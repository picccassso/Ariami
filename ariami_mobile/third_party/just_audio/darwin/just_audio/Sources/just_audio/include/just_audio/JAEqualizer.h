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

/// Whether items need the processing tap: the EQ is on, or levels are metered.
- (BOOL)wantsTap;

/// App-wide kick-band metering (35–150 Hz energy envelope of the mono mix,
/// linear 0–1) of whatever the tap is rendering. Off by default; costs
/// nothing when off.
+ (void)setMetering:(BOOL)metering;
+ (BOOL)isMetering;
/// Main thread only. Float64 values: the seconds each reading covers, then
/// the readings rendered since the last call up to [mediaTime] (the
/// playhead), oldest first.
+ (NSData *)levelsUntil:(double)mediaTime;

/// Attaches the processing tap to the item if not already attached. Must be
/// called once the item's asset tracks are loaded (e.g. on ReadyToPlay).
- (void)attachToPlayerItem:(AVPlayerItem *)item;

@end
