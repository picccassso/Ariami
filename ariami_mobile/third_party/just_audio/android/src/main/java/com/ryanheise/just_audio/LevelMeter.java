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
 * (Ariami fork) Band metering of what the player is playing, for UI that
 * follows the music. Mirrors the Darwin meter in JAEqualizer.m: the energy
 * envelope of each of {@link #BANDS} bands (see NativeLevels in
 * just_audio.dart) is read every {@link #BLOCK} frames. The sink receives
 * audio well ahead of the speakers, so each reading is stamped with its
 * presentation time and handed out only once the playhead reaches it.
 */
final class LevelMeter {
    private static final int BLOCK = 256;
    private static final int BANDS = 11;
    private static final int RING = 2048; // a power of two, for masking
    private static final double[] ringTime = new double[RING];
    private static final float[][] ringLevel = new float[RING][BANDS];
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
     * Main thread only. The seconds each reading covers, the bands per
     * reading, then the readings played since the last call, oldest first;
     * null while nothing plays.
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
        double[] batch = new double[count * BANDS + 2];
        int size = 2;
        batch[0] = blockSeconds;
        batch[1] = BANDS;
        for (int n = head - count; n != head; n++) {
            int slot = n & (RING - 1);
            double time = ringTime[slot];
            if (time <= lastRead || time > now) continue;
            for (float level : ringLevel[slot]) batch[size++] = level;
        }
        lastRead = now;
        return Arrays.copyOf(batch, size);
    }

    // The meter's filters, as in JAEqualizer.m. Mid is the centre of the
    // stereo image (the mean of the channels), side its spread (L-R)/2.
    private static final double HIGH = 0, LOW = 1, BAND = 2;
    private static final double Q = Math.sqrt(0.5);
    private static final int KICK_HP = 0, KICK_LP = 1;     // mid 35–150 Hz
    private static final int BASS_HP = 2, BASS_LP = 3;     // mid 40–250 Hz
    private static final int SNARE_LO = 4, SNARE_HI = 5;   // mid 200 Hz + 2.5 kHz, in parallel
    private static final int HATS_HP = 6;                  // mid above 7 kHz
    private static final int MID_HP = 7, MID_LP = 8;       // mid 300–3400 Hz
    private static final int SIDE_HP = 9, SIDE_LP = 10;    // side 300–3400 Hz
    private static final int WIDE_HP = 11, WIDE_LP = 12;   // side 150–8000 Hz
    private static final int HIGH_L = 13, HIGH_R = 14;     // left and right above 7 kHz
    private static final int MIDS_L_HP = 15, MIDS_L_LP = 16, MIDS_R_HP = 17, MIDS_R_LP = 18; // left and right 150–8000 Hz
    private static final double[][] FILTERS = {
        {HIGH, 35, Q}, {LOW, 150, Q},
        {HIGH, 40, Q}, {LOW, 250, Q},
        {BAND, 200, 1.2}, {BAND, 2500, 0.9},
        {HIGH, 7000, Q},
        {HIGH, 300, Q}, {LOW, 3400, Q},
        {HIGH, 300, Q}, {LOW, 3400, Q},
        {HIGH, 150, Q}, {LOW, 8000, Q},
        {HIGH, 7000, Q}, {HIGH, 7000, Q},
        {HIGH, 150, Q}, {LOW, 8000, Q},
        {HIGH, 150, Q}, {LOW, 8000, Q},
    };

    /** Wraps a player's audio sink to meter the PCM it is handed. */
    static final class Sink extends ForwardingAudioSink {
        private int encoding = Format.NO_VALUE;
        private int channels;
        private double sampleRate;
        // Biquad coefficients {b0, b1, b2, a1, a2} and states {x1, x2, y1, y2},
        // one per entry of FILTERS.
        private final double[][] coeffs = new double[FILTERS.length][5];
        private final double[][] states = new double[FILTERS.length][4];
        private final double[] energy = new double[BANDS];
        private double alpha;
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
            for (int n = 0; n < FILTERS.length; n++) {
                filterCoefficients(coeffs[n], FILTERS[n]);
                Arrays.fill(states[n], 0);
            }
            alpha = 1.0 - Math.exp(-1.0 / (0.008 * sampleRate));
            Arrays.fill(energy, 0);
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
            double[] bands = new double[BANDS];
            for (int i = 0; i < frames; i++) {
                double mid = 0, left = 0, right = 0;
                for (int c = 0; c < channels; c++) {
                    int index = base + i * frameBytes + c * bytesPerSample;
                    double x = bytesPerSample == 2 ? pcm.getShort(index) / 32768.0 : pcm.getFloat(index);
                    if (c == 0) left = x;
                    else if (c == 1) right = x;
                    mid += x;
                }
                mid /= channels;
                if (channels == 1) right = left;
                double side = 0.5 * (left - right);
                bands[0] = filter(KICK_LP, filter(KICK_HP, mid));
                bands[1] = filter(BASS_LP, filter(BASS_HP, mid));
                bands[2] = filter(SNARE_LO, mid) + filter(SNARE_HI, mid);
                bands[3] = filter(HATS_HP, mid);
                bands[4] = filter(MID_LP, filter(MID_HP, mid));
                bands[5] = filter(SIDE_LP, filter(SIDE_HP, side));
                bands[6] = filter(WIDE_LP, filter(WIDE_HP, side));
                bands[7] = filter(HIGH_L, left);
                bands[8] = filter(HIGH_R, right);
                bands[9] = filter(MIDS_L_LP, filter(MIDS_L_HP, left));
                bands[10] = filter(MIDS_R_LP, filter(MIDS_R_HP, right));
                for (int n = 0; n < BANDS; n++) {
                    energy[n] += alpha * (bands[n] * bands[n] - energy[n]);
                }
                if (++blockCount < BLOCK) continue;
                blockCount = 0;
                int head = ringHead.get();
                int slot = head & (RING - 1);
                ringTime[slot] = start + (i + 1) / sampleRate;
                for (int n = 0; n < BANDS; n++) {
                    ringLevel[slot][n] = (float) Math.sqrt(energy[n]);
                }
                ringHead.set(head + 1);
            }
        }

        // RBJ Audio EQ Cookbook high-/low-pass and band-pass (0 dB peak).
        // [filter] is {kind, frequency, q}.
        private void filterCoefficients(double[] c, double[] filter) {
            double w0 = 2.0 * Math.PI * filter[1] / sampleRate;
            double cosw0 = Math.cos(w0);
            double alpha = Math.sin(w0) / (2.0 * filter[2]);
            double a0 = 1.0 + alpha;
            if (filter[0] == BAND) {
                c[0] = alpha / a0;
                c[1] = 0;
                c[2] = -c[0];
            } else {
                boolean high = filter[0] == HIGH;
                double edge = high ? (1.0 + cosw0) / 2.0 : (1.0 - cosw0) / 2.0;
                c[0] = edge / a0;
                c[1] = (high ? -2.0 : 2.0) * edge / a0;
                c[2] = c[0];
            }
            c[3] = -2.0 * cosw0 / a0;
            c[4] = (1.0 - alpha) / a0;
        }

        private double filter(int n, double x0) {
            return biquad(coeffs[n], states[n], x0);
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
