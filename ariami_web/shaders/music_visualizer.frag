#version 460 core

#include <flutter/runtime_effect.glsl>

// The music visualizer (see lib/player/widgets/music_visualizer.dart): a
// warped fluid in the theme's colours where each voice of the music moves
// it its own way. Uniform order is the order the widget sets them in.

precision highp float;

uniform vec2 uSize;
uniform float uTime;
uniform float uFlow;
uniform float uHue;
uniform float uSnarePhase;
// Where the fluid has jumped to: each kick throws it somewhere new.
uniform vec2 uJump;
// A heavy bass hit's shake: how far the whole picture is knocked (xy) and
// punched in (z).
uniform vec3 uShake;
uniform vec3 uBase;
uniform vec3 uA;
uniform vec3 uB;
uniform vec3 uC;
uniform float uBass;
uniform float uVocal;
uniform float uOther;
uniform float uHats;
uniform float uSnare;
uniform float uKick;
uniform float uWeird;
uniform float uFlash;
// Where the kit and the instruments sit in the stereo image: -1 left, 1 right.
uniform float uDrumPan;
uniform float uInstrumentPan;
// The last four kicks: seconds since each, strength, and origin (as
// fractions of the screen).
uniform vec4 uKickAge;
uniform vec4 uKickAmp;
uniform vec4 uKickX;
uniform vec4 uKickY;

out vec4 fragColor;

float hash(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
             mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 5; i++) {
    v += a * noise(p);
    p = mat2(1.6, 1.2, -1.2, 1.6) * p + 3.1;
    a *= 0.5;
  }
  return v;
}

// Cycles glow C -> B -> A -> C.
vec3 pal(float t) {
  t = fract(t) * 3.0;
  vec3 c = mix(uC, uB, smoothstep(0.0, 1.0, t));
  c = mix(c, uA, smoothstep(1.0, 2.0, t));
  return mix(c, uC, smoothstep(2.0, 3.0, t));
}

// A kick's expanding ring: how far it pushes space outward here (xy) and
// how brightly it glows (z).
vec3 shock(vec2 p, float ox, float oy, float age, float amp) {
  vec2 o = (vec2(ox, oy) - 0.5) * uSize / min(uSize.x, uSize.y);
  vec2 d = p - o;
  float r = length(d) + 1e-4;
  float w = 0.06 + age * 0.35;
  float x = (r - age * 1.5) / w;
  float band = exp(-x * x) * amp * exp(-age * 1.6);
  return vec3(d / r * band, band);
}

// A vocal ribbon wandering up and down the whole screen around [centre].
float ribbon(vec2 p, float centre, float amp, float freq, float phase, float thick) {
  float y = centre + amp * sin(p.x * freq + phase);
  return thick / (abs(p.y - y) + thick);
}

