#include <metal_stdlib>
using namespace metal;

/// Distortion for the words where they are under water: each row of pixels is shifted sideways
/// along a slow wave, so the letters sway the way things do when seen through moving water.
///
/// - position: destination pixel, in the view's own coordinates (points).
/// - time: animation phase in radians, already wrapped to 0...2π. Both waves below repeat every
///   2π of `time`, so the wrap is seamless.
/// - amplitude: maximum sideways shift, in points.
/// - wavelength: vertical distance between wave crests, in points.
/// - waterline: y of the water's front edge; the sway fades in below it so the words don't jump
///   where they meet the crisp, above-water part.
[[ stitchable ]] float2 underwaterWave(float2 position, float time, float amplitude, float wavelength, float waterline) {
    float k = 6.2831853 / wavelength;
    // A main wave plus a smaller, faster one so the motion doesn't look mechanical.
    float wave = sin(position.y * k + time) + 0.35 * sin(position.y * k * 2.3 - 2.0 * time);
    float fadeIn = clamp((position.y - waterline) / (wavelength * 0.25), 0.0, 1.0);
    return float2(position.x + wave * amplitude * fadeIn, position.y);
}
