#import "./include/just_audio/JAEqualizer.h"
#import <MediaToolbox/MediaToolbox.h>
#import <stdatomic.h>
#import <math.h>
#import <stdlib.h>
#import <string.h>

#define JA_EQ_MAX_BANDS 10
// Filter quality for each peaking band. ~0.9 gives gentle overlap for a
// 5-band layout spanning 60Hz-14kHz.
#define JA_EQ_BAND_Q 0.9

// Gain/enabled state shared between the main thread and every render tap.
// Reference-counted with plain C atomics because taps can outlive the
// JAEqualizer that spawned them (AVFoundation finalizes taps asynchronously).
typedef struct {
    atomic_int refCount;
    int bandCount;
    float frequencies[JA_EQ_MAX_BANDS];
    _Atomic float gains[JA_EQ_MAX_BANDS];
    atomic_bool enabled;
    // Bumped after every gain change; taps recompute coefficients when the
    // value they cached falls behind.
    atomic_int generation;
} JAEqSharedState;

typedef struct {
    // Direct form 1 coefficients (already normalized by a0).
    float b0, b1, b2, a1, a2;
} JAEqBiquadCoeffs;

typedef struct {
    float x1, x2, y1, y2;
} JAEqBiquadState;

// Per-tap DSP context. Created in the tap's init callback, sized in prepare,
// freed in finalize. Only ever touched by the render thread after prepare.
typedef struct {
    JAEqSharedState *shared;
    int cachedGeneration;
    double sampleRate;
    int channelCount;
    JAEqBiquadCoeffs coeffs[JA_EQ_MAX_BANDS];
    bool bandActive[JA_EQ_MAX_BANDS];
    // bandCount * channelCount states, laid out band-major.
    JAEqBiquadState *states;
} JAEqTapContext;

static void ja_eq_shared_release(JAEqSharedState *shared) {
    if (atomic_fetch_sub(&shared->refCount, 1) == 1) {
        free(shared);
    }
}

// RBJ Audio EQ Cookbook peaking filter.
static JAEqBiquadCoeffs ja_eq_peaking_coeffs(double sampleRate, double frequency, double gainDb) {
    JAEqBiquadCoeffs c;
    double A = pow(10.0, gainDb / 40.0);
    double w0 = 2.0 * M_PI * frequency / sampleRate;
    double cosw0 = cos(w0);
    double alpha = sin(w0) / (2.0 * JA_EQ_BAND_Q);
    double a0 = 1.0 + alpha / A;
    c.b0 = (float)((1.0 + alpha * A) / a0);
    c.b1 = (float)((-2.0 * cosw0) / a0);
    c.b2 = (float)((1.0 - alpha * A) / a0);
    c.a1 = (float)((-2.0 * cosw0) / a0);
    c.a2 = (float)((1.0 - alpha / A) / a0);
    return c;
}

static void ja_eq_refresh_coeffs(JAEqTapContext *ctx) {
    int generation = atomic_load_explicit(&ctx->shared->generation, memory_order_acquire);
    if (generation == ctx->cachedGeneration) return;
    ctx->cachedGeneration = generation;
    for (int band = 0; band < ctx->shared->bandCount; band++) {
        float gain = atomic_load_explicit(&ctx->shared->gains[band], memory_order_relaxed);
        double frequency = ctx->shared->frequencies[band];
        // Filters above Nyquist are unstable; skip them (can happen for a
        // 14kHz band on low-sample-rate audio).
        if (fabsf(gain) < 0.01f || frequency >= ctx->sampleRate / 2.0) {
            ctx->bandActive[band] = false;
        } else {
            ctx->bandActive[band] = true;
            ctx->coeffs[band] = ja_eq_peaking_coeffs(ctx->sampleRate, frequency, gain);
        }
    }
}

static void ja_eq_process_channel(JAEqTapContext *ctx, int channel, float *samples,
                                  CMItemCount frames, size_t stride) {
    for (int band = 0; band < ctx->shared->bandCount; band++) {
        if (!ctx->bandActive[band]) continue;
        JAEqBiquadCoeffs c = ctx->coeffs[band];
        JAEqBiquadState *s = &ctx->states[band * ctx->channelCount + channel];
        float x1 = s->x1, x2 = s->x2, y1 = s->y1, y2 = s->y2;
        float *p = samples;
        for (CMItemCount i = 0; i < frames; i++, p += stride) {
            float x0 = *p;
            float y0 = c.b0 * x0 + c.b1 * x1 + c.b2 * x2 - c.a1 * y1 - c.a2 * y2;
            *p = y0;
            x2 = x1; x1 = x0;
            y2 = y1; y1 = y0;
        }
        s->x1 = x1; s->x2 = x2; s->y1 = y1; s->y2 = y2;
    }
}

static void ja_eq_tap_init(MTAudioProcessingTapRef tap, void *clientInfo, void **tapStorageOut) {
    JAEqTapContext *ctx = calloc(1, sizeof(JAEqTapContext));
    ctx->shared = (JAEqSharedState *)clientInfo;
    atomic_fetch_add(&ctx->shared->refCount, 1);
    ctx->cachedGeneration = -1;
    *tapStorageOut = ctx;
}

static void ja_eq_tap_finalize(MTAudioProcessingTapRef tap) {
    JAEqTapContext *ctx = MTAudioProcessingTapGetStorage(tap);
    ja_eq_shared_release(ctx->shared);
    free(ctx->states);
    free(ctx);
}

