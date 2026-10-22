#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <MediaPlayer/MediaPlayer.h>
#import <objc/runtime.h>
#import <AudioToolbox/AudioToolbox.h>
#import <math.h>

static NSString * const SRAccentChangedNotification = @"SRAccentChangedNotification";
static NSString * const SRAudioStateChangedNotification = @"SRAudioStateChangedNotification";
static NSString * const SRNextTrackNotification = @"SRNextTrackNotification";
static NSString * const SRPreviousTrackNotification = @"SRPreviousTrackNotification";
static NSString * const SRTrackChangedNotification = @"SRTrackChangedNotification";
static NSString * const SRTrackEndedNotification = @"SRTrackEndedNotification";

static UIColor *BG(void){ return [UIColor colorWithRed:.035 green:.045 blue:.075 alpha:1]; }
static UIColor *CARD(void){ return [UIColor colorWithRed:.13 green:.15 blue:.21 alpha:.88]; }
static UIColor *SUBTLE(void){ return [UIColor colorWithWhite:.62 alpha:1]; }
static UIColor *ACCENT(void){
    NSUserDefaults *d=NSUserDefaults.standardUserDefaults;
    if([d objectForKey:@"accent.r"]){
        return [UIColor colorWithRed:[d floatForKey:@"accent.r"] green:[d floatForKey:@"accent.g"] blue:[d floatForKey:@"accent.b"] alpha:1];
    }
    return [UIColor colorWithRed:.24 green:.64 blue:.95 alpha:1];
}
static void SaveAccent(UIColor *c){
    CGFloat r=0,g=0,b=0,a=0; if(![c getRed:&r green:&g blue:&b alpha:&a]) return;
    NSUserDefaults *d=NSUserDefaults.standardUserDefaults;
    [d setFloat:r forKey:@"accent.r"]; [d setFloat:g forKey:@"accent.g"]; [d setFloat:b forKey:@"accent.b"];
    [NSNotificationCenter.defaultCenter postNotificationName:SRAccentChangedNotification object:nil];
}

static AVAudioUnitReverbPreset SRReverbPreset(NSInteger index){
    switch(index){
        case 1:return AVAudioUnitReverbPresetSmallRoom;
        case 2:return AVAudioUnitReverbPresetMediumRoom;
        case 3:return AVAudioUnitReverbPresetLargeRoom;
        case 4:return AVAudioUnitReverbPresetMediumHall;
        case 5:return AVAudioUnitReverbPresetLargeHall;
        case 6:return AVAudioUnitReverbPresetPlate;
        case 7:return AVAudioUnitReverbPresetMediumChamber;
        case 8:return AVAudioUnitReverbPresetLargeChamber;
        case 9:return AVAudioUnitReverbPresetCathedral;
        case 10:return AVAudioUnitReverbPresetLargeRoom2;
        case 11:return AVAudioUnitReverbPresetMediumHall2;
        case 12:return AVAudioUnitReverbPresetMediumHall3;
        default:return AVAudioUnitReverbPresetLargeHall2;
    }
}
static NSString *SRReverbName(NSInteger index){
    switch(index){
        case 1:return @"Small Room"; case 2:return @"Medium Room"; case 3:return @"Large Room";
        case 4:return @"Medium Hall"; case 5:return @"Large Hall"; case 6:return @"Plate";
        case 7:return @"Medium Chamber"; case 8:return @"Large Chamber"; case 9:return @"Cathedral";
        case 10:return @"Large Room 2"; case 11:return @"Medium Hall 2"; case 12:return @"Medium Hall 3";
        default:return @"Large Hall 2";
    }
}

static NSString * const MelodiaLibraryChanged = @"MelodiaLibraryChanged";
static NSArray *MelodiaSections(void) { return @[@"Songs",@"Favorites",@"Albums",@"Artists",@"Recently Added"]; }
static BOOL MelodiaSectionEnabled(NSString *section) {
    NSString *key=[@"section." stringByAppendingString:section];
    return [NSUserDefaults.standardUserDefaults objectForKey:key] ? [NSUserDefaults.standardUserDefaults boolForKey:key] : YES;
}
static BOOL MelodiaIsFavorite(NSURL *url) {
    if(!url)return NO;
    return [[NSUserDefaults.standardUserDefaults stringArrayForKey:@"favorites"] containsObject:url.lastPathComponent];
}
static void MelodiaSetFavorite(NSURL *url, BOOL value) {
    if(!url)return;
    NSMutableArray *favorites=[[NSUserDefaults.standardUserDefaults stringArrayForKey:@"favorites"] mutableCopy]?:[NSMutableArray new];
    [favorites removeObject:url.lastPathComponent]; if(value)[favorites addObject:url.lastPathComponent];
    [NSUserDefaults.standardUserDefaults setObject:favorites forKey:@"favorites"];
    [NSNotificationCenter.defaultCenter postNotificationName:MelodiaLibraryChanged object:nil];
}
static UIImage *MelodiaArtwork(NSURL *url);
static UIImage *MelodiaPlaceholder(void);
static NSString *MelodiaArtist(NSURL *url);

@interface TrackSettings : NSObject
@property float speed, pitch, reverb, bass;
@property NSInteger reverbPreset;
@property BOOL eightDEnabled;
@property float eightDPeriod;
@property NSInteger currentReverbPreset;
@end
@implementation TrackSettings @end

@interface AudioController : NSObject
@property (nonatomic, strong) AVAudioEngine *engine;
@property (nonatomic, strong) AVAudioPlayerNode *player;
@property (nonatomic, strong) AVAudioUnitTimePitch *timePitch;
@property (nonatomic, strong) AVAudioUnitReverb *reverb;
@property (nonatomic, strong) AVAudioUnitEQ *eq;
@property (nonatomic, strong) AVAudioFile *file;
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, copy) NSString *nowPlayingTitle;
@property BOOL playing;
@property BOOL wasPlayingBeforeInterruption;
@property float currentSpeed;
@property float outputVolume;
@property BOOL eightDEnabled;
@property float eightDPeriod;
@property NSInteger currentReverbPreset;
@property NSTimeInterval eightDStartedAt;
@property (nonatomic, strong) NSTimer *eightDTimer;
@property NSTimeInterval duration;
@property NSTimeInterval position;
@property NSTimeInterval playStartedAt;
@property NSInteger scheduleGeneration;
- (BOOL)load:(NSURL*)url error:(NSError**)error;
- (void)playPause;
- (void)stop;
- (void)apply:(TrackSettings*)s;
- (void)updateNowPlaying;
- (void)seekTo:(NSTimeInterval)seconds;
- (NSTimeInterval)currentTime;
- (void)setEightDEnabled:(BOOL)enabled period:(float)period;
@end

