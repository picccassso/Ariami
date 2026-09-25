package com.ryanheise.just_audio;

import androidx.annotation.Nullable;
import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.exoplayer.audio.AudioSink;
import androidx.media3.exoplayer.audio.ForwardingAudioSink;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Arrays;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * (Ariami fork) Kick-band metering of what the player is playing, for UI that
 * follows the music. Mirrors the Darwin meter in JAEqualizer.m: the 35–150 Hz
 * energy envelope of the mono mix is read every {@link #BLOCK} frames. The
 * sink receives audio well ahead of the speakers, so each reading is stamped
 * with its presentation time and handed out only once the playhead reaches it.
 */
final class LevelMeter {
    private static final int BLOCK = 256;
    private static final int RING = 2048; // a power of two, for masking
    private static final double[] ringTime = new double[RING];
    private static final float[] ringLevel = new float[RING];
    private static final AtomicInteger ringHead = new AtomicInteger();
    private static volatile boolean metering;
    private static volatile double blockSeconds;
    private static volatile double playheadSeconds = Double.NaN;
    // Main thread only: the time up to which readings have been returned.
    private static double lastRead = -1;

    private LevelMeter() {}

    static void setMetering(boolean enabled) {
        metering = enabled;
    }

    /**
     * Main thread only. The seconds each reading covers, then the readings
     * played since the last call, oldest first; null while nothing plays.
     */
    @Nullable
    static double[] levels() {
        double now = playheadSeconds;
        if (Double.isNaN(now)) return null;
        // A jump (seek, new track) restarts from just before the playhead
        // rather than replaying or skipping seconds of readings.
        if (lastRead < 0 || now < lastRead || now > lastRead + 0.5) {
            lastRead = now - 0.05;
        }
        int head = ringHead.get();
        int count = Math.min(head, RING);
        double[] batch = new double[count + 1];
        int size = 1;
        batch[0] = blockSeconds;
        for (int n = head - count; n != head; n++) {
            int slot = n & (RING - 1);
            double time = ringTime[slot];
            if (time <= lastRead || time > now) continue;
            batch[size++] = ringLevel[slot];
        }
        lastRead = now;
        return Arrays.copyOf(batch, size);
    }

    /** Wraps a player's audio sink to meter the PCM it is handed. */
    static final class Sink extends ForwardingAudioSink {
        private int encoding = Format.NO_VALUE;
        private int channels;
        private double sampleRate;
        // Biquad coefficients {b0, b1, b2, a1, a2} and states {x1, x2, y1, y2}.
        private final double[] hp = new double[5];
        private final double[] lp = new double[5];
        private final double[] hpState = new double[4];
        private final double[] lpState = new double[4];
        private double alpha;
        private double energy;
        private int blockCount;
        @Nullable private ByteBuffer lastBuffer;
        private long lastPresentationTimeUs = C.TIME_UNSET;

        Sink(AudioSink sink) {
            super(sink);
        }

        @Override
        public void configure(Format inputFormat, int specifiedBufferSize, @Nullable int[] outputChannels)
                throws ConfigurationException {
            super.configure(inputFormat, specifiedBufferSize, outputChannels);
            encoding = inputFormat.pcmEncoding;
            channels = Math.max(1, inputFormat.channelCount);
            sampleRate = inputFormat.sampleRate;
            if (sampleRate <= 0) {
                encoding = Format.NO_VALUE;
                return;
            }
            passCoefficients(hp, 35.0, true);
            passCoefficients(lp, 150.0, false);
            Arrays.fill(hpState, 0);
            Arrays.fill(lpState, 0);
            alpha = 1.0 - Math.exp(-1.0 / (0.008 * sampleRate));
            energy = 0;
            blockCount = 0;
            blockSeconds = BLOCK / sampleRate;
        }

        @Override
        public boolean handleBuffer(ByteBuffer buffer, long presentationTimeUs, int encodedAccessUnitCount)
                throws InitializationException, WriteException {
            // A buffer the sink couldn't take in full comes back again; meter
            // each one once.
            if (metering && (buffer != lastBuffer || presentationTimeUs != lastPresentationTimeUs)) {
                measure(buffer, presentationTimeUs);
            }
            lastBuffer = buffer;
            lastPresentationTimeUs = presentationTimeUs;
            return super.handleBuffer(buffer, presentationTimeUs, encodedAccessUnitCount);
        }

        @Override
        public long getCurrentPositionUs(boolean sourceEnded) {
            long position = super.getCurrentPositionUs(sourceEnded);
            if (position != CURRENT_POSITION_NOT_SET) playheadSeconds = position / 1e6;
            return position;
        }

        private void measure(ByteBuffer buffer, long presentationTimeUs) {
            int bytesPerSample;
            if (encoding == C.ENCODING_PCM_16BIT) {
                bytesPerSample = 2;
            } else if (encoding == C.ENCODING_PCM_FLOAT) {
                bytesPerSample = 4;
            } else {
                return;
            }
            ByteBuffer pcm = buffer.duplicate().order(ByteOrder.nativeOrder());
            int frameBytes = bytesPerSample * channels;
            int frames = pcm.remaining() / frameBytes;
            int base = pcm.position();
            double start = presentationTimeUs / 1e6;
            for (int i = 0; i < frames; i++) {
                double mono = 0;
                for (int c = 0; c < channels; c++) {
                    int index = base + i * frameBytes + c * bytesPerSample;
                    mono += bytesPerSample == 2 ? pcm.getShort(index) / 32768.0 : pcm.getFloat(index);
                }
                double band = biquad(lp, lpState, biquad(hp, hpState, mono / channels));
                energy += alpha * (band * band - energy);
                if (++blockCount < BLOCK) continue;
                blockCount = 0;
                int head = ringHead.get();
                int slot = head & (RING - 1);
                ringTime[slot] = start + (i + 1) / sampleRate;
                ringLevel[slot] = (float) Math.sqrt(energy);
                ringHead.set(head + 1);
            }
        }

        // RBJ Audio EQ Cookbook high-/low-pass (Q = 1/sqrt 2).
        private void passCoefficients(double[] c, double frequency, boolean high) {
            double w0 = 2.0 * Math.PI * frequency / sampleRate;
            double cosw0 = Math.cos(w0);
            double alpha = Math.sin(w0) / Math.sqrt(2.0);
            double a0 = 1.0 + alpha;
            double edge = high ? (1.0 + cosw0) / 2.0 : (1.0 - cosw0) / 2.0;
            c[0] = edge / a0;
            c[1] = (high ? -2.0 : 2.0) * edge / a0;
            c[2] = c[0];
            c[3] = -2.0 * cosw0 / a0;
            c[4] = (1.0 - alpha) / a0;
        }

        private static double biquad(double[] c, double[] s, double x0) {
            double y0 = c[0] * x0 + c[1] * s[0] + c[2] * s[1] - c[3] * s[2] - c[4] * s[3];
            s[1] = s[0];
            s[0] = x0;
            s[3] = s[2];
            s[2] = y0;
            return y0;
        }
    }
}
