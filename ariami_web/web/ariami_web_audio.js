(() => {
  'use strict';

  const DEFAULT_FREQUENCIES = [60, 230, 910, 3600, 14000];
  const EQ_Q = 1.4;
  const METER_Q = Math.SQRT1_2;
  const FFT_SIZE = 1024;
  const BAND_COUNT = 11;

  class Biquad {
    constructor(kind, frequency, q, sampleRate) {
      const w0 = (2 * Math.PI * frequency) / sampleRate;
      const cosw0 = Math.cos(w0);
      const alpha = Math.sin(w0) / (2 * q);
      const a0 = 1 + alpha;
      if (kind === 'band') {
        this.b0 = alpha / a0;
        this.b1 = 0;
        this.b2 = -this.b0;
      } else {
        const high = kind === 'high';
        const edge = (high ? 1 + cosw0 : 1 - cosw0) / 2;
        this.b0 = edge / a0;
        this.b1 = ((high ? -2 : 2) * edge) / a0;
        this.b2 = this.b0;
      }
      this.a1 = (-2 * cosw0) / a0;
      this.a2 = (1 - alpha) / a0;
      this.x1 = 0;
      this.x2 = 0;
      this.y1 = 0;
      this.y2 = 0;
    }

    process(x0) {
      const y0 =
        this.b0 * x0 +
        this.b1 * this.x1 +
        this.b2 * this.x2 -
        this.a1 * this.y1 -
        this.a2 * this.y2;
      this.x2 = this.x1;
      this.x1 = x0;
      this.y2 = this.y1;
      this.y1 = y0;
      return y0;
    }
  }

  class Bands {
    constructor(sampleRate) {
      this.kickHp = new Biquad('high', 35, METER_Q, sampleRate);
      this.kickLp = new Biquad('low', 150, METER_Q, sampleRate);
      this.bassHp = new Biquad('high', 40, METER_Q, sampleRate);
      this.bassLp = new Biquad('low', 250, METER_Q, sampleRate);
      this.snareLo = new Biquad('band', 200, 1.2, sampleRate);
      this.snareHi = new Biquad('band', 2500, 0.9, sampleRate);
      this.hats = new Biquad('high', 7000, METER_Q, sampleRate);
      this.midHp = new Biquad('high', 300, METER_Q, sampleRate);
      this.midLp = new Biquad('low', 3400, METER_Q, sampleRate);
      this.sideHp = new Biquad('high', 300, METER_Q, sampleRate);
      this.sideLp = new Biquad('low', 3400, METER_Q, sampleRate);
      this.wideHp = new Biquad('high', 150, METER_Q, sampleRate);
      this.wideLp = new Biquad('low', 8000, METER_Q, sampleRate);
      this.highL = new Biquad('high', 7000, METER_Q, sampleRate);
      this.highR = new Biquad('high', 7000, METER_Q, sampleRate);
      this.midsLHp = new Biquad('high', 150, METER_Q, sampleRate);
      this.midsLLp = new Biquad('low', 8000, METER_Q, sampleRate);
      this.midsRHp = new Biquad('high', 150, METER_Q, sampleRate);
      this.midsRLp = new Biquad('low', 8000, METER_Q, sampleRate);
      this.alpha = 1 - Math.exp(-1 / (0.008 * sampleRate));
      this.energy = new Float64Array(BAND_COUNT);
    }

    pushSample(left, right) {
      const mid = 0.5 * (left + right);
      const side = 0.5 * (left - right);
      const vals = [
        this.kickLp.process(this.kickHp.process(mid)),
        this.bassLp.process(this.bassHp.process(mid)),
        this.snareLo.process(mid) + this.snareHi.process(mid),
        this.hats.process(mid),
        this.midLp.process(this.midHp.process(mid)),
        this.sideLp.process(this.sideHp.process(side)),
        this.wideLp.process(this.wideHp.process(side)),
        this.highL.process(left),
        this.highR.process(right),
        this.midsLLp.process(this.midsLHp.process(left)),
        this.midsRLp.process(this.midsRHp.process(right)),
      ];
      for (let n = 0; n < BAND_COUNT; n++) {
        this.energy[n] += this.alpha * (vals[n] * vals[n] - this.energy[n]);
      }
    }

    read() {
      const out = new Array(BAND_COUNT);
      for (let n = 0; n < BAND_COUNT; n++) {
        out[n] = Math.sqrt(this.energy[n]);
      }
      return out;
    }

    reset() {
      this.energy.fill(0);
    }
  }

  let audioCtx = null;
  let eqFilters = null;
  let analyserL = null;
  let analyserR = null;
  let bandsFilter = null;
  let bufL = null;
  let bufR = null;
  let activeElement = null;
  let lastSampleTime = null;
  let meteringEnabled = false;

  const sourceNodes = new WeakMap();
  const eqState = {
    enabled: false,
    frequencies: DEFAULT_FREQUENCIES.slice(),
    gains: new Array(DEFAULT_FREQUENCIES.length).fill(0),
  };

  function ensureGraph() {
    if (audioCtx) return audioCtx;
    const AudioContextCtor = window.AudioContext || window.webkitAudioContext;
    if (!AudioContextCtor) return null;

    audioCtx = new AudioContextCtor();
    eqFilters = DEFAULT_FREQUENCIES.map((freq) => {
      const filter = audioCtx.createBiquadFilter();
      filter.type = 'peaking';
      filter.frequency.value = freq;
      filter.Q.value = EQ_Q;
      filter.gain.value = 0;
      return filter;
    });
    for (let i = 0; i < eqFilters.length - 1; i++) {
      eqFilters[i].connect(eqFilters[i + 1]);
    }

    const tail = eqFilters[eqFilters.length - 1];
    tail.connect(audioCtx.destination);

    const meterBus = audioCtx.createGain();
    meterBus.channelCount = 2;
    meterBus.channelCountMode = 'explicit';
    meterBus.channelInterpretation = 'speakers';
    const splitter = audioCtx.createChannelSplitter(2);
    analyserL = audioCtx.createAnalyser();
    analyserR = audioCtx.createAnalyser();
    analyserL.fftSize = FFT_SIZE;
    analyserR.fftSize = FFT_SIZE;
    analyserL.smoothingTimeConstant = 0;
    analyserR.smoothingTimeConstant = 0;

    tail.connect(meterBus);
    meterBus.connect(splitter);
    splitter.connect(analyserL, 0);
    splitter.connect(analyserR, 1);

    bufL = new Float32Array(FFT_SIZE);
    bufR = new Float32Array(FFT_SIZE);
    bandsFilter = new Bands(audioCtx.sampleRate);
    applyEqToFilters();
    return audioCtx;
  }

  function applyEqToFilters() {
    if (!eqFilters || !audioCtx) return;
    const maxFreq = audioCtx.sampleRate * 0.49;
    for (let i = 0; i < eqFilters.length; i++) {
      const filter = eqFilters[i];
      const freq = Number(eqState.frequencies[i]);
      if (Number.isFinite(freq) && freq > 0) {
        filter.frequency.value = Math.min(freq, maxFreq);
      }
      const gain = eqState.enabled ? Number(eqState.gains[i]) || 0 : 0;
      filter.gain.value = Number.isFinite(gain) ? gain : 0;
    }
  }

  function resumeAudioContext() {
    if (audioCtx && audioCtx.state === 'suspended') {
      audioCtx.resume().catch(() => {});
    }
  }

  function attachElement(el) {
    if (!audioCtx && !ensureGraph()) return;
    resumeAudioContext();
    try {
      let source = sourceNodes.get(el);
      if (!source) {
        source = audioCtx.createMediaElementSource(el);
        sourceNodes.set(el, source);
      }
      source.connect(eqFilters[0]);
    } catch (_) {
      // Ignore if element cannot be attached.
    }
    activeElement = el;
  }

  const origCreateElement = document.createElement;
  document.createElement = function (tagName) {
    const el = origCreateElement.apply(this, arguments);
    if (typeof tagName === 'string' && tagName.toLowerCase() === 'audio') {
      el.crossOrigin = 'anonymous';
      el.addEventListener('play', () => attachElement(el));
      // A released element leaves the graph so it can be garbage collected.
      el.addEventListener('emptied', () => {
        if (!el.getAttribute('src')) sourceNodes.get(el)?.disconnect();
      });
      el.addEventListener('playing', () => {
        activeElement = el;
        resumeAudioContext();
      });
    }
    return el;
  };

  window.addEventListener('pointerdown', resumeAudioContext, { passive: true });
  window.addEventListener('keydown', resumeAudioContext, { passive: true });

  window.ariamiWebAudio = {
    setEqualizer(enabled, frequencies, gains) {
      eqState.enabled = Boolean(enabled);
      if (frequencies && frequencies.length === DEFAULT_FREQUENCIES.length) {
        eqState.frequencies = Array.from(frequencies);
      }
      if (gains && gains.length === DEFAULT_FREQUENCIES.length) {
        eqState.gains = Array.from(gains);
      }
      applyEqToFilters();
    },

    setMeteringEnabled(enabled) {
      meteringEnabled = Boolean(enabled);
      lastSampleTime = null;
      if (!meteringEnabled && bandsFilter) {
        bandsFilter.reset();
      }
    },

    sampleBands() {
      if (
        !meteringEnabled ||
        !audioCtx ||
        audioCtx.state !== 'running' ||
        !analyserL ||
        !analyserR ||
        !bandsFilter ||
        !activeElement ||
        activeElement.paused ||
        activeElement.ended
      ) {
        lastSampleTime = null;
        return null;
      }

      const now = audioCtx.currentTime;
      let dt = lastSampleTime === null ? 1 / 60 : now - lastSampleTime;
      if (dt <= 0) return null;
      lastSampleTime = now;
      if (dt > 0.1) dt = 0.1;

      analyserL.getFloatTimeDomainData(bufL);
      analyserR.getFloatTimeDomainData(bufR);

      const count = Math.min(
        FFT_SIZE,
        Math.max(1, Math.round(dt * audioCtx.sampleRate)),
      );
      const start = FFT_SIZE - count;
      for (let i = start; i < FFT_SIZE; i++) {
        bandsFilter.pushSample(bufL[i], bufR[i]);
      }
      return {
        bands: bandsFilter.read(),
        dt,
      };
    },
  };
})();