void main() {
  vec2 uv = (FlutterFragCoord().xy - 0.5 * uSize) / min(uSize.x, uSize.y);
  vec2 p = uv * (1.0 - uShake.z) + uShake.xy;

  // Kick: shockwaves shove the field outward.
  vec3 k = shock(p, uKickX.x, uKickY.x, uKickAge.x, uKickAmp.x)
         + shock(p, uKickX.y, uKickY.y, uKickAge.y, uKickAmp.y)
         + shock(p, uKickX.z, uKickY.z, uKickAge.z, uKickAmp.z)
         + shock(p, uKickX.w, uKickY.w, uKickAge.w, uKickAmp.w);
  p -= k.xy * 0.09 * uWeird;

  // Snare: the field shears and ripples.
  p.x += sin(p.y * 13.0 + uSnarePhase * 6.0) * 0.08 * uSnare * uWeird;
  p.y += sin(p.x * 9.0 - uSnarePhase * 5.0) * 0.05 * uSnare * uWeird;

  // Bass: domain warp, so the whole fluid swells and folds harder. Fine
  // enough that several folds fill the screen at once.
  vec2 w = p * 2.1 + uJump;
  vec2 q = vec2(fbm(w + vec2(0.0, uFlow * 0.35)),
                fbm(w + vec2(5.2, 1.3) - uFlow * 0.3));
  float warp = (0.9 + 2.2 * uBass) * uWeird;
  vec2 r = vec2(fbm(w + warp * q + vec2(1.7, 9.2) + uFlow * 0.18),
                fbm(w + warp * q + vec2(8.3, 2.8) - uFlow * 0.15));
  float f = fbm(w + warp * r);

  // Stereo: the two halves of the screen trade colours as the instruments
  // swing from one side to the other.
  float side = clamp(uv.x * 1.5, -1.0, 1.0);
  float swap = 0.33 * uInstrumentPan * side;

  // Only the folds light up, over deep base in the troughs, with bright
  // crests along their ridges.
  vec3 glow = pal(f * 1.1 + uHue + r.x * 0.7 + swap);
  float body = smoothstep(0.4, 0.8, f + 0.18 * uBass + 0.1 * length(q));
  vec3 col = mix(uBase, glow, body * body * (0.8 + 0.3 * uBass));
  float crest = smoothstep(0.62, 0.8, f + 0.1 * uBass);
  col += mix(glow, vec3(1.0), 0.3) * crest * 0.25;

  // Instruments: a second colour bleeds through the folds.
  col = mix(col, pal(uHue + 0.5 + q.y - swap), 0.6 * uOther * smoothstep(0.4, 0.9, r.y) * body);

  // Vocals light the scene: the lit folds brighten and warm while someone
  // sings, and three ribbons of light weave through the field, each roaming
  // the full height of the screen.
  vec3 voiceLight = mix(pal(uHue + 0.66), vec3(1.0), 0.5);
  col += voiceLight * uVocal * 0.14 * (0.3 + body);
  float amp = 0.12 + 0.22 * uVocal;
  float thick = 0.006 + 0.08 * uVocal;
  float bend = (q.y - 0.5) * 0.5;
  float r1 = ribbon(p, 0.4 * sin(uTime * 0.21) + bend, amp, 2.1,
                    uTime * 0.9 + r.x * 3.0 * uWeird, thick);
  float r2 = ribbon(p, 0.4 * sin(uTime * 0.17 + 2.5) + bend, amp * 0.7, 3.3,
                    -uTime * 0.7 + r.y * 3.0 * uWeird + 2.0, thick * 0.6);
  float r3 = ribbon(p, 0.4 * sin(uTime * 0.13 + 4.4) - bend, amp * 0.85, 1.6,
                    uTime * 0.5 + q.x * 3.0 * uWeird + 4.0, thick * 0.8);
  col += voiceLight * (r1 * r1 + 0.5 * r2 * r2 + 0.7 * r3 * r3) * uVocal * 1.2;

  // Hats: glitter twinkling on the brighter folds.
  vec2 g = p * 36.0 + vec2(0.0, uFlow * 2.0);
  vec2 id = floor(g);
  float h = hash(id);
  vec2 at = vec2(hash(id + 7.1), hash(id + 3.7)) * 0.5 + 0.25;
  float star = smoothstep(0.22, 0.0, length(fract(g) - at)) * step(0.55, h)
             * (0.5 + 0.5 * sin(uTime * (9.0 + h * 25.0) + h * 60.0));
  // Heaped up on the side the hats are panned.
  star *= max(0.0, 1.0 + 1.5 * uDrumPan * side);
  col += mix(glow, vec3(1.0), 0.6) * star * uHats * 3.0 * (0.4 + body);

  // Kick light: the rings glow and the whole frame lifts.
  col += mix(uA, vec3(1.0), 0.25) * k.z * 0.5 * uFlash;
  col *= 1.0 + 0.35 * uKick * uFlash;

  // The side the instruments lean toward burns brighter.
  col *= max(0.0, 1.0 + 0.45 * uInstrumentPan * side);
  col *= 1.0 - 0.12 * dot(uv, uv);
  // A contrast curve: darks sink, brights lift.
  col = pow(max(col, 0.0), vec3(1.3)) * 1.2;
  // A soft ceiling: past the knee, brights roll off toward it rather than
  // clipping to white, so a pale cover never washes out the player's text.
  // Hue is kept by scaling all three channels together.
  float peak = max(max(col.r, col.g), col.b);
  float knee = 0.55;
  float ceiling = 0.82;
  if (peak > knee) {
    float over = (peak - knee) / (ceiling - knee);
    col *= (knee + (ceiling - knee) * (1.0 - exp(-over))) / peak;
  }
  col += (hash(FlutterFragCoord().xy + fract(uTime)) - 0.5) / 255.0;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