@implementation AudioController
- (instancetype)init {
    if((self=[super init])){
        _engine=[AVAudioEngine new]; _player=[AVAudioPlayerNode new];
        _timePitch=[AVAudioUnitTimePitch new]; _reverb=[AVAudioUnitReverb new]; _eq=[[AVAudioUnitEQ alloc] initWithNumberOfBands:1];
        _currentSpeed=1.0f; _outputVolume=1.0f; _eightDEnabled=NO; _eightDPeriod=7.0f; _currentReverbPreset=0;
        AVAudioUnitEQFilterParameters *b=_eq.bands[0]; b.filterType=AVAudioUnitEQFilterTypeLowShelf; b.frequency=180; b.bandwidth=1; b.bypass=NO;
        [_reverb loadFactoryPreset:AVAudioUnitReverbPresetLargeHall2];
        [_engine attachNode:_player]; [_engine attachNode:_timePitch]; [_engine attachNode:_eq]; [_engine attachNode:_reverb];
        [_engine connect:_player to:_timePitch format:nil]; [_engine connect:_timePitch to:_eq format:nil]; [_engine connect:_eq to:_reverb format:nil]; [_engine connect:_reverb to:_engine.mainMixerNode format:nil]; _engine.mainMixerNode.outputVolume=_outputVolume;
        AVAudioSession *s=AVAudioSession.sharedInstance;
        [s setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:0 error:nil];
        [s setActive:YES error:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(interruption:) name:AVAudioSessionInterruptionNotification object:s];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(routeChanged:) name:AVAudioSessionRouteChangeNotification object:s];
        MPRemoteCommandCenter *cc=MPRemoteCommandCenter.sharedCommandCenter;
        cc.playCommand.enabled=YES; cc.pauseCommand.enabled=YES; cc.togglePlayPauseCommand.enabled=YES;
        cc.changePlaybackPositionCommand.enabled=YES;
        cc.skipForwardCommand.enabled=NO; cc.skipBackwardCommand.enabled=NO;
        cc.seekForwardCommand.enabled=NO; cc.seekBackwardCommand.enabled=NO;
        cc.nextTrackCommand.enabled=YES; cc.previousTrackCommand.enabled=YES;
        [cc.playCommand addTarget:self action:@selector(remotePlay:)];
        [cc.pauseCommand addTarget:self action:@selector(remotePause:)];
        [cc.togglePlayPauseCommand addTarget:self action:@selector(remoteToggle:)];
        [cc.changePlaybackPositionCommand addTarget:self action:@selector(remoteSeek:)];
        [cc.nextTrackCommand addTarget:self action:@selector(remoteNext:)];
        [cc.previousTrackCommand addTarget:self action:@selector(remotePrevious:)];
    } return self;
}
- (void)scheduleFromPosition {
    if(!self.file) return;
    self.scheduleGeneration+=1; NSInteger generation=self.scheduleGeneration;
    AVAudioFramePosition frame=(AVAudioFramePosition)llround(MAX(0,MIN(self.duration,self.position))*self.file.processingFormat.sampleRate);
    frame=MIN(frame,self.file.length);
    AVAudioFrameCount count=(AVAudioFrameCount)MIN((AVAudioFramePosition)UINT32_MAX,MAX((AVAudioFramePosition)0,self.file.length-frame));
    [self.player stop];
    if(count==0){ self.position=self.duration; self.playing=NO; return; }
    __block AudioController *me=self;
    [self.player scheduleSegment:self.file startingFrame:frame frameCount:count atTime:nil completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if(generation!=me.scheduleGeneration) return;
            me.position=me.duration; me.playing=NO; me.playStartedAt=0; [me updateNowPlaying]; [NSNotificationCenter.defaultCenter postNotificationName:SRAudioStateChangedNotification object:me]; [NSNotificationCenter.defaultCenter postNotificationName:SRTrackEndedNotification object:me];
        });
    }];
}
- (BOOL)load:(NSURL*)url error:(NSError**)error {
    [self stop]; self.url=url; self.nowPlayingTitle=url.lastPathComponent.stringByDeletingPathExtension;
    self.file=[[AVAudioFile alloc] initForReading:url error:error]; if(!self.file) return NO;
    self.duration=(double)self.file.length/self.file.processingFormat.sampleRate; self.position=0; self.playStartedAt=0;
    [self scheduleFromPosition];
    if(!self.engine.running && ![self.engine startAndReturnError:error]) return NO;
    [self updateNowPlaying]; return YES;
}
- (NSTimeInterval)currentTime {
    NSTimeInterval p=self.position;
    if(self.playing && self.playStartedAt>0) p+=(NSDate.timeIntervalSinceReferenceDate-self.playStartedAt)*MAX(.01f,self.currentSpeed);
    return MAX(0,MIN(self.duration,p));
}
- (void)playPause {
    if(!self.file)return;
    if(self.playing){ self.position=[self currentTime]; [self.player pause]; self.playing=NO; self.playStartedAt=0; }
    else {
        if(self.position>=self.duration-.01){ self.position=0; [self scheduleFromPosition]; }
        [AVAudioSession.sharedInstance setActive:YES error:nil]; if(!self.engine.running)[self.engine startAndReturnError:nil];
        [self.player play]; self.playing=YES; self.playStartedAt=NSDate.timeIntervalSinceReferenceDate;
    }
    [self updateNowPlaying]; [NSNotificationCenter.defaultCenter postNotificationName:SRAudioStateChangedNotification object:self];
}
- (void)stop { self.scheduleGeneration+=1; if(self.player){[self.player stop];self.playing=NO;} self.position=0; self.playStartedAt=0; [self updateNowPlaying]; }
- (void)apply:(TrackSettings*)s {
    if(self.playing){ self.position=[self currentTime]; self.playStartedAt=NSDate.timeIntervalSinceReferenceDate; }
    self.currentSpeed=s.speed; self.timePitch.rate=s.speed; self.timePitch.pitch=s.pitch; self.currentReverbPreset=s.reverbPreset; [self.reverb loadFactoryPreset:SRReverbPreset(s.reverbPreset)]; self.reverb.wetDryMix=s.reverb; self.eq.bands[0].gain=s.bass; [self setEightDEnabled:s.eightDEnabled period:s.eightDPeriod]; [self updateNowPlaying];
}
- (void)updateEightD:(NSTimer*)timer {
    if(!self.eightDEnabled || !self.player){ if(self.player)self.player.pan=0; return; }
    NSTimeInterval elapsed=NSDate.timeIntervalSinceReferenceDate-self.eightDStartedAt;
    float period=MAX(2.0f,self.eightDPeriod);
    self.player.pan=sinf((float)(elapsed/period*2.0*M_PI))*.92f;
}
- (void)setEightDEnabled:(BOOL)enabled period:(float)period {
    float resolved=MAX(2.0f,period);
    BOOL changed=(self.eightDEnabled!=enabled || fabsf(self.eightDPeriod-resolved)>.01f || (enabled && self.eightDTimer==nil));
    self.eightDEnabled=enabled; self.eightDPeriod=resolved;
    if(!changed){ if(!enabled && self.player)self.player.pan=0; return; }
    [self.eightDTimer invalidate]; self.eightDTimer=nil;
    if(enabled){ self.eightDStartedAt=NSDate.timeIntervalSinceReferenceDate; self.eightDTimer=[NSTimer scheduledTimerWithTimeInterval:.035 target:self selector:@selector(updateEightD:) userInfo:nil repeats:YES]; [self updateEightD:self.eightDTimer]; }
    else if(self.player) self.player.pan=0;
}
- (void)seekTo:(NSTimeInterval)seconds {
    if(!self.file)return; BOOL resume=self.playing;
    self.position=MAX(0,MIN(self.duration,seconds)); self.playing=NO; self.playStartedAt=0;
    [self scheduleFromPosition];
    if(resume && self.position<self.duration){ [AVAudioSession.sharedInstance setActive:YES error:nil]; if(!self.engine.running)[self.engine startAndReturnError:nil]; [self.player play]; self.playing=YES; self.playStartedAt=NSDate.timeIntervalSinceReferenceDate; }
    [self updateNowPlaying]; [NSNotificationCenter.defaultCenter postNotificationName:SRAudioStateChangedNotification object:self];
}
- (void)updateNowPlaying {
    if(!self.nowPlayingTitle.length){ MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo=nil; return; }
    NSMutableDictionary *info=[NSMutableDictionary dictionary];
    info[MPMediaItemPropertyTitle]=self.nowPlayingTitle;
    info[MPMediaItemPropertyArtist]=MelodiaArtist(self.url);
    info[MPMediaItemPropertyPlaybackDuration]=@(MAX(0,self.duration));
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime]=@([self currentTime]);
    info[MPNowPlayingInfoPropertyPlaybackRate]=@(self.playing?self.currentSpeed:0);
    info[MPNowPlayingInfoPropertyDefaultPlaybackRate]=@(self.currentSpeed);
    UIImage *icon=MelodiaArtwork(self.url)?:MelodiaPlaceholder();
    if(icon){ MPMediaItemArtwork *art=[[MPMediaItemArtwork alloc] initWithBoundsSize:icon.size requestHandler:^UIImage * _Nonnull(CGSize size) { return icon; }]; info[MPMediaItemPropertyArtwork]=art; }
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo=info;
}
- (MPRemoteCommandHandlerStatus)remotePlay:(MPRemoteCommandEvent*)e { if(!self.file) return MPRemoteCommandHandlerStatusNoSuchContent; if(!self.playing)[self playPause]; return MPRemoteCommandHandlerStatusSuccess; }
- (MPRemoteCommandHandlerStatus)remotePause:(MPRemoteCommandEvent*)e { if(!self.file) return MPRemoteCommandHandlerStatusNoSuchContent; if(self.playing)[self playPause]; return MPRemoteCommandHandlerStatusSuccess; }
- (MPRemoteCommandHandlerStatus)remoteToggle:(MPRemoteCommandEvent*)e { if(!self.file) return MPRemoteCommandHandlerStatusNoSuchContent; [self playPause]; return MPRemoteCommandHandlerStatusSuccess; }
- (MPRemoteCommandHandlerStatus)remoteSeek:(MPRemoteCommandEvent*)e { if(!self.file || ![e isKindOfClass:MPChangePlaybackPositionCommandEvent.class]) return MPRemoteCommandHandlerStatusCommandFailed; [self seekTo:((MPChangePlaybackPositionCommandEvent*)e).positionTime]; return MPRemoteCommandHandlerStatusSuccess; }
- (MPRemoteCommandHandlerStatus)remoteNext:(MPRemoteCommandEvent*)e { if(!self.file) return MPRemoteCommandHandlerStatusNoSuchContent; dispatch_async(dispatch_get_main_queue(), ^{ [NSNotificationCenter.defaultCenter postNotificationName:SRNextTrackNotification object:self]; }); return MPRemoteCommandHandlerStatusSuccess; }
- (MPRemoteCommandHandlerStatus)remotePrevious:(MPRemoteCommandEvent*)e { if(!self.file) return MPRemoteCommandHandlerStatusNoSuchContent; dispatch_async(dispatch_get_main_queue(), ^{ [NSNotificationCenter.defaultCenter postNotificationName:SRPreviousTrackNotification object:self]; }); return MPRemoteCommandHandlerStatusSuccess; }
- (void)interruption:(NSNotification*)n {
    NSNumber *t=n.userInfo[AVAudioSessionInterruptionTypeKey];
    if(t.integerValue==AVAudioSessionInterruptionTypeBegan){ self.wasPlayingBeforeInterruption=self.playing; if(self.playing){self.position=[self currentTime];[self.player pause];self.playing=NO;self.playStartedAt=0;} [self updateNowPlaying]; }
    else { [AVAudioSession.sharedInstance setActive:YES error:nil]; if(!self.engine.running)[self.engine startAndReturnError:nil]; NSNumber *opts=n.userInfo[AVAudioSessionInterruptionOptionKey]; if(self.wasPlayingBeforeInterruption && (opts.unsignedIntegerValue&AVAudioSessionInterruptionOptionShouldResume)){[self.player play];self.playing=YES;self.playStartedAt=NSDate.timeIntervalSinceReferenceDate;} self.wasPlayingBeforeInterruption=NO; [self updateNowPlaying]; [NSNotificationCenter.defaultCenter postNotificationName:SRAudioStateChangedNotification object:self]; }
}
- (void)routeChanged:(NSNotification*)n { [AVAudioSession.sharedInstance setActive:YES error:nil]; if(self.file && !self.engine.running)[self.engine startAndReturnError:nil]; [self updateNowPlaying]; }
- (void)dealloc { [self.eightDTimer invalidate]; [NSNotificationCenter.defaultCenter removeObserver:self]; }
@end

@class LibraryVC;
@interface PlayerVC : UIViewController
@property (nonatomic, strong) NSURL *trackURL;
@property (nonatomic, assign) LibraryVC *library;
@property (nonatomic, strong) AudioController *audio;
@property (nonatomic, strong) TrackSettings *settings;
@property (nonatomic, strong) UILabel *titleLabel,*elapsedLabel,*remainingLabel;
@property (nonatomic, strong) UIButton *playButton,*saveButton,*exportButton,*previousButton,*nextButton,*shuffleButton,*repeatButton,*reverbTypeButton,*eightDButton,*slowedPresetButton,*nightcorePresetButton,*resetButton;
@property (nonatomic, strong) UISlider *progressSlider,*volumeSlider;
@property (nonatomic, strong) UIImageView *coverView,*backgroundCover;
@property (nonatomic, strong) UILabel *artistLabel;
@property (nonatomic, strong) UIButton *favoriteButton;
@property (nonatomic, strong) NSTimer *progressTimer;
@property (nonatomic, strong) NSMutableDictionary<NSNumber*,UISlider*> *sliders;
@property (nonatomic, strong) NSMutableSet<NSNumber*> *steppedTags;
@property BOOL scrubbing;
@end

@interface SettingsVC : UIViewController
@property (nonatomic, strong) UIColorWell *colorWell;
@property (nonatomic, strong) UIView *preview;
@property (nonatomic, strong) UIScrollView *preferencesScroll;
@end

@interface LibraryVC : UIViewController <UITableViewDataSource,UITableViewDelegate,UIDocumentPickerDelegate,UISearchBarDelegate>
@property (nonatomic, strong) NSMutableArray<NSURL*> *tracks;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) AudioController *audio;
@property (nonatomic, strong) UIButton *nowPlayingButton;
@property (nonatomic, strong) UIVisualEffectView *glassDock;
@property (nonatomic, strong) NSMutableArray<UIButton*> *dockButtons;
@property (nonatomic, strong) UIButton *miniPlayer, *miniPlay;
@property (nonatomic, strong) UIImageView *miniArtwork;
@property (nonatomic, strong) UILabel *miniTitleLabel,*miniArtistLabel;
@property (nonatomic, strong) UISegmentedControl *libraryMode;
@property (nonatomic, copy) NSString *activeMode;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSArray<NSURL*> *visibleTracks;
@property BOOL shuffleEnabled;
@property NSInteger repeatMode;
- (TrackSettings*)settingsFor:(NSURL*)u;
- (void)saveSettings:(TrackSettings*)s forURL:(NSURL*)u;
- (void)playTrackAtIndex:(NSInteger)i;
- (void)playTrackURL:(NSURL*)u;
- (NSInteger)nextIndexFrom:(NSInteger)i;
- (NSInteger)previousIndexFrom:(NSInteger)i;
@end

static UIImage *MelodiaArtwork(NSURL *url) {
    if(!url) return nil;
    AVURLAsset *asset=[AVURLAsset URLAssetWithURL:url options:nil];
    for(AVMetadataItem *item in [AVMetadataItem metadataItemsFromArray:asset.commonMetadata withKey:AVMetadataCommonKeyArtwork keySpace:AVMetadataKeySpaceCommon]) {
        NSData *data=nil;
        if([item.value isKindOfClass:NSData.class]) data=(NSData*)item.value;
        else if([item.value isKindOfClass:NSDictionary.class]) data=[(NSDictionary*)item.value objectForKey:@"data"];
        if(data.length){ UIImage *image=[UIImage imageWithData:data]; if(image)return image; }
    }
    return nil;
}
static NSString *MelodiaArtist(NSURL *url) {
    if(!url) return @"Unknown Artist";
    AVURLAsset *asset=[AVURLAsset URLAssetWithURL:url options:nil];
    NSArray *items=[AVMetadataItem metadataItemsFromArray:asset.commonMetadata withKey:AVMetadataCommonKeyArtist keySpace:AVMetadataKeySpaceCommon];
    for(AVMetadataItem *item in items) { NSString *name=item.stringValue; if(name.length) return name; }
    return @"Unknown Artist";
}
static UIImage *MelodiaPlaceholder(void) {
    CGSize size=CGSizeMake(80,80);
    UIGraphicsBeginImageContextWithOptions(size,YES,0);
    [[UIColor colorWithRed:.19 green:.20 blue:.23 alpha:1] setFill]; UIRectFill((CGRect){CGPointZero,size});
    UIImage *symbol=[UIImage systemImageNamed:@"music.note"];
    symbol=[symbol imageWithTintColor:[UIColor colorWithWhite:.70 alpha:1] renderingMode:UIImageRenderingModeAlwaysOriginal];
    [symbol drawInRect:CGRectMake(24,21,32,38)];
    UIImage *result=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return result;
}

static UILabel *Label(NSString *text, CGFloat size, UIFontWeight weight){ UILabel*l=[UILabel new];l.text=text;l.textColor=UIColor.whiteColor;l.font=[UIFont systemFontOfSize:size weight:weight];l.translatesAutoresizingMaskIntoConstraints=NO;return l; }
static UIButton *Button(NSString *title){ UIButton*b=[UIButton buttonWithType:UIButtonTypeSystem];[b setTitle:title forState:UIControlStateNormal];[b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];b.backgroundColor=CARD();b.layer.cornerRadius=18;b.titleLabel.font=[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];b.translatesAutoresizingMaskIntoConstraints=NO;return b; }

