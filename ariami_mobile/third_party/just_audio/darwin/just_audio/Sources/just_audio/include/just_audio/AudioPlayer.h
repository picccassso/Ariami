#import <AVFoundation/AVFoundation.h>
#if TARGET_OS_OSX
#import <FlutterMacOS/FlutterMacOS.h>
#else
#import <Flutter/Flutter.h>
#endif

@interface AudioPlayer : NSObject<AVPlayerItemMetadataOutputPushDelegate>

@property (readonly, nonatomic) AVQueuePlayer *player;
@property (readonly, nonatomic) float speed;

- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar playerId:(NSString*)idParam loadConfiguration:(NSDictionary *)loadConfiguration darwinAudioEffects:(NSArray *)darwinAudioEffects useLazyPreparation:(BOOL)useLazyPreparation;
- (void)dispose:(BOOL)calledFromDealloc;
// (Ariami fork) Attaches the audio tap (EQ / level meter) to the playing item.
- (void)attachTapToCurrentItem;

@end

enum ProcessingState {
    psIdle,
    psLoading,
    psBuffering,
    psReady,
    psCompleted
};

enum LoopMode {
    lmLoopOff,
    lmLoopOne,
    lmLoopAll
};
