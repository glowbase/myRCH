#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// Which of the RCH logo's five leaf colours a pixel belongs to, by hue:
/// 0 red, 1 orange, 2 yellow, 3 green, 4 teal; -1 for everything else (the
/// navy or white figure, and the transparent background). The logo's leaves
/// sit near 345°, 22°, 45°, 75° and 190°; the navy figure near 225°.
static int leafGroup(float3 rgb) {
    float high = max(rgb.r, max(rgb.g, rgb.b));
    float low = min(rgb.r, min(rgb.g, rgb.b));
    float delta = high - low;
    // Greys and the white dark-mode figure have no hue to speak of.
    if (high <= 0.0 || delta / high < 0.25) return -1;

    float hue;
    if (high == rgb.r) {
        hue = (rgb.g - rgb.b) / delta;
    } else if (high == rgb.g) {
        hue = (rgb.b - rgb.r) / delta + 2.0;
    } else {
        hue = (rgb.r - rgb.g) / delta + 4.0;
    }
    hue = fmod(hue * 60.0 + 360.0, 360.0);

    if (hue >= 300.0 || hue < 10.0) return 0;
    if (hue < 35.0) return 1;
    if (hue < 60.0) return 2;
    if (hue < 140.0) return 3;
    if (hue < 210.0) return 4;
    return -1;
}

/// Pulses the logo's leaves between their colour and a dim grey, one colour
/// after another (red, orange, yellow, green, teal), so the colour ripples
/// around the tree. `color` is premultiplied; its hue survives that.
/// `strength` eases the effect in from 0 (the plain logo) to 1, so it takes
/// over from the still launch screen without a jump.
[[ stitchable ]] half4 leafPulse(float2 position, half4 color, float time, float period, float strength) {
    if (color.a <= 0.0h) return color;
    int group = leafGroup(float3(color.rgb));
    if (group < 0) return color;

    // 1 when this colour's leaves are fully "on", 0 when "off". The
    // smoothstep squares the cosine off a little, so each leaf holds its
    // colour (and its grey) for a moment rather than drifting through.
    float wave = 0.5 + 0.5 * cos(2.0 * M_PI_F * (time / period - float(group) / 5.0));
    float on = mix(1.0, smoothstep(0.2, 0.8, wave), saturate(strength));

    half3 grey = half3(dot(color.rgb, half3(0.299h, 0.587h, 0.114h)));
    half3 rgb = mix(grey, color.rgb, half(on));
    // Off leaves also fade back a little, like a light going out.
    half fade = mix(0.4h, 1.0h, half(on));
    return half4(rgb, color.a) * fade;
}