@implementation SettingsVC
- (void)viewDidLoad { [super viewDidLoad]; self.view.backgroundColor=BG(); self.title=@"Appearance"; self.navigationController.navigationBar.tintColor=UIColor.whiteColor;
    UILabel *title=Label(@"Accent color",22,UIFontWeightBold); [self.view addSubview:title];
    UILabel *sub=Label(@"Choose an accent color for Melodia. System glass follows iOS appearance settings.",14,UIFontWeightRegular); sub.textColor=SUBTLE(); sub.numberOfLines=0; [self.view addSubview:sub];
    self.colorWell=[UIColorWell new]; self.colorWell.selectedColor=ACCENT(); self.colorWell.supportsAlpha=NO; self.colorWell.translatesAutoresizingMaskIntoConstraints=NO; [self.colorWell addTarget:self action:@selector(colorChanged:) forControlEvents:UIControlEventValueChanged]; [self.view addSubview:self.colorWell];
    self.preview=[UIView new]; self.preview.backgroundColor=ACCENT(); self.preview.layer.cornerRadius=22; self.preview.translatesAutoresizingMaskIntoConstraints=NO; [self.view addSubview:self.preview];
    UILabel *p=Label(@"Melodia Accent",16,UIFontWeightSemibold); [self.preview addSubview:p];
    UIButton *reset=Button(@"Reset to blue"); [reset addTarget:self action:@selector(reset) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:reset];
    [NSLayoutConstraint activateConstraints:@[[title.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:28],[title.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:28],[sub.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8],[sub.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],[sub.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-28],[self.colorWell.topAnchor constraintEqualToAnchor:sub.bottomAnchor constant:26],[self.colorWell.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],[self.colorWell.widthAnchor constraintEqualToConstant:64],[self.colorWell.heightAnchor constraintEqualToConstant:44],[self.preview.topAnchor constraintEqualToAnchor:self.colorWell.bottomAnchor constant:28],[self.preview.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],[self.preview.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-28],[self.preview.heightAnchor constraintEqualToConstant:52],[p.centerXAnchor constraintEqualToAnchor:self.preview.centerXAnchor],[p.centerYAnchor constraintEqualToAnchor:self.preview.centerYAnchor],[reset.topAnchor constraintEqualToAnchor:self.preview.bottomAnchor constant:18],[reset.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],[reset.heightAnchor constraintEqualToConstant:44],[reset.widthAnchor constraintEqualToConstant:160]]];
    UILabel *sectionTitle=Label(@"Library sections",21,UIFontWeightBold); [self.view addSubview:sectionTitle];
    [NSLayoutConstraint activateConstraints:@[[sectionTitle.topAnchor constraintEqualToAnchor:reset.bottomAnchor constant:28],[sectionTitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor]]];
    UIView *previous=sectionTitle;
    for(NSString *name in MelodiaSections()) {
        UILabel *label=Label(name,16,UIFontWeightMedium); [self.view addSubview:label];
        UISwitch *toggle=[UISwitch new]; toggle.on=MelodiaSectionEnabled(name); toggle.accessibilityLabel=name;
        toggle.translatesAutoresizingMaskIntoConstraints=NO;
        objc_setAssociatedObject(toggle,@selector(sectionChanged:),name,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [toggle addTarget:self action:@selector(sectionChanged:) forControlEvents:UIControlEventValueChanged]; [self.view addSubview:toggle];
        [NSLayoutConstraint activateConstraints:@[[label.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],[label.centerYAnchor constraintEqualToAnchor:toggle.centerYAnchor],[toggle.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-30],[toggle.topAnchor constraintEqualToAnchor:previous.bottomAnchor constant:16]]];
        previous=toggle;
    }
    UILabel *sortLabel=Label(@"Sort songs",18,UIFontWeightSemibold); [self.view addSubview:sortLabel];
    UISegmentedControl *sort=[[UISegmentedControl alloc] initWithItems:@[@"Title",@"Artist",@"Recent"]];
    sort.translatesAutoresizingMaskIntoConstraints=NO; sort.selectedSegmentIndex=[NSUserDefaults.standardUserDefaults integerForKey:@"library.sort"];
    [sort addTarget:self action:@selector(sortChanged:) forControlEvents:UIControlEventValueChanged]; [self.view addSubview:sort];
    [NSLayoutConstraint activateConstraints:@[[sortLabel.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],[sortLabel.topAnchor constraintEqualToAnchor:previous.bottomAnchor constant:24],[sort.topAnchor constraintEqualToAnchor:sortLabel.bottomAnchor constant:12],[sort.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],[sort.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-28]]];
}
- (void)sectionChanged:(UISwitch*)sender {
    NSString *name=objc_getAssociatedObject(sender,@selector(sectionChanged:));
    [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:[@"section." stringByAppendingString:name]];
    [NSNotificationCenter.defaultCenter postNotificationName:MelodiaLibraryChanged object:nil];
}
- (void)sortChanged:(UISegmentedControl*)sender {
    [NSUserDefaults.standardUserDefaults setInteger:sender.selectedSegmentIndex forKey:@"library.sort"];
    [NSNotificationCenter.defaultCenter postNotificationName:MelodiaLibraryChanged object:nil];
}
- (void)colorChanged:(UIColorWell*)w { if(w.selectedColor){SaveAccent(w.selectedColor);self.preview.backgroundColor=w.selectedColor;} }
- (void)reset { UIColor*c=[UIColor colorWithRed:.24 green:.64 blue:.95 alpha:1];self.colorWell.selectedColor=c;SaveAccent(c);self.preview.backgroundColor=c; }
@end

@interface MelodiaSearchDelegate : NSObject <UITableViewDataSource,UITableViewDelegate,UISearchResultsUpdating>
@property (nonatomic, assign) LibraryVC *library;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<NSURL*> *results;
- (instancetype)initWithLibrary:(LibraryVC*)library table:(UITableView*)table;
@end
@implementation MelodiaSearchDelegate
- (instancetype)initWithLibrary:(LibraryVC*)library table:(UITableView*)table {
    if((self=[super init])) { _library=library; _table=table; _results=[library.tracks copy]; } return self;
}
- (void)updateSearchResultsForSearchController:(UISearchController*)controller {
    NSString *query=controller.searchBar.text?:@"";
    if(!query.length) self.results=[self.library.tracks copy];
    else self.results=[self.library.tracks filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSURL *url, NSDictionary *bindings) {
        return [url.lastPathComponent localizedCaseInsensitiveContainsString:query] || [MelodiaArtist(url) localizedCaseInsensitiveContainsString:query];
    }]];
    [self.table reloadData];
}
- (NSInteger)tableView:(UITableView*)table numberOfRowsInSection:(NSInteger)section { return self.results.count; }
- (UITableViewCell*)tableView:(UITableView*)table cellForRowAtIndexPath:(NSIndexPath*)path {
    UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:@"search"];
    if(!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"search"];
    NSURL *url=self.results[path.row]; cell.backgroundColor=UIColor.clearColor;
    cell.textLabel.text=url.lastPathComponent.stringByDeletingPathExtension;
    cell.textLabel.textColor=UIColor.whiteColor; cell.textLabel.font=[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    cell.detailTextLabel.text=MelodiaArtist(url); cell.detailTextLabel.textColor=SUBTLE();
    cell.imageView.image=MelodiaArtwork(url)?:MelodiaPlaceholder();
    cell.imageView.layer.cornerRadius=8; cell.imageView.clipsToBounds=YES;
    return cell;
}
- (void)tableView:(UITableView*)table didSelectRowAtIndexPath:(NSIndexPath*)path {
    [table deselectRowAtIndexPath:path animated:YES]; NSURL *url=self.results[path.row];
    if(![self.library.audio.url isEqual:url]) [self.library playTrackURL:url];
    else if(!self.library.audio.playing) [self.library.audio playPause];
    [self.library updateNowPlayingButton];
}
@end

