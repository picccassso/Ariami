// (Ariami fork) Native iOS/macOS graphic equalizer for just_audio.
//
// AVPlayer exposes no equalizer API, so this implements one with an
// MTAudioProcessingTap attached to each AVPlayerItem's audioMix, running a
// cascade of RBJ peaking biquad filters over the PCM stream. Band gains are
// shared across all taps (current item, preloaded items) and may be updated
// live from the main thread while the render thread is processing.
#import <AVFoundation/AVFoundation.h>

@interface JAEqualizer : NSObject

- (instancetype)initWithFrequencies:(NSArray<NSNumber *> *)frequencies
                              gains:(NSArray<NSNumber *> *)gains
                            enabled:(BOOL)enabled;

- (void)setEnabled:(BOOL)enabled;
- (BOOL)isEnabled;
- (void)setGain:(double)gain forBand:(int)bandIndex;

/// Attaches the processing tap to the item if not already attached. Must be
/// called once the item's asset tracks are loaded (e.g. on ReadyToPlay).
- (void)attachToPlayerItem:(AVPlayerItem *)item;

@end