static void ja_eq_tap_prepare(MTAudioProcessingTapRef tap, CMItemCount maxFrames,
                              const AudioStreamBasicDescription *processingFormat) {
    JAEqTapContext *ctx = MTAudioProcessingTapGetStorage(tap);
    ctx->sampleRate = processingFormat->mSampleRate;
    ctx->channelCount = (int)processingFormat->mChannelsPerFrame;
    if (ctx->channelCount < 1) ctx->channelCount = 1;
    free(ctx->states);
    ctx->states = calloc((size_t)ctx->shared->bandCount * ctx->channelCount,
                         sizeof(JAEqBiquadState));
    ctx->cachedGeneration = -1;
}

static void ja_eq_tap_unprepare(MTAudioProcessingTapRef tap) {
    JAEqTapContext *ctx = MTAudioProcessingTapGetStorage(tap);
    free(ctx->states);
    ctx->states = NULL;
}

static void ja_eq_tap_process(MTAudioProcessingTapRef tap, CMItemCount numberFrames,
                              MTAudioProcessingTapFlags flags,
                              AudioBufferList *bufferListInOut,
                              CMItemCount *numberFramesOut,
                              MTAudioProcessingTapFlags *flagsOut) {
    OSStatus status = MTAudioProcessingTapGetSourceAudio(
        tap, numberFrames, bufferListInOut, flagsOut, NULL, numberFramesOut);
    if (status != noErr) return;

    JAEqTapContext *ctx = MTAudioProcessingTapGetStorage(tap);
    if (!ctx->states) return;
    if (!atomic_load_explicit(&ctx->shared->enabled, memory_order_relaxed)) return;

    ja_eq_refresh_coeffs(ctx);

    // The processing format is float32; buffers are one-per-channel when
    // deinterleaved, or a single interleaved buffer otherwise.
    int channel = 0;
    for (UInt32 b = 0; b < bufferListInOut->mNumberBuffers; b++) {
        AudioBuffer *buffer = &bufferListInOut->mBuffers[b];
        float *data = (float *)buffer->mData;
        if (!data) continue;
        UInt32 bufferChannels = buffer->mNumberChannels > 0 ? buffer->mNumberChannels : 1;
        for (UInt32 c = 0; c < bufferChannels; c++) {
            if (channel >= ctx->channelCount) break;
            ja_eq_process_channel(ctx, channel, data + c, *numberFramesOut, bufferChannels);
            channel++;
        }
    }
}

@implementation JAEqualizer {
    JAEqSharedState *_shared;
}

- (instancetype)initWithFrequencies:(NSArray<NSNumber *> *)frequencies
                              gains:(NSArray<NSNumber *> *)gains
                            enabled:(BOOL)enabled {
    self = [super init];
    NSAssert(self, @"super init cannot be nil");
    _shared = calloc(1, sizeof(JAEqSharedState));
    atomic_init(&_shared->refCount, 1);
    _shared->bandCount = (int)MIN(frequencies.count, (NSUInteger)JA_EQ_MAX_BANDS);
    for (int i = 0; i < _shared->bandCount; i++) {
        _shared->frequencies[i] = frequencies[i].floatValue;
        float gain = i < (int)gains.count ? gains[i].floatValue : 0.0f;
        atomic_init(&_shared->gains[i], gain);
    }
    atomic_init(&_shared->enabled, enabled);
    atomic_init(&_shared->generation, 0);
    return self;
}

- (void)dealloc {
    ja_eq_shared_release(_shared);
}

- (void)setEnabled:(BOOL)enabled {
    atomic_store(&_shared->enabled, enabled);
}

- (void)setGain:(double)gain forBand:(int)bandIndex {
    if (bandIndex < 0 || bandIndex >= _shared->bandCount) return;
    atomic_store_explicit(&_shared->gains[bandIndex], (float)gain, memory_order_relaxed);
    atomic_fetch_add_explicit(&_shared->generation, 1, memory_order_release);
}

- (void)attachToPlayerItem:(AVPlayerItem *)item {
    if (item.audioMix) return;
    NSArray<AVAssetTrack *> *tracks = [item.asset tracksWithMediaType:AVMediaTypeAudio];
    if (tracks.count == 0) return;

    MTAudioProcessingTapCallbacks callbacks;
    callbacks.version = kMTAudioProcessingTapCallbacksVersion_0;
    callbacks.clientInfo = _shared;
    callbacks.init = ja_eq_tap_init;
    callbacks.finalize = ja_eq_tap_finalize;
    callbacks.prepare = ja_eq_tap_prepare;
    callbacks.unprepare = ja_eq_tap_unprepare;
    callbacks.process = ja_eq_tap_process;

    MTAudioProcessingTapRef tap = NULL;
    OSStatus status = MTAudioProcessingTapCreate(
        kCFAllocatorDefault, &callbacks,
        kMTAudioProcessingTapCreationFlag_PreEffects, &tap);
    if (status != noErr || !tap) return;

    AVMutableAudioMixInputParameters *inputParams =
        [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:tracks[0]];
    inputParams.audioTapProcessor = tap;
    CFRelease(tap);

    AVMutableAudioMix *audioMix = [AVMutableAudioMix audioMix];
    audioMix.inputParameters = @[inputParams];
    item.audioMix = audioMix;
}

@end