@implementation LibraryVC
- (void)viewDidLoad { [super viewDidLoad]; self.view.backgroundColor=BG(); self.audio=[AudioController new]; self.tracks=[NSMutableArray new];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(remoteNextTrack:) name:SRNextTrackNotification object:self.audio];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(remotePreviousTrack:) name:SRPreviousTrackNotification object:self.audio];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(audioLibraryStateChanged:) name:SRAudioStateChangedNotification object:self.audio];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(trackEnded:) name:SRTrackEndedNotification object:self.audio];
    self.shuffleEnabled=[NSUserDefaults.standardUserDefaults boolForKey:@"playback.shuffle"]; self.repeatMode=[NSUserDefaults.standardUserDefaults integerForKey:@"playback.repeatMode"];
    
    UILabel *library=Label(@"Library",34,UIFontWeightBold); [self.view addSubview:library];
    self.nowPlayingButton=Button(@"Now Playing"); self.nowPlayingButton.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]; self.nowPlayingButton.hidden=YES; [self.nowPlayingButton addTarget:self action:@selector(openNowPlaying) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:self.nowPlayingButton];
    self.table=[[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain]; self.table.backgroundColor=UIColor.clearColor; self.table.separatorColor=[UIColor colorWithWhite:.16 alpha:1]; self.table.rowHeight=62; self.table.dataSource=self; self.table.delegate=self; self.table.translatesAutoresizingMaskIntoConstraints=NO; [self.view addSubview:self.table];
    [NSLayoutConstraint activateConstraints:@[[library.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:24],[library.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],[self.nowPlayingButton.centerYAnchor constraintEqualToAnchor:library.centerYAnchor],[self.nowPlayingButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],[self.nowPlayingButton.widthAnchor constraintGreaterThanOrEqualToConstant:108],[self.nowPlayingButton.heightAnchor constraintEqualToConstant:34],[self.table.topAnchor constraintEqualToAnchor:library.bottomAnchor constant:10],[self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:18],[self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-18],[self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]]];
    // Floating translucent controls are separate from the original audio engine.
    // Prefer Apple's native glass effect when the installed iOS SDK/runtime supports it.
    // Use a standard system material on older iOS versions.
    Class glassClass=NSClassFromString(@"UIGlassEffect");
    UIVisualEffect *effect=glassClass ? [[glassClass alloc] init] : [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    self.glassDock=[[UIVisualEffectView alloc] initWithEffect:effect];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateDockAccent) name:SRAccentChangedNotification object:nil];
    self.glassDock.translatesAutoresizingMaskIntoConstraints=NO;
    self.glassDock.layer.cornerRadius=28;
    self.glassDock.layer.masksToBounds=YES;
    self.glassDock.layer.borderWidth=.8;
    self.glassDock.layer.borderColor=[UIColor colorWithWhite:1 alpha:.16].CGColor;
    [self.view addSubview:self.glassDock];
    UIStackView *tabs=[UIStackView new]; tabs.axis=UILayoutConstraintAxisHorizontal;tabs.distribution=UIStackViewDistributionFillEqually;tabs.translatesAutoresizingMaskIntoConstraints=NO;
    [self.glassDock.contentView addSubview:tabs];
    NSArray *symbols=@[@"square.stack.fill",@"square.and.arrow.down",@"magnifyingglass",@"gearshape.fill"];
    NSArray *names=@[@"Library",@"Import",@"Search",@"Settings"];
    self.dockButtons=[NSMutableArray new];
    for(NSInteger j=0;j<4;j++){
        UIButton *tab=[UIButton buttonWithType:UIButtonTypeSystem];tab.tag=500+j;
        [tab setImage:[UIImage systemImageNamed:symbols[j]] forState:UIControlStateNormal];
        [tab setTitle:[@"\n" stringByAppendingString:names[j]] forState:UIControlStateNormal];
        tab.titleLabel.font=[UIFont systemFontOfSize:10 weight:UIFontWeightMedium];tab.titleLabel.numberOfLines=2;
        tab.tintColor=j==0?ACCENT():UIColor.whiteColor;
        [tab setTitleColor:tab.tintColor forState:UIControlStateNormal];
        tab.contentHorizontalAlignment=UIControlContentHorizontalAlignmentCenter;
        tab.imageView.contentMode=UIViewContentModeScaleAspectFit;
        [tab addTarget:self action:@selector(dockTapped:) forControlEvents:UIControlEventTouchUpInside];
        [tabs addArrangedSubview:tab];
        [self.dockButtons addObject:tab];
    }
    self.miniPlayer=Button(@"♪  Choose a song");self.miniPlayer.titleLabel.lineBreakMode=NSLineBreakByTruncatingTail;
    self.miniPlayer.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;
    self.miniPlayer.contentEdgeInsets=UIEdgeInsetsMake(0,70,0,60);
    self.miniPlayer.backgroundColor=[UIColor colorWithRed:.16 green:.18 blue:.21 alpha:.85];
    self.miniPlayer.layer.cornerRadius=19;self.miniPlayer.hidden=YES;
    [self.miniPlayer addTarget:self action:@selector(openNowPlaying) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.miniPlayer];
    self.miniArtwork=[UIImageView new]; self.miniArtwork.translatesAutoresizingMaskIntoConstraints=NO;
    self.miniArtwork.contentMode=UIViewContentModeScaleAspectFill; self.miniArtwork.clipsToBounds=YES;
    self.miniArtwork.layer.cornerRadius=11; self.miniArtwork.hidden=YES;
    [self.view addSubview:self.miniArtwork];
    self.miniTitleLabel=Label(@"",14,UIFontWeightSemibold); self.miniTitleLabel.lineBreakMode=NSLineBreakByTruncatingTail;
    self.miniArtistLabel=Label(@"",11,UIFontWeightRegular); self.miniArtistLabel.textColor=SUBTLE();
    [self.view addSubview:self.miniTitleLabel]; [self.view addSubview:self.miniArtistLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.miniTitleLabel.leadingAnchor constraintEqualToAnchor:self.miniArtwork.trailingAnchor constant:12],
        [self.miniTitleLabel.trailingAnchor constraintEqualToAnchor:self.miniPlayer.trailingAnchor constant:-62],
        [self.miniTitleLabel.bottomAnchor constraintEqualToAnchor:self.miniPlayer.centerYAnchor constant:-1],
        [self.miniArtistLabel.leadingAnchor constraintEqualToAnchor:self.miniTitleLabel.leadingAnchor],
        [self.miniArtistLabel.trailingAnchor constraintEqualToAnchor:self.miniTitleLabel.trailingAnchor],
        [self.miniArtistLabel.topAnchor constraintEqualToAnchor:self.miniPlayer.centerYAnchor constant:2]]];
    UITapGestureRecognizer *artTap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openNowPlaying)];
    self.miniArtwork.userInteractionEnabled=YES; [self.miniArtwork addGestureRecognizer:artTap];
    self.miniPlay=[UIButton buttonWithType:UIButtonTypeSystem];self.miniPlay.translatesAutoresizingMaskIntoConstraints=NO;
    [self.miniPlay setImage:[UIImage systemImageNamed:@"pause.fill"] forState:UIControlStateNormal];
    self.miniPlay.tintColor=UIColor.whiteColor;self.miniPlay.hidden=YES;
    [self.miniPlay addTarget:self action:@selector(toggleMiniPlayback) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.miniPlay];
    self.searchBar=[UISearchBar new];self.searchBar.translatesAutoresizingMaskIntoConstraints=NO;
    self.searchBar.searchBarStyle=UISearchBarStyleMinimal;self.searchBar.placeholder=@"Search songs";
    self.searchBar.hidden=YES;self.searchBar.delegate=self;
    [self.view addSubview:self.searchBar];
    [NSLayoutConstraint activateConstraints:@[
        [self.glassDock.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.glassDock.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.glassDock.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8],
        [self.glassDock.heightAnchor constraintEqualToConstant:66],
        [tabs.leadingAnchor constraintEqualToAnchor:self.glassDock.contentView.leadingAnchor constant:8],
        [tabs.trailingAnchor constraintEqualToAnchor:self.glassDock.contentView.trailingAnchor constant:-8],
        [tabs.topAnchor constraintEqualToAnchor:self.glassDock.contentView.topAnchor],
        [tabs.bottomAnchor constraintEqualToAnchor:self.glassDock.contentView.bottomAnchor],
        [self.miniPlayer.leadingAnchor constraintEqualToAnchor:self.glassDock.leadingAnchor],
        [self.miniPlayer.trailingAnchor constraintEqualToAnchor:self.glassDock.trailingAnchor],
        [self.miniPlayer.bottomAnchor constraintEqualToAnchor:self.glassDock.topAnchor constant:-9],
        [self.miniPlayer.heightAnchor constraintEqualToConstant:58],
        [self.miniArtwork.leadingAnchor constraintEqualToAnchor:self.miniPlayer.leadingAnchor constant:9],
        [self.miniArtwork.centerYAnchor constraintEqualToAnchor:self.miniPlayer.centerYAnchor],
        [self.miniArtwork.widthAnchor constraintEqualToConstant:42],
        [self.miniArtwork.heightAnchor constraintEqualToConstant:42],
        [self.miniPlay.trailingAnchor constraintEqualToAnchor:self.miniPlayer.trailingAnchor constant:-18],
        [self.miniPlay.centerYAnchor constraintEqualToAnchor:self.miniPlayer.centerYAnchor],
        [self.miniPlay.widthAnchor constraintEqualToConstant:38],
        [self.miniPlay.heightAnchor constraintEqualToConstant:44],
        [self.searchBar.topAnchor constraintEqualToAnchor:library.bottomAnchor constant:6],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:14],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-14],
        [self.searchBar.heightAnchor constraintEqualToConstant:48]
    ]];
    self.table.contentInset=UIEdgeInsetsMake(0,0,156,0);
    self.table.scrollIndicatorInsets=UIEdgeInsetsMake(0,0,156,0);
    self.activeMode=@"Songs";
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(libraryPreferencesChanged) name:MelodiaLibraryChanged object:nil];
    UIButton *modeButton=[UIButton buttonWithType:UIButtonTypeSystem]; modeButton.translatesAutoresizingMaskIntoConstraints=NO;
    [modeButton setTitle:@"Songs  ⌄" forState:UIControlStateNormal]; modeButton.titleLabel.font=[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    modeButton.tintColor=UIColor.whiteColor; [modeButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    modeButton.showsMenuAsPrimaryAction=YES; self.libraryMode=nil;
    [self.view addSubview:modeButton];
    [NSLayoutConstraint activateConstraints:@[[modeButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-22],[modeButton.centerYAnchor constraintEqualToAnchor:library.centerYAnchor]]];
    objc_setAssociatedObject(self,@selector(updateLibraryMenu),modeButton,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self updateLibraryMenu];
    [self reloadTracks]; [self updateNowPlayingButton]; [self updateDockAccent];
}
- (void)libraryPreferencesChanged { [self updateLibraryMenu]; [self reloadTracks]; }
- (void)updateLibraryMenu {
    UIButton *button=objc_getAssociatedObject(self,@selector(updateLibraryMenu)); if(!button)return;
    NSMutableArray *items=[NSMutableArray new];
    for(NSString *name in MelodiaSections()) {
        if(!MelodiaSectionEnabled(name))continue;
        UIAction *action=[UIAction actionWithTitle:name image:nil identifier:nil handler:^(__kindof UIAction *a) {
            self.activeMode=name; [button setTitle:[name stringByAppendingString:@"  ⌄"] forState:UIControlStateNormal]; [self filterTracks];
        }];
        if([name isEqualToString:self.activeMode])action.state=UIMenuElementStateOn;
        [items addObject:action];
    }
    button.menu=[UIMenu menuWithTitle:@"Library" children:items];
}
- (void)updateDockAccent {
    for(NSInteger j=0;j<(NSInteger)self.dockButtons.count;j++){
        UIButton *b=self.dockButtons[j];
        UIColor *color=(j==0)?ACCENT():[UIColor colorWithWhite:1 alpha:.86];
        b.tintColor=color;
        [b setTitleColor:color forState:UIControlStateNormal];
    }
}
- (void)updateNowPlayingButton { self.nowPlayingButton.hidden=YES;
    BOOL active=(self.audio.file!=nil);self.miniPlayer.hidden=!active;self.miniPlay.hidden=!active;self.miniArtwork.hidden=!active;self.miniTitleLabel.hidden=!active;self.miniArtistLabel.hidden=!active;
    if(self.audio.url){ NSString*t=self.audio.url.lastPathComponent.stringByDeletingPathExtension;
        [self.miniPlayer setTitle:@"" forState:UIControlStateNormal]; self.miniTitleLabel.text=t; self.miniArtistLabel.text=MelodiaArtist(self.audio.url); self.miniArtwork.image=MelodiaArtwork(self.audio.url)?:MelodiaPlaceholder();
        [self.miniPlay setImage:[UIImage systemImageNamed:(self.audio.playing?@"pause.fill":@"play.fill")] forState:UIControlStateNormal];
    }
}
- (void)toggleMiniPlayback { if(self.audio.file){[self.audio playPause];[self updateNowPlayingButton];} }
- (void)dockTapped:(UIButton*)b { switch(b.tag-500){case 0:self.searchBar.hidden=YES;self.searchBar.text=@"";[self filterTracks];break;
    case 1:[self importAudio];break;case 2:[self openSearch];break;
    case 3:[self openSettings];break;} }
- (void)openSearch {
    UIViewController *searchPage=[UIViewController new]; searchPage.view.backgroundColor=BG();
    searchPage.title=@"Search";
    UISearchController *controller=[[UISearchController alloc] initWithSearchResultsController:nil];
    controller.obscuresBackgroundDuringPresentation=NO;
    controller.searchBar.placeholder=@"Search songs or artists";
    searchPage.navigationItem.searchController=controller;
    searchPage.navigationItem.hidesSearchBarWhenScrolling=NO;
    UITableView *results=[[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    results.backgroundColor=UIColor.clearColor; results.separatorColor=[UIColor colorWithWhite:.18 alpha:1];
    results.rowHeight=62; results.translatesAutoresizingMaskIntoConstraints=NO;
    [searchPage.view addSubview:results];
    [NSLayoutConstraint activateConstraints:@[
        [results.topAnchor constraintEqualToAnchor:searchPage.view.safeAreaLayoutGuide.topAnchor],
        [results.leadingAnchor constraintEqualToAnchor:searchPage.view.leadingAnchor constant:18],
        [results.trailingAnchor constraintEqualToAnchor:searchPage.view.trailingAnchor constant:-18],
        [results.bottomAnchor constraintEqualToAnchor:searchPage.view.bottomAnchor]]];
    MelodiaSearchDelegate *delegate=[[MelodiaSearchDelegate alloc] initWithLibrary:self table:results];
    results.dataSource=delegate; results.delegate=delegate;
    controller.searchResultsUpdater=delegate;
    objc_setAssociatedObject(searchPage, @selector(openSearch), delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self.navigationController pushViewController:searchPage animated:YES];
}
- (void)searchBar:(UISearchBar*)searchBar textDidChange:(NSString*)searchText { [self filterTracks]; }
- (void)filterTracks {
    NSString *q=self.searchBar.text?:@"";
    NSArray *source=self.tracks;
    if([self.activeMode isEqualToString:@"Favorites"])source=[source filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSURL *u, NSDictionary *bindings){return MelodiaIsFavorite(u);}]];
    if(q.length)source=[source filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSURL *u,NSDictionary *bindings){return [u.lastPathComponent localizedCaseInsensitiveContainsString:q] || [MelodiaArtist(u) localizedCaseInsensitiveContainsString:q];}]];
    NSInteger sort=[NSUserDefaults.standardUserDefaults integerForKey:@"library.sort"];
    if([self.activeMode isEqualToString:@"Recently Added"])sort=2;
    if([self.activeMode isEqualToString:@"Artists"])sort=1;
    if([self.activeMode isEqualToString:@"Albums"])sort=1;
    self.visibleTracks=[source sortedArrayUsingComparator:^NSComparisonResult(NSURL *a,NSURL *b){
        if(sort==1){ NSComparisonResult c=[MelodiaArtist(a) localizedCaseInsensitiveCompare:MelodiaArtist(b)]; if(c!=NSOrderedSame)return c; }
        if(sort==2){ NSDate *da=nil,*db=nil;[a getResourceValue:&da forKey:NSURLCreationDateKey error:nil];[b getResourceValue:&db forKey:NSURLCreationDateKey error:nil];NSComparisonResult c=[(db?:[NSDate distantPast]) compare:(da?:[NSDate distantPast])];if(c!=NSOrderedSame)return c; }
        return [a.lastPathComponent localizedCaseInsensitiveCompare:b.lastPathComponent];
    }];
    self.table.sectionIndexColor=ACCENT();
    [self.table reloadData];
}
- (NSArray<NSString*>*)sectionIndexTitlesForTableView:(UITableView*)tableView {
    if(tableView!=self.table || ![self.activeMode isEqualToString:@"Songs"] || [NSUserDefaults.standardUserDefaults integerForKey:@"library.sort"]==2)return nil;
    return @[@"A",@"B",@"C",@"D",@"E",@"F",@"G",@"H",@"I",@"J",@"K",@"L",@"M",@"N",@"O",@"P",@"Q",@"R",@"S",@"T",@"U",@"V",@"W",@"X",@"Y",@"Z",@"#"];
}
- (NSInteger)tableView:(UITableView*)tableView sectionForSectionIndexTitle:(NSString*)title atIndex:(NSInteger)index {
    for(NSInteger i=0;i<(NSInteger)self.visibleTracks.count;i++) {
        NSURL *u=self.visibleTracks[i];NSString *value=[NSUserDefaults.standardUserDefaults integerForKey:@"library.sort"]==1?MelodiaArtist(u):u.lastPathComponent.stringByDeletingPathExtension;
        if([value.uppercaseString hasPrefix:title]){[tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0] atScrollPosition:UITableViewScrollPositionTop animated:NO];break;}
    }
    return 0;
}

- (void)audioLibraryStateChanged:(NSNotification*)n { [self updateNowPlayingButton]; }
- (NSInteger)indexForURL:(NSURL*)u { NSUInteger i=[self.tracks indexOfObject:u]; return i==NSNotFound?-1:(NSInteger)i; }
- (void)playTrackURL:(NSURL*)u { NSInteger i=[self indexForURL:u]; if(i>=0)[self playTrackAtIndex:i]; }
- (void)playTrackAtIndex:(NSInteger)i { if(self.tracks.count==0)return; NSInteger n=self.tracks.count; i=(i%n+n)%n; NSURL*u=self.tracks[i]; TrackSettings*st=[self settingsFor:u]; NSError*e=nil; if(![self.audio load:u error:&e])return; [self.audio apply:st]; [self.audio playPause]; NSMutableDictionary*info=[MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo mutableCopy]; if(info){ info[MPNowPlayingInfoPropertyPlaybackQueueIndex]=@(i); info[MPNowPlayingInfoPropertyPlaybackQueueCount]=@(n); MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo=info; [info release]; } [self updateNowPlayingButton]; [NSNotificationCenter.defaultCenter postNotificationName:SRTrackChangedNotification object:self.audio]; }
- (NSInteger)nextIndexFrom:(NSInteger)i { if(self.tracks.count==0)return -1; if(self.shuffleEnabled && self.tracks.count>1){ NSInteger next=i; while(next==i) next=arc4random_uniform((uint32_t)self.tracks.count); return next; } return (i+1)%self.tracks.count; }
- (NSInteger)previousIndexFrom:(NSInteger)i { if(self.tracks.count==0)return -1; if(self.shuffleEnabled && self.tracks.count>1){ NSInteger prev=i; while(prev==i) prev=arc4random_uniform((uint32_t)self.tracks.count); return prev; } return (i-1+(NSInteger)self.tracks.count)%self.tracks.count; }
- (void)remoteNextTrack:(NSNotification*)n { NSInteger i=[self indexForURL:self.audio.url]; [self playTrackAtIndex:[self nextIndexFrom:(i<0?0:i)]]; }
- (void)remotePreviousTrack:(NSNotification*)n { NSInteger i=[self indexForURL:self.audio.url]; [self playTrackAtIndex:[self previousIndexFrom:(i<0?0:i)]]; }
- (void)trackEnded:(NSNotification*)n { if(self.tracks.count==0 || !self.audio.url)return; NSInteger i=[self indexForURL:self.audio.url]; if(i<0)return; if(self.repeatMode==2){ [self playTrackAtIndex:i]; return; } if(self.repeatMode==1 || i<self.tracks.count-1 || self.shuffleEnabled){ [self playTrackAtIndex:[self nextIndexFrom:i]]; } }
- (void)openNowPlaying { if(!self.audio.url)return; PlayerVC*p=[PlayerVC new]; p.trackURL=self.audio.url; p.library=self; p.audio=self.audio; [self.navigationController pushViewController:p animated:YES]; }
- (void)openSettings { SettingsVC*s=[SettingsVC new]; [self.navigationController pushViewController:s animated:YES]; }
- (NSURL*)libraryDir { NSURL*d=[[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject]; d=[d URLByAppendingPathComponent:@"S&R Library" isDirectory:YES]; [[NSFileManager defaultManager] createDirectoryAtURL:d withIntermediateDirectories:YES attributes:nil error:nil]; return d; }
- (void)reloadTracks { [self.tracks removeAllObjects]; NSArray *a=[[NSFileManager defaultManager] contentsOfDirectoryAtURL:[self libraryDir] includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil]; for(NSURL*u in a){ if([@[@"mp3",@"m4a",@"wav",@"aac",@"aif",@"aiff",@"caf"] containsObject:u.pathExtension.lowercaseString]) [self.tracks addObject:u]; } [self.tracks sortUsingComparator:^NSComparisonResult(NSURL*a,NSURL*b){return [a.lastPathComponent localizedCaseInsensitiveCompare:b.lastPathComponent];}]; [self filterTracks]; }
- (void)importAudio { UIDocumentPickerViewController*p=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeAudio] asCopy:YES]; p.delegate=self; p.allowsMultipleSelection=YES; [self presentViewController:p animated:YES completion:nil]; }
- (void)documentPicker:(UIDocumentPickerViewController*)controller didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls { for(NSURL*u in urls){ BOOL scoped=[u startAccessingSecurityScopedResource]; NSString *name=u.lastPathComponent; NSURL*dst=[[self libraryDir] URLByAppendingPathComponent:name]; NSInteger n=2; while([[NSFileManager defaultManager] fileExistsAtPath:dst.path]){ NSString*base=[name stringByDeletingPathExtension];NSString*ext=name.pathExtension;dst=[[self libraryDir] URLByAppendingPathComponent:[NSString stringWithFormat:@"%@ %ld.%@",base,(long)n++,ext]];} [[NSFileManager defaultManager] copyItemAtURL:u toURL:dst error:nil]; if(scoped)[u stopAccessingSecurityScopedResource]; } [self reloadTracks]; }
- (NSInteger)tableView:(UITableView*)t numberOfRowsInSection:(NSInteger)s{return self.visibleTracks.count;}
- (UITableViewCell*)tableView:(UITableView*)t cellForRowAtIndexPath:(NSIndexPath*)i { UITableViewCell*c=[t dequeueReusableCellWithIdentifier:@"c"];if(!c)c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"]; NSURL*u=self.visibleTracks[i.row];c.backgroundColor=UIColor.clearColor;c.textLabel.text=u.lastPathComponent.stringByDeletingPathExtension;c.textLabel.textColor=UIColor.whiteColor;c.textLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightMedium];c.detailTextLabel.text=MelodiaArtist(u);c.detailTextLabel.textColor=SUBTLE();c.accessoryType=UITableViewCellAccessoryNone;
    c.imageView.image=MelodiaArtwork(u)?:MelodiaPlaceholder();
    c.imageView.layer.cornerRadius=7;c.imageView.layer.masksToBounds=YES;
    c.imageView.contentMode=UIViewContentModeScaleAspectFill;
    return c; }
- (void)tableView:(UITableView*)t didSelectRowAtIndexPath:(NSIndexPath*)i { [t deselectRowAtIndexPath:i animated:YES]; NSURL *u=self.visibleTracks[i.row]; if(![self.audio.url isEqual:u]) [self playTrackURL:u]; else if(!self.audio.playing)[self.audio playPause]; [self updateNowPlayingButton]; }
- (NSString*)keyFor:(NSURL*)u{return [@"settings." stringByAppendingString:u.lastPathComponent];}
- (TrackSettings*)settingsFor:(NSURL*)u { NSDictionary*d=[[NSUserDefaults standardUserDefaults] dictionaryForKey:[self keyFor:u]];TrackSettings*s=[TrackSettings new];s.speed=d?[d[@"speed"] floatValue]:1;s.pitch=d?[d[@"pitch"] floatValue]:0;s.reverb=d?[d[@"reverb"] floatValue]:0;s.bass=d?[d[@"bass"] floatValue]:0;s.reverbPreset=d[@"reverbPreset"]?[d[@"reverbPreset"] integerValue]:0;s.eightDEnabled=d[@"eightD"]?[d[@"eightD"] boolValue]:NO;s.eightDPeriod=d[@"eightDPeriod"]?[d[@"eightDPeriod"] floatValue]:7.0f;return s; }
- (void)saveSettings:(TrackSettings*)s forURL:(NSURL*)u { [[NSUserDefaults standardUserDefaults] setObject:@{@"speed":@(s.speed),@"pitch":@(s.pitch),@"reverb":@(s.reverb),@"bass":@(s.bass),@"reverbPreset":@(s.reverbPreset),@"eightD":@(s.eightDEnabled),@"eightDPeriod":@(s.eightDPeriod)} forKey:[self keyFor:u]]; }
- (void)deleteTrackAt:(NSIndexPath*)i { if(i.row>=self.visibleTracks.count)return; NSURL*u=self.visibleTracks[i.row]; if([self.audio.url.path isEqualToString:u.path]) [self.audio stop]; [[NSFileManager defaultManager] removeItemAtURL:u error:nil]; [[NSUserDefaults standardUserDefaults] removeObjectForKey:[self keyFor:u]]; [self.tracks removeObject:u]; [self filterTracks]; }
- (UISwipeActionsConfiguration*)tableView:(UITableView*)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath*)indexPath { __block LibraryVC *me=self; UIContextualAction*d=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete" handler:^(UIContextualAction *a,UIView *v,void(^done)(BOOL)){[me deleteTrackAt:indexPath];done(YES);}]; return [UISwipeActionsConfiguration configurationWithActions:@[d]]; }
- (UIContextMenuConfiguration*)tableView:(UITableView*)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath*)indexPath point:(CGPoint)point API_AVAILABLE(ios(13.0)) { __block LibraryVC *me=self; return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray<UIMenuElement*> *suggested){ UIAction*d=[UIAction actionWithTitle:@"Delete" image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(__kindof UIAction *action){[me deleteTrackAt:indexPath];}]; d.attributes=UIMenuElementAttributesDestructive; return [UIMenu menuWithTitle:@"" children:@[d]]; }]; }
@end

@implementation PlayerVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=BG();
    self.backgroundCover=[UIImageView new]; self.backgroundCover.image=MelodiaArtwork(self.trackURL); self.backgroundCover.contentMode=UIViewContentModeScaleAspectFill;
    self.backgroundCover.frame=self.view.bounds; self.backgroundCover.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.backgroundCover];
    UIVisualEffectView *blur=[[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    blur.frame=self.view.bounds; blur.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; [self.view addSubview:blur];
    UIView *shade=[[UIView alloc] initWithFrame:self.view.bounds]; shade.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    shade.backgroundColor=[UIColor colorWithRed:.035 green:.045 blue:.075 alpha:.55]; [self.view addSubview:shade];
    CAGradientLayer *gradient=[CAGradientLayer layer];gradient.colors=@[(id)[UIColor colorWithRed:.09 green:.13 blue:.19 alpha:1].CGColor,(id)BG().CGColor];
    gradient.startPoint=CGPointMake(0,0);gradient.endPoint=CGPointMake(.8,1);
    gradient.frame=UIScreen.mainScreen.bounds;gradient.opacity=.20;[self.view.layer insertSublayer:gradient atIndex:0];
    self.settings=[self.library settingsFor:self.trackURL];
    self.sliders=[NSMutableDictionary dictionary];
    self.steppedTags=[NSMutableSet set];
    self.navigationController.navigationBar.tintColor=UIColor.whiteColor;
    self.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(accentChanged) name:SRAccentChangedNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(audioStateChanged) name:SRAudioStateChangedNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(trackChanged:) name:SRTrackChangedNotification object:self.audio];

    UIScrollView *scroll=[UIScrollView new]; scroll.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever; scroll.translatesAutoresizingMaskIntoConstraints=NO; [self.view addSubview:scroll];
    UIView *content=[UIView new]; content.translatesAutoresizingMaskIntoConstraints=NO; [scroll addSubview:content];

    self.coverView=[UIImageView new]; self.coverView.image=MelodiaArtwork(self.trackURL)?:MelodiaPlaceholder();
    self.coverView.contentMode=UIViewContentModeScaleAspectFill; self.coverView.clipsToBounds=YES;
    self.coverView.layer.cornerRadius=16; self.coverView.translatesAutoresizingMaskIntoConstraints=NO; [content addSubview:self.coverView];
    self.titleLabel=Label(self.trackURL.lastPathComponent.stringByDeletingPathExtension,21,UIFontWeightBold);
    self.titleLabel.numberOfLines=2; self.titleLabel.lineBreakMode=NSLineBreakByTruncatingTail; [content addSubview:self.titleLabel];
    self.artistLabel=Label(MelodiaArtist(self.trackURL),16,UIFontWeightMedium); self.artistLabel.textColor=[UIColor colorWithWhite:.80 alpha:1]; [content addSubview:self.artistLabel];
    self.favoriteButton=[UIButton buttonWithType:UIButtonTypeSystem]; self.favoriteButton.translatesAutoresizingMaskIntoConstraints=NO;
    [self.favoriteButton addTarget:self action:@selector(toggleFavorite) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:self.favoriteButton]; [self refreshFavorite];

    

    UIStackView *fileActions=[UIStackView new]; fileActions.axis=UILayoutConstraintAxisHorizontal; fileActions.spacing=12; fileActions.distribution=UIStackViewDistributionFillEqually; fileActions.translatesAutoresizingMaskIntoConstraints=NO; [content addSubview:fileActions];
    self.saveButton=Button(@"Save"); self.saveButton.backgroundColor=[UIColor colorWithWhite:1 alpha:.15]; [self.saveButton addTarget:self action:@selector(save) forControlEvents:UIControlEventTouchUpInside]; [fileActions addArrangedSubview:self.saveButton];
    self.exportButton=Button(@"Export"); self.exportButton.backgroundColor=[UIColor colorWithWhite:1 alpha:.15]; [self.exportButton addTarget:self action:@selector(exportAudio) forControlEvents:UIControlEventTouchUpInside]; [fileActions addArrangedSubview:self.exportButton];

    UILabel *presetsLabel=Label(@"Presets",14,UIFontWeightSemibold); presetsLabel.textColor=SUBTLE(); presetsLabel.textAlignment=NSTextAlignmentCenter; [content addSubview:presetsLabel];
    UIStackView *presets=[UIStackView new]; presets.axis=UILayoutConstraintAxisHorizontal; presets.spacing=10; presets.distribution=UIStackViewDistributionFillEqually; presets.translatesAutoresizingMaskIntoConstraints=NO; [content addSubview:presets];
    self.slowedPresetButton=Button(@"Slowed + Reverb"); self.slowedPresetButton.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]; [self.slowedPresetButton addTarget:self action:@selector(applySlowedPreset) forControlEvents:UIControlEventTouchUpInside]; [presets addArrangedSubview:self.slowedPresetButton];
    self.nightcorePresetButton=Button(@"Nightcore"); self.nightcorePresetButton.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]; [self.nightcorePresetButton addTarget:self action:@selector(applyNightcorePreset) forControlEvents:UIControlEventTouchUpInside]; [presets addArrangedSubview:self.nightcorePresetButton];
    self.resetButton=Button(@""); [self.resetButton setImage:[UIImage systemImageNamed:@"arrow.counterclockwise"] forState:UIControlStateNormal]; self.resetButton.tintColor=UIColor.whiteColor; self.resetButton.layer.cornerRadius=13; self.resetButton.accessibilityLabel=@"Reset effects"; [self.resetButton addTarget:self action:@selector(resetEffects) forControlEvents:UIControlEventTouchUpInside]; [content addSubview:self.resetButton];
    self.eightDButton=Button(@"8D: Off"); self.eightDButton.layer.cornerRadius=13; self.eightDButton.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightSemibold]; self.eightDButton.showsMenuAsPrimaryAction=YES; [content addSubview:self.eightDButton];

    UIView *transport=[UIView new]; transport.backgroundColor=UIColor.clearColor; transport.layer.cornerRadius=22; transport.translatesAutoresizingMaskIntoConstraints=NO; [content addSubview:transport];
    self.progressSlider=[UISlider new]; self.progressSlider.minimumValue=0; self.progressSlider.maximumValue=1; self.progressSlider.minimumTrackTintColor=ACCENT(); self.progressSlider.translatesAutoresizingMaskIntoConstraints=NO; [self.progressSlider setThumbImage:[self subtleThumb] forState:UIControlStateNormal]; [self.progressSlider addTarget:self action:@selector(scrubBegan:) forControlEvents:UIControlEventTouchDown]; [self.progressSlider addTarget:self action:@selector(scrubChanged:) forControlEvents:UIControlEventValueChanged]; [self.progressSlider addTarget:self action:@selector(scrubEnded:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel]; [transport addSubview:self.progressSlider];
    self.elapsedLabel=Label(@"0:00",12.5,UIFontWeightMedium); self.elapsedLabel.textColor=SUBTLE(); [transport addSubview:self.elapsedLabel];
    self.remainingLabel=Label(@"−0:00",12.5,UIFontWeightMedium); self.remainingLabel.textColor=SUBTLE(); self.remainingLabel.textAlignment=NSTextAlignmentRight; [transport addSubview:self.remainingLabel];
    self.previousButton=Button(@"◀︎|"); self.previousButton.titleLabel.font=[UIFont systemFontOfSize:19 weight:UIFontWeightSemibold]; [self.previousButton addTarget:self action:@selector(previousTrack) forControlEvents:UIControlEventTouchUpInside]; [transport addSubview:self.previousButton];
    self.playButton=Button(@"▶︎"); self.playButton.titleLabel.font=[UIFont systemFontOfSize:23 weight:UIFontWeightBold]; [self.playButton addTarget:self action:@selector(playPause) forControlEvents:UIControlEventTouchUpInside]; [transport addSubview:self.playButton];
    self.nextButton=Button(@"|▶︎"); self.nextButton.titleLabel.font=[UIFont systemFontOfSize:19 weight:UIFontWeightSemibold]; [self.nextButton addTarget:self action:@selector(nextTrack) forControlEvents:UIControlEventTouchUpInside]; [transport addSubview:self.nextButton];
    self.shuffleButton=Button(@""); [self.shuffleButton setImage:[UIImage systemImageNamed:@"shuffle"] forState:UIControlStateNormal]; self.shuffleButton.tintColor=UIColor.whiteColor; [self.shuffleButton addTarget:self action:@selector(toggleShuffle) forControlEvents:UIControlEventTouchUpInside]; [transport addSubview:self.shuffleButton];
    self.repeatButton=Button(@""); [self.repeatButton setImage:[UIImage systemImageNamed:(self.library.repeatMode==2?@"repeat.1":@"repeat")] forState:UIControlStateNormal]; self.repeatButton.tintColor=UIColor.whiteColor; [self.repeatButton addTarget:self action:@selector(toggleRepeat) forControlEvents:UIControlEventTouchUpInside]; [transport addSubview:self.repeatButton];
    for(UIButton *b in @[self.previousButton,self.playButton,self.nextButton,self.shuffleButton,self.repeatButton]) {
        b.backgroundColor=UIColor.clearColor;
    }
    MPVolumeView *systemVolume=[[MPVolumeView alloc] initWithFrame:CGRectZero]; systemVolume.translatesAutoresizingMaskIntoConstraints=NO;
    systemVolume.showsRouteButton=NO; systemVolume.showsVolumeSlider=YES; [transport addSubview:systemVolume];
    self.volumeSlider=nil;
    [NSLayoutConstraint activateConstraints:@[[systemVolume.leadingAnchor constraintEqualToAnchor:transport.leadingAnchor constant:22],
        [systemVolume.trailingAnchor constraintEqualToAnchor:transport.trailingAnchor constant:-22],
        [systemVolume.topAnchor constraintEqualToAnchor:self.playButton.bottomAnchor constant:10],
        [systemVolume.heightAnchor constraintEqualToConstant:35]]];

    UIStackView *stack=[UIStackView new]; stack.axis=UILayoutConstraintAxisVertical; stack.spacing=25; stack.translatesAutoresizingMaskIntoConstraints=NO; [content addSubview:stack];
    [self addSliderTo:stack name:@"Speed" min:.5 max:1.5 value:self.settings.speed tag:1];
    float pitchFactor=powf(2.0f,self.settings.pitch/1200.0f); [self addSliderTo:stack name:@"Pitch" min:.5 max:1.5 value:pitchFactor tag:2];
    [self addSliderTo:stack name:@"Reverb" min:0 max:100 value:self.settings.reverb tag:3];
    [self addSliderTo:stack name:@"Bass" min:-12 max:18 value:self.settings.bass tag:4];

    UILabel *hint=Label(@"Changes are previewed live. Save keeps your effects in Melodia. Export creates a new audio file without changing the original.",12.5,UIFontWeightRegular); hint.textColor=SUBTLE(); hint.numberOfLines=0; [content addSubview:hint];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor], [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor], [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [content.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor], [content.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor], [content.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor], [content.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor], [content.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
        [self.coverView.topAnchor constraintEqualToAnchor:content.topAnchor constant:16],
        [self.coverView.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
        [self.coverView.widthAnchor constraintEqualToAnchor:content.widthAnchor multiplier:.82],
        [self.coverView.heightAnchor constraintEqualToAnchor:self.coverView.widthAnchor],
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.coverView.bottomAnchor constant:22], [self.titleLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:26], [self.titleLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-70],
        [self.artistLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:5],
        [self.artistLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.artistLabel.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
        [self.favoriteButton.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],[self.favoriteButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-22],[self.favoriteButton.widthAnchor constraintEqualToConstant:42],[self.favoriteButton.heightAnchor constraintEqualToConstant:42],
        [fileActions.topAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.bottomAnchor constant:34],
        [fileActions.topAnchor constraintGreaterThanOrEqualToAnchor:transport.bottomAnchor constant:85], [fileActions.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:26], [fileActions.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-26], [fileActions.heightAnchor constraintEqualToConstant:44],
        [presetsLabel.topAnchor constraintEqualToAnchor:fileActions.bottomAnchor constant:12], [presetsLabel.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
        [presets.topAnchor constraintEqualToAnchor:presetsLabel.bottomAnchor constant:7], [presets.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:52], [presets.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-52], [presets.heightAnchor constraintEqualToConstant:34],
        [self.resetButton.centerYAnchor constraintEqualToAnchor:presets.centerYAnchor], [self.resetButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-12], [self.resetButton.widthAnchor constraintEqualToConstant:26], [self.resetButton.heightAnchor constraintEqualToConstant:26],
        [self.eightDButton.topAnchor constraintEqualToAnchor:presets.bottomAnchor constant:9], [self.eightDButton.centerXAnchor constraintEqualToAnchor:content.centerXAnchor], [self.eightDButton.widthAnchor constraintEqualToConstant:126], [self.eightDButton.heightAnchor constraintEqualToConstant:30],
        [stack.topAnchor constraintEqualToAnchor:self.eightDButton.bottomAnchor constant:18], [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:26], [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-26],
        [transport.topAnchor constraintEqualToAnchor:self.artistLabel.bottomAnchor constant:24], [transport.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:26], [transport.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-26], [transport.heightAnchor constraintEqualToConstant:184],
        [self.progressSlider.topAnchor constraintEqualToAnchor:transport.topAnchor constant:16], [self.progressSlider.leadingAnchor constraintEqualToAnchor:transport.leadingAnchor constant:18], [self.progressSlider.trailingAnchor constraintEqualToAnchor:transport.trailingAnchor constant:-18],
        [self.elapsedLabel.topAnchor constraintEqualToAnchor:self.progressSlider.bottomAnchor constant:2], [self.elapsedLabel.leadingAnchor constraintEqualToAnchor:self.progressSlider.leadingAnchor],
        [self.remainingLabel.topAnchor constraintEqualToAnchor:self.progressSlider.bottomAnchor constant:2], [self.remainingLabel.trailingAnchor constraintEqualToAnchor:self.progressSlider.trailingAnchor],
        [self.playButton.centerXAnchor constraintEqualToAnchor:transport.centerXAnchor], [self.playButton.topAnchor constraintEqualToAnchor:self.elapsedLabel.bottomAnchor constant:12], [self.playButton.widthAnchor constraintEqualToConstant:50], [self.playButton.heightAnchor constraintEqualToConstant:42],
        [self.previousButton.centerYAnchor constraintEqualToAnchor:self.playButton.centerYAnchor], [self.previousButton.trailingAnchor constraintEqualToAnchor:self.playButton.leadingAnchor constant:-14], [self.previousButton.widthAnchor constraintEqualToConstant:46], [self.previousButton.heightAnchor constraintEqualToConstant:40],
        [self.nextButton.centerYAnchor constraintEqualToAnchor:self.playButton.centerYAnchor], [self.nextButton.leadingAnchor constraintEqualToAnchor:self.playButton.trailingAnchor constant:14], [self.nextButton.widthAnchor constraintEqualToConstant:46], [self.nextButton.heightAnchor constraintEqualToConstant:40],
        [self.shuffleButton.centerYAnchor constraintEqualToAnchor:self.playButton.centerYAnchor], [self.shuffleButton.trailingAnchor constraintEqualToAnchor:self.previousButton.leadingAnchor constant:-8], [self.shuffleButton.widthAnchor constraintEqualToConstant:42], [self.shuffleButton.heightAnchor constraintEqualToConstant:40],
        [self.repeatButton.centerYAnchor constraintEqualToAnchor:self.playButton.centerYAnchor], [self.repeatButton.leadingAnchor constraintEqualToAnchor:self.nextButton.trailingAnchor constant:8], [self.repeatButton.widthAnchor constraintEqualToConstant:42], [self.repeatButton.heightAnchor constraintEqualToConstant:40],
        
        [hint.topAnchor constraintEqualToAnchor:stack.bottomAnchor constant:16], [hint.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:26], [hint.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-26], [hint.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-24],
        [content.heightAnchor constraintGreaterThanOrEqualToAnchor:scroll.frameLayoutGuide.heightAnchor]
    ]];

    [self refreshPlaybackModeButtons];
    BOOL alreadyCurrent=(self.audio.file && [self.audio.url.path isEqualToString:self.trackURL.path]);
    if(alreadyCurrent){ self.settings.speed=self.audio.currentSpeed; self.settings.pitch=self.audio.timePitch.pitch; self.settings.reverb=self.audio.reverb.wetDryMix; self.settings.bass=self.audio.eq.bands[0].gain; self.settings.reverbPreset=self.audio.currentReverbPreset; self.settings.eightDEnabled=self.audio.eightDEnabled; self.settings.eightDPeriod=self.audio.eightDPeriod; UISlider*s1=self.sliders[@1],*s2=self.sliders[@2],*s3=self.sliders[@3],*s4=self.sliders[@4]; s1.value=self.settings.speed; s2.value=powf(2.0f,self.settings.pitch/1200.0f); s3.value=self.settings.reverb; s4.value=self.settings.bass; [self updateLabel:(UILabel*)[s1.superview viewWithTag:101] tag:1 value:s1.value]; [self updateLabel:(UILabel*)[s2.superview viewWithTag:102] tag:2 value:s2.value]; [self updateLabel:(UILabel*)[s3.superview viewWithTag:103] tag:3 value:s3.value]; [self updateLabel:(UILabel*)[s4.superview viewWithTag:104] tag:4 value:s4.value]; [self refreshEffectMenus]; [self startProgressTimer]; [self audioStateChanged]; [self updateProgress]; }
    else { NSError *e=nil; if([self.audio load:self.trackURL error:&e]){ [self.audio apply:self.settings]; [self startProgressTimer]; [self updateProgress]; } else [self show:[NSString stringWithFormat:@"Could not open audio: %@",e.localizedDescription]]; }
}
- (NSString*)clock:(NSTimeInterval)t { NSInteger total=(NSInteger)MAX(0,round(t)); return [NSString stringWithFormat:@"%ld:%02ld",(long)(total/60),(long)(total%60)]; }
- (void)startProgressTimer { [self.progressTimer invalidate]; self.progressTimer=[NSTimer scheduledTimerWithTimeInterval:.25 target:self selector:@selector(updateProgress) userInfo:nil repeats:YES]; }
- (void)updateProgress { if(!self.audio.file)return; NSTimeInterval now=[self.audio currentTime],dur=self.audio.duration; if(!self.scrubbing){self.progressSlider.maximumValue=MAX(.01,dur);self.progressSlider.value=MIN(dur,now);} self.elapsedLabel.text=[self clock:(self.scrubbing?self.progressSlider.value:now)]; self.remainingLabel.text=[@"−" stringByAppendingString:[self clock:MAX(0,dur-(self.scrubbing?self.progressSlider.value:now))]]; }
- (void)scrubBegan:(UISlider*)s { self.scrubbing=YES; }
- (void)scrubChanged:(UISlider*)s { self.elapsedLabel.text=[self clock:s.value]; self.remainingLabel.text=[@"−" stringByAppendingString:[self clock:MAX(0,self.audio.duration-s.value)]]; }
- (void)scrubEnded:(UISlider*)s { self.scrubbing=NO; [self.audio seekTo:s.value]; [self updateProgress]; }
- (void)refreshFavorite { [self.favoriteButton setImage:[UIImage systemImageNamed:(MelodiaIsFavorite(self.trackURL)?@"heart.fill":@"heart")] forState:UIControlStateNormal]; self.favoriteButton.tintColor=MelodiaIsFavorite(self.trackURL)?ACCENT():UIColor.whiteColor; }
- (void)toggleFavorite { MelodiaSetFavorite(self.trackURL,!MelodiaIsFavorite(self.trackURL)); [self refreshFavorite]; }
- (void)accentChanged { self.saveButton.backgroundColor=[UIColor colorWithWhite:1 alpha:.15]; self.exportButton.backgroundColor=[UIColor colorWithWhite:1 alpha:.15]; self.progressSlider.minimumTrackTintColor=ACCENT(); for(UISlider*s in self.sliders.allValues)s.minimumTrackTintColor=ACCENT(); [self refreshPlaybackModeButtons]; [self refreshEffectMenus]; }
- (void)audioStateChanged { [self.playButton setTitle:(self.audio.playing?@"❚❚":@"▶︎") forState:UIControlStateNormal]; [self updateProgress]; }
- (void)trackChanged:(NSNotification*)n { if(!self.audio.url)return; self.trackURL=self.audio.url; self.titleLabel.text=self.trackURL.lastPathComponent.stringByDeletingPathExtension;
    self.artistLabel.text=MelodiaArtist(self.trackURL); self.coverView.image=MelodiaArtwork(self.trackURL)?:MelodiaPlaceholder(); self.backgroundCover.image=MelodiaArtwork(self.trackURL); [self refreshFavorite];
    self.settings=[self.library settingsFor:self.trackURL]; UISlider*s1=self.sliders[@1],*s2=self.sliders[@2],*s3=self.sliders[@3],*s4=self.sliders[@4]; s1.value=self.settings.speed; s2.value=powf(2.0f,self.settings.pitch/1200.0f); s3.value=self.settings.reverb; s4.value=self.settings.bass; [self updateLabel:(UILabel*)[s1.superview viewWithTag:101] tag:1 value:s1.value]; [self updateLabel:(UILabel*)[s2.superview viewWithTag:102] tag:2 value:s2.value]; [self updateLabel:(UILabel*)[s3.superview viewWithTag:103] tag:3 value:s3.value]; [self updateLabel:(UILabel*)[s4.superview viewWithTag:104] tag:4 value:s4.value]; [self refreshEffectMenus]; [self.audio apply:self.settings]; [self audioStateChanged]; }
- (float)stepForTag:(NSInteger)tag { if(tag==1)return .05f; if(tag==2)return .05f; if(tag==3)return 5.0f; return 1.0f; }
- (float)snap:(float)v tag:(NSInteger)tag { float st=[self stepForTag:tag]; return roundf(v/st)*st; }
- (UIImage*)subtleThumb {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(12,12),NO,0);
    [[UIColor colorWithWhite:1 alpha:.70] setFill]; [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(2,2,8,8)] fill];
    UIImage *image=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return image;
}
- (void)addSliderTo:(UIStackView*)stack name:(NSString*)name min:(float)min max:(float)max value:(float)value tag:(NSInteger)tag {
    UIView*v=[UIView new]; v.translatesAutoresizingMaskIntoConstraints=NO;
    UILabel*l=Label(@"",16,UIFontWeightSemibold); l.tag=100+tag; [v addSubview:l];
    UIButton*mode=Button(@"Smooth"); mode.tag=200+tag; mode.layer.cornerRadius=12; mode.titleLabel.font=[UIFont systemFontOfSize:11 weight:UIFontWeightMedium]; [mode addTarget:self action:@selector(toggleMode:) forControlEvents:UIControlEventTouchUpInside]; [v addSubview:mode];
    UIButton *reverbType=nil; if(tag==3){ reverbType=Button(SRReverbName(self.settings.reverbPreset)); reverbType.layer.cornerRadius=12; reverbType.titleLabel.font=[UIFont systemFontOfSize:9.5 weight:UIFontWeightMedium]; reverbType.showsMenuAsPrimaryAction=YES; self.reverbTypeButton=reverbType; [v addSubview:reverbType]; }
    UISlider*s=[UISlider new]; s.minimumValue=min;s.maximumValue=max;s.value=value;s.tag=tag;s.minimumTrackTintColor=ACCENT();s.translatesAutoresizingMaskIntoConstraints=NO;[s setThumbImage:[self subtleThumb] forState:UIControlStateNormal];[s addTarget:self action:@selector(slider:) forControlEvents:UIControlEventValueChanged];[v addSubview:s]; self.sliders[@(tag)]=s;
    NSMutableArray *constraints=[NSMutableArray arrayWithArray:@[[v.heightAnchor constraintEqualToConstant:62],[l.topAnchor constraintEqualToAnchor:v.topAnchor],[l.leadingAnchor constraintEqualToAnchor:v.leadingAnchor],[mode.centerYAnchor constraintEqualToAnchor:l.centerYAnchor],[mode.trailingAnchor constraintEqualToAnchor:v.trailingAnchor],[mode.widthAnchor constraintEqualToConstant:66],[mode.heightAnchor constraintEqualToConstant:26],[s.topAnchor constraintEqualToAnchor:l.bottomAnchor constant:7],[s.leadingAnchor constraintEqualToAnchor:v.leadingAnchor],[s.trailingAnchor constraintEqualToAnchor:v.trailingAnchor]]];
    if(reverbType){ [constraints addObject:[reverbType.centerYAnchor constraintEqualToAnchor:l.centerYAnchor]]; [constraints addObject:[reverbType.trailingAnchor constraintEqualToAnchor:mode.leadingAnchor constant:-7]]; [constraints addObject:[reverbType.widthAnchor constraintEqualToConstant:102]]; [constraints addObject:[reverbType.heightAnchor constraintEqualToConstant:26]]; }
    [NSLayoutConstraint activateConstraints:constraints];
    [stack addArrangedSubview:v]; [self updateLabel:l tag:tag value:value]; if(tag==3)[self refreshEffectMenus];
}
- (void)refreshEffectMenus {
    if(self.reverbTypeButton){
        [self.reverbTypeButton setTitle:SRReverbName(self.settings.reverbPreset) forState:UIControlStateNormal];
        NSMutableArray *items=[NSMutableArray array];
        __block PlayerVC *me=self;
        for(NSInteger i=0;i<=12;i++){ NSInteger idx=i; UIAction *a=[UIAction actionWithTitle:SRReverbName(i) image:nil identifier:nil handler:^(__kindof UIAction *action){ me.settings.reverbPreset=idx; [me.reverbTypeButton setTitle:SRReverbName(idx) forState:UIControlStateNormal]; [me.audio apply:me.settings]; }]; if(i==self.settings.reverbPreset)a.state=UIMenuElementStateOn; [items addObject:a]; }
        self.reverbTypeButton.menu=[UIMenu menuWithTitle:@"Reverb type" children:items];
    }
    if(self.eightDButton){
        NSString *title=@"8D: Off"; if(self.settings.eightDEnabled){ if(self.settings.eightDPeriod>=10)title=@"8D: Slow"; else if(self.settings.eightDPeriod<=5)title=@"8D: Fast"; else title=@"8D: Medium"; }
        [self.eightDButton setTitle:title forState:UIControlStateNormal];
        __block PlayerVC *me=self;
        UIAction *off=[UIAction actionWithTitle:@"Off" image:nil identifier:nil handler:^(__kindof UIAction *a){me.settings.eightDEnabled=NO;[me.audio apply:me.settings];[me refreshEffectMenus];}];
        UIAction *slow=[UIAction actionWithTitle:@"Slow orbit · 12s" image:nil identifier:nil handler:^(__kindof UIAction *a){me.settings.eightDEnabled=YES;me.settings.eightDPeriod=12;[me.audio apply:me.settings];[me refreshEffectMenus];}];
        UIAction *medium=[UIAction actionWithTitle:@"Medium orbit · 7s" image:nil identifier:nil handler:^(__kindof UIAction *a){me.settings.eightDEnabled=YES;me.settings.eightDPeriod=7;[me.audio apply:me.settings];[me refreshEffectMenus];}];
        UIAction *fast=[UIAction actionWithTitle:@"Fast orbit · 4s" image:nil identifier:nil handler:^(__kindof UIAction *a){me.settings.eightDEnabled=YES;me.settings.eightDPeriod=4;[me.audio apply:me.settings];[me refreshEffectMenus];}];
        if(!self.settings.eightDEnabled)off.state=UIMenuElementStateOn; else if(self.settings.eightDPeriod>=10)slow.state=UIMenuElementStateOn; else if(self.settings.eightDPeriod<=5)fast.state=UIMenuElementStateOn; else medium.state=UIMenuElementStateOn;
        self.eightDButton.menu=[UIMenu menuWithTitle:@"8D motion" children:@[off,slow,medium,fast]];
        [self.eightDButton setTitleColor:(self.settings.eightDEnabled?ACCENT():UIColor.whiteColor) forState:UIControlStateNormal];
    }
}
- (void)applyPresetSpeed:(float)speed pitch:(float)pitchFactor reverb:(float)reverb bass:(float)bass {
    UISlider *s1=self.sliders[@1],*s2=self.sliders[@2],*s3=self.sliders[@3],*s4=self.sliders[@4];
    s1.value=speed; s2.value=pitchFactor; s3.value=reverb; s4.value=bass;
    [self slider:s1]; [self slider:s2]; [self slider:s3]; [self slider:s4];
}
- (void)applySlowedPreset { [self applyPresetSpeed:.80f pitch:.80f reverb:40.0f bass:0.0f]; }
- (void)applyNightcorePreset { [self applyPresetSpeed:1.20f pitch:1.20f reverb:0.0f bass:0.0f]; }
- (void)resetEffects {
    self.settings.reverbPreset=0; self.settings.eightDEnabled=NO; self.settings.eightDPeriod=7.0f;
    self.library.shuffleEnabled=NO; self.library.repeatMode=0;
    [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"playback.shuffle"];
    [NSUserDefaults.standardUserDefaults setInteger:0 forKey:@"playback.repeatMode"];
    [self applyPresetSpeed:1.0f pitch:1.0f reverb:0.0f bass:0.0f];
    [self.audio apply:self.settings]; [self refreshEffectMenus]; [self refreshPlaybackModeButtons];
}
- (void)toggleMode:(UIButton*)b { NSInteger tag=b.tag-200; NSNumber*n=@(tag); if([self.steppedTags containsObject:n]){[self.steppedTags removeObject:n];[b setTitle:@"Smooth" forState:UIControlStateNormal];} else {[self.steppedTags addObject:n];[b setTitle:@"Step" forState:UIControlStateNormal]; UISlider*s=self.sliders[n];s.value=[self snap:s.value tag:tag];[self slider:s];} }
- (void)updateLabel:(UILabel*)l tag:(NSInteger)tag value:(float)v { if(tag==1)l.text=[NSString stringWithFormat:@"Speed  %.2fx",v]; if(tag==2)l.text=[NSString stringWithFormat:@"Pitch  %.2fx",v]; if(tag==3)l.text=[NSString stringWithFormat:@"Reverb  %.0f%%",v]; if(tag==4)l.text=[NSString stringWithFormat:@"Bass  %+.1f dB",v]; }
- (void)slider:(UISlider*)x { if([self.steppedTags containsObject:@(x.tag)]) x.value=[self snap:x.value tag:x.tag]; if(x.tag==1)self.settings.speed=x.value; if(x.tag==2)self.settings.pitch=1200.0f*log2f(MAX(.01f,x.value)); if(x.tag==3)self.settings.reverb=x.value; if(x.tag==4)self.settings.bass=x.value; [self updateLabel:(UILabel*)[x.superview viewWithTag:100+x.tag] tag:x.tag value:x.value]; [self.audio apply:self.settings]; }
- (void)volumeChanged:(UISlider*)s { self.audio.outputVolume=s.value; self.audio.engine.mainMixerNode.outputVolume=s.value; }
- (void)refreshPlaybackModeButtons { self.shuffleButton.tintColor=self.library.shuffleEnabled?ACCENT():UIColor.whiteColor; [self.repeatButton setImage:[UIImage systemImageNamed:(self.library.repeatMode==2?@"repeat.1":@"repeat")] forState:UIControlStateNormal]; self.repeatButton.tintColor=(self.library.repeatMode==0?UIColor.whiteColor:ACCENT()); }
- (void)toggleShuffle { self.library.shuffleEnabled=!self.library.shuffleEnabled; [NSUserDefaults.standardUserDefaults setBool:self.library.shuffleEnabled forKey:@"playback.shuffle"]; [self refreshPlaybackModeButtons]; }
- (void)toggleRepeat { self.library.repeatMode=(self.library.repeatMode+1)%3; [NSUserDefaults.standardUserDefaults setInteger:self.library.repeatMode forKey:@"playback.repeatMode"]; [self refreshPlaybackModeButtons]; }
- (void)playPause { [self.audio playPause]; [self audioStateChanged]; }
- (void)save { [self.library saveSettings:self.settings forURL:self.trackURL]; [self show:@"Saved. These settings will be restored next time you open this track."]; }
- (void)loadTrackAtIndex:(NSInteger)i autoPlay:(BOOL)autoPlay { if(self.library.tracks.count==0)return; NSInteger n=self.library.tracks.count; i=(i%n+n)%n; BOOL wasPlaying=autoPlay||self.audio.playing; self.trackURL=self.library.tracks[i]; self.settings=[self.library settingsFor:self.trackURL]; self.titleLabel.text=self.trackURL.lastPathComponent.stringByDeletingPathExtension; UISlider*s1=self.sliders[@1],*s2=self.sliders[@2],*s3=self.sliders[@3],*s4=self.sliders[@4]; s1.value=self.settings.speed; s2.value=powf(2.0f,self.settings.pitch/1200.0f); s3.value=self.settings.reverb; s4.value=self.settings.bass; [self slider:s1];[self slider:s2];[self slider:s3];[self slider:s4]; NSError*e=nil; if(![self.audio load:self.trackURL error:&e]){[self show:[NSString stringWithFormat:@"Could not open audio: %@",e.localizedDescription]];return;} [self.audio apply:self.settings]; if(wasPlaying)[self.audio playPause]; [self updateProgress]; }
- (NSInteger)currentTrackIndex { NSUInteger i=[self.library.tracks indexOfObject:self.trackURL]; return i==NSNotFound?0:(NSInteger)i; }
- (void)previousTrack { [self.library playTrackAtIndex:[self.library previousIndexFrom:[self currentTrackIndex]]]; }
- (void)nextTrack { [self.library playTrackAtIndex:[self.library nextIndexFrom:[self currentTrackIndex]]]; }
- (NSURL*)renderExport:(NSError**)outError {
    AVAudioFile *input=[[AVAudioFile alloc] initForReading:self.trackURL error:outError]; if(!input)return nil;
    AVAudioEngine *engine=[AVAudioEngine new]; AVAudioPlayerNode *player=[AVAudioPlayerNode new]; AVAudioUnitTimePitch *tp=[AVAudioUnitTimePitch new]; AVAudioUnitEQ *eq=[[AVAudioUnitEQ alloc] initWithNumberOfBands:1]; AVAudioUnitReverb *rev=[AVAudioUnitReverb new];
    AVAudioUnitEQFilterParameters *band=eq.bands[0]; band.filterType=AVAudioUnitEQFilterTypeLowShelf; band.frequency=180; band.bandwidth=1; band.bypass=NO; band.gain=self.settings.bass; tp.rate=self.settings.speed; tp.pitch=self.settings.pitch; [rev loadFactoryPreset:SRReverbPreset(self.settings.reverbPreset)]; rev.wetDryMix=self.settings.reverb;
    [engine attachNode:player]; [engine attachNode:tp]; [engine attachNode:eq]; [engine attachNode:rev];
    AVAudioFormat *sourceFormat=input.processingFormat;
    AVAudioFormat *renderFormat=[[AVAudioFormat alloc] initStandardFormatWithSampleRate:sourceFormat.sampleRate channels:sourceFormat.channelCount];
    [engine connect:player to:tp format:sourceFormat]; [engine connect:tp to:eq format:nil]; [engine connect:eq to:rev format:nil]; [engine connect:rev to:engine.mainMixerNode format:renderFormat];
    NSError *err=nil; if(![engine enableManualRenderingMode:AVAudioEngineManualRenderingModeOffline format:renderFormat maximumFrameCount:4096 error:&err]){if(outError)*outError=err;return nil;}
    NSString *base=self.trackURL.lastPathComponent.stringByDeletingPathExtension; NSString *name=[NSString stringWithFormat:@"%@ S&R.wav",base]; NSURL *out=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]]; [[NSFileManager defaultManager] removeItemAtURL:out error:nil];
    NSDictionary *wavSettings=@{AVFormatIDKey:@(kAudioFormatLinearPCM), AVSampleRateKey:@(renderFormat.sampleRate), AVNumberOfChannelsKey:@(renderFormat.channelCount), AVLinearPCMBitDepthKey:@16, AVLinearPCMIsFloatKey:@NO, AVLinearPCMIsBigEndianKey:@NO, AVLinearPCMIsNonInterleaved:@NO};
    AVAudioFile *output=[[AVAudioFile alloc] initForWriting:out settings:wavSettings error:&err]; if(!output){if(outError)*outError=err;return nil;}
    [player scheduleFile:input atTime:nil completionHandler:nil]; if(![engine startAndReturnError:&err]){if(outError)*outError=err;return nil;} [player play];
    AVAudioPCMBuffer *buffer=[[AVAudioPCMBuffer alloc] initWithPCMFormat:engine.manualRenderingFormat frameCapacity:engine.manualRenderingMaximumFrameCount];
    NSTimeInterval sourceSeconds=(double)input.length/sourceFormat.sampleRate; NSTimeInterval renderedSeconds=sourceSeconds/MAX(.1f,self.settings.speed)+2.0; AVAudioFramePosition target=(AVAudioFramePosition)ceil(renderedSeconds*renderFormat.sampleRate);
    AVAudioFramePosition written=0; NSInteger noProgress=0;
    while(engine.manualRenderingSampleTime<target){
        AVAudioFrameCount frames=(AVAudioFrameCount)MIN((AVAudioFramePosition)buffer.frameCapacity,target-engine.manualRenderingSampleTime);
        AVAudioEngineManualRenderingStatus st=[engine renderOffline:frames toBuffer:buffer error:&err];
        if(st==AVAudioEngineManualRenderingStatusSuccess){ if(buffer.frameLength>0){
            if(self.settings.eightDEnabled && buffer.format.channelCount>=2 && buffer.floatChannelData){ float * const *ch=buffer.floatChannelData; double sr=buffer.format.sampleRate; for(AVAudioFrameCount f=0;f<buffer.frameLength;f++){ double t=(double)(written+f)/sr; float pan=sinf((float)(t/MAX(2.0f,self.settings.eightDPeriod)*2.0*M_PI))*.92f; float lg=pan>0?(1.0f-pan*.86f):1.0f; float rg=pan<0?(1.0f+pan*.86f):1.0f; ch[0][f]*=lg; ch[1][f]*=rg; } }
            if(![output writeFromBuffer:buffer error:&err])break; written+=buffer.frameLength; noProgress=0; } else if(++noProgress>256) break; }
        else if(st==AVAudioEngineManualRenderingStatusCannotDoInCurrentContext || st==AVAudioEngineManualRenderingStatusInsufficientDataFromInputNode){ if(++noProgress>256) break; continue; }
        else { if(!err)err=[NSError errorWithDomain:@"SRAudioExport" code:1 userInfo:@{NSLocalizedDescriptionKey:@"The audio engine could not render the export."}]; break; }
    }
    [player stop]; [engine stop];
    [output release]; output=nil;
    if(err){ [[NSFileManager defaultManager] removeItemAtURL:out error:nil]; if(outError)*outError=err; return nil; }
    if(written<renderFormat.sampleRate*.25){ [[NSFileManager defaultManager] removeItemAtURL:out error:nil]; if(outError)*outError=[NSError errorWithDomain:@"SRAudioExport" code:2 userInfo:@{NSLocalizedDescriptionKey:@"The rendered file contained no usable audio."}]; return nil; }
    AVAudioFile *check=[[AVAudioFile alloc] initForReading:out error:&err]; if(!check || check.length<=0){ [[NSFileManager defaultManager] removeItemAtURL:out error:nil]; if(outError)*outError=err?:[NSError errorWithDomain:@"SRAudioExport" code:3 userInfo:@{NSLocalizedDescriptionKey:@"The exported WAV could not be reopened."}]; return nil; }
    return out;
}
- (void)exportAudio {
    self.exportButton.enabled=NO; [self.exportButton setTitle:@"Rendering…" forState:UIControlStateNormal]; __block PlayerVC *me=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{ NSError*e=nil; NSURL*out=[me renderExport:&e]; dispatch_async(dispatch_get_main_queue(), ^{ me.exportButton.enabled=YES; [me.exportButton setTitle:@"Export" forState:UIControlStateNormal]; if(!out){[me show:[NSString stringWithFormat:@"Export failed: %@",e.localizedDescription?:@"Unknown error"]];return;} UIActivityViewController*a=[[UIActivityViewController alloc] initWithActivityItems:@[out] applicationActivities:nil]; if(a.popoverPresentationController)a.popoverPresentationController.sourceView=me.exportButton; [me presentViewController:a animated:YES completion:nil]; }); });
}
- (void)show:(NSString*)m { UIAlertController*a=[UIAlertController alertControllerWithTitle:@"Melodia" message:m preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil]; }
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; if(self.isMovingFromParentViewController){[self.progressTimer invalidate];self.progressTimer=nil;} }
- (void)dealloc { [self.progressTimer invalidate]; [NSNotificationCenter.defaultCenter removeObserver:self]; }
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate> @property (nonatomic, strong) UIWindow *window; @end
@implementation AppDelegate
- (BOOL)application:(UIApplication*)app didFinishLaunchingWithOptions:(NSDictionary*)opts { self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];LibraryVC*l=[LibraryVC new];UINavigationController*n=[[UINavigationController alloc] initWithRootViewController:l];n.navigationBar.barStyle=UIBarStyleBlack;n.navigationBar.translucent=YES;self.window.rootViewController=n;[self.window makeKeyAndVisible];return YES; }
- (void)applicationDidBecomeActive:(UIApplication*)application { [AVAudioSession.sharedInstance setActive:YES error:nil]; }
@end
int main(int argc,char*argv[]){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(AppDelegate.class));}}
