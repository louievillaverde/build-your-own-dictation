import MetalKit
import SwiftUI

/// The pill's surface: a Metal fragment shader compiled at launch (no Xcode toolchain needed).
/// Deep-water body with caustic light, a lit glass orb, glass rim and outer glow, all driven by voice level.
private let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct VOut { float4 pos [[position]]; float2 uv; };
struct U { float2 res; float margin; float scale; float time; float level; float phase; float phaseT; float orb; float style; float flow; float motion; float reel; float pad3; };

vertex VOut v_main(uint vid [[vertex_id]]) {
    float2 p[4] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1) };
    VOut o; o.pos = float4(p[vid], 0, 1); o.uv = p[vid] * 0.5 + 0.5; return o;
}

float caustic(float2 uv, float time) {
    float2 p = uv * 6.28318 - 250.0;
    float2 i = p; float c = 1.0; float inten = 0.005;
    for (int n = 0; n < 5; n++) {
        float t = time * (1.0 - (3.5 / float(n + 1)));
        i = p + float2(cos(t - i.x) + sin(t + i.y), sin(t - i.y) + cos(t + i.x));
        c += 1.0 / length(float2(p.x / (sin(i.x + t) / inten), p.y / (cos(i.y + t) / inten)));
    }
    c /= 5.0; c = 1.17 - pow(c, 1.4);
    return clamp(pow(abs(c), 8.0), 0.0, 1.0);
}

float hash11(float n) { return fract(sin(n * 127.1) * 43758.5453); }

// Caustic water:
// domain-warped value noise, folded into ridges, sharpened into filaments.
float2 hash2(float2 p) {
    p = float2(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453) * 2.0 - 1.0;
}
float vnoise(float2 p) {
    float2 i = floor(p); float2 f = fract(p); float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(dot(hash2(i), f), dot(hash2(i + float2(1, 0)), f - float2(1, 0)), u.x),
               mix(dot(hash2(i + float2(0, 1)), f - float2(0, 1)), dot(hash2(i + float2(1, 1)), f - float2(1, 1)), u.x), u.y) * 0.5 + 0.5;
}
float siteLayer(float2 uv, float t, float scale) {
    float2 warp = float2(vnoise(uv * scale + t), vnoise(uv * scale - t * 1.3));
    float n = vnoise(uv * scale + warp * 1.6 + t * 0.5);
    n = abs(n * 2.0 - 1.0);
    return pow(1.0 - n, 7.0);
}

// style: 0 deep water · 1 liquid glass · 2 neon wave
fragment float4 f_main(VOut in [[stage_in]], constant U& u [[buffer(0)]]) {
    float2 px = in.uv * u.res;
    float m = u.margin;
    float2 size = u.res - 2.0 * m;
    float r = min(size.x, size.y) * 0.5;
    float2 c = u.res * 0.5;
    float2 q = abs(px - c) - (size * 0.5 - r);
    bool vertical = size.y > size.x;
    float sd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    int style = int(u.style + 0.5);

    float lvl = u.level;
    float t = u.time;
    float3 aqua = float3(0.30, 0.84, 0.88);
    float3 amber = float3(1.00, 0.62, 0.22);
    float3 tint = u.phase > 3.5 ? amber : aqua;
    float xn = (px.x - m) / size.x;                        // 0..1 across the capsule
    float vy = (px.y - (c.y - size.y * 0.5)) / size.y;     // 0 bottom .. 1 top

    // Neon's glow cycles through the spectrum; the others keep the accent.
    float3 spectrum = 0.5 + 0.5 * cos(6.28318 * (xn * 0.6 + t * 0.12 + float3(0.0, 0.33, 0.67)));
    float3 glowTint = style == 2 && u.phase < 3.5 ? mix(float3(0.25, 0.8, 1.0), spectrum, 0.6) : tint;
    float g = exp(-max(sd, 0.0) / ((style == 2 ? 9.0 : 7.0) * u.scale)) * ((style == 1 ? 0.04 : 0.07) + lvl * 0.5);
    float4 outside = float4(glowTint * g, g * 0.85) * step(0.0, sd);
    if (sd >= 1.0 * u.scale) { return outside; }

    float2 uv = (px - (c - size * 0.5)) / (2.0 * r);
    float3 col;
    float bodyAlpha = 0.97;

    if (style == 3) {
        // PLAIN (animated graphics off): a quiet dark bar and one small dot that breathes with the voice.
        col = mix(float3(0.06, 0.065, 0.075), float3(0.10, 0.105, 0.115), vy);
        float2 dc = float2(m + r, c.y);
        float dr = r * (0.20 + lvl * 0.14);
        float dd = length(px - dc);
        float3 dotCol = u.phase > 3.5 ? amber : float3(0.36, 0.86, 0.9);
        col = mix(col, dotCol, smoothstep(dr + 0.8 * u.scale, dr - 0.4 * u.scale, dd));
        col += dotCol * exp(-max(dd - dr, 0.0) / (3.0 * u.scale)) * (0.15 + lvl * 0.4);
        tint = dotCol;
        glowTint = dotCol * 0.4;
    } else if (style == 1) {
        // ON AIR, tape edition: brushed charcoal, two reel-to-reel spools that spin up with the voice and
        // coast when it stops, tape running between them past a head, a red ON AIR lamp, a brass edge.
        float grain = vnoise(float2(px.x * 0.004 / u.scale, px.y * 0.9 / u.scale)) * 0.5 + vnoise(float2(px.x * 0.02 / u.scale, px.y * 2.1 / u.scale)) * 0.5;
        col = mix(float3(0.07, 0.065, 0.06), float3(0.16, 0.15, 0.14), vy) * (0.85 + grain * 0.3);
        col *= 0.75 + 0.25 * smoothstep(0.0, 0.35, min(xn, 1.0 - xn));
        float R = r * 0.66;
        float2 c1 = float2(m + r * 0.95, c.y + r * 0.04), c2 = float2(m + r * 2.75, c.y + r * 0.04);
        // tape: runs along the bottom of both reels, over the head in between
        float tapeY = c.y - R * 0.86;
        float onTape = step(c1.x, px.x) * step(px.x, c2.x) * smoothstep(1.2 * u.scale, 0.2 * u.scale, abs(px.y - tapeY));
        col = mix(col, float3(0.24, 0.15, 0.08), onTape);
        float2 headC = float2((c1.x + c2.x) * 0.5, tapeY - 2.2 * u.scale);
        float2 hq = abs(px - headC) - float2(4.0 * u.scale, 2.0 * u.scale);
        col = mix(col, float3(0.62, 0.6, 0.56), step(max(hq.x, hq.y), 0.0));
        for (int k = 0; k < 2; k++) {
            float2 rc = k == 0 ? c1 : c2;
            float pack = k == 0 ? 0.82 : 0.58;                               // supply reel fuller than take-up
            float2 d = px - rc;
            float rr = length(d) / R;
            if (rr < 1.02) {
                float ang = atan2(d.y, d.x) - u.reel * (k == 0 ? 1.0 : 1.35);
                float3 flange = mix(float3(0.42, 0.42, 0.44), float3(0.80, 0.80, 0.82), 0.5 + 0.5 * cos(ang * 2.0 + 0.8));
                flange *= 0.85 + 0.15 * vnoise(float2(rr * 40.0, ang * 3.0));
                float3 reelCol = flange;
                // three windows in the flange show the tape pack (or darkness) beneath
                float win = fract(ang * 3.0 / 6.28318 + 1.0);
                bool inWindow = rr > 0.32 && rr < 0.86 && win > 0.12 && win < 0.45;
                if (inWindow) reelCol = rr < pack ? float3(0.30, 0.19, 0.10) * (0.8 + 0.2 * sin(rr * 90.0)) : float3(0.03, 0.03, 0.035);
                if (rr < 0.24) {                                             // hub with three spokes
                    float spoke = smoothstep(0.18, 0.05, abs(fract(ang * 3.0 / 6.28318 + 1.0) - 0.5) * 2.0);
                    reelCol = mix(float3(0.12, 0.12, 0.13), float3(0.55, 0.55, 0.57), spoke * step(0.09, rr));
                }
                reelCol += 0.25 * exp(-abs(rr - 1.0) * 30.0);                // bright rim
                col = mix(col, reelCol, smoothstep(1.02, 0.97, rr));
            }
        }
        // ON AIR lamp between the reels, top
        float2 lp = float2((c1.x + c2.x) * 0.5, c.y + r * 0.55);
        float lampOn = u.phase < 0.5 ? 1.0 : 0.15;
        float ld = length(px - lp);
        col = mix(col, float3(1.0, 0.18, 0.12) * (0.4 + lampOn), smoothstep(2.6 * u.scale, 1.6 * u.scale, ld));
        col += float3(1.0, 0.2, 0.1) * exp(-ld / (5.0 * u.scale)) * 0.4 * lampOn;
        tint = u.phase > 3.5 ? amber : float3(0.85, 0.62, 0.32);
        glowTint = tint * 0.6;
        bodyAlpha = 0.98;
    } else if (style == 2) {
        // NEO NOIR (Blade Runner): dark violet, CRT scanlines, rain, a flickering neon tube edge,
        // and a segmented LED level meter in the left zone.
        float3 magenta = float3(1.0, 0.17, 0.84), cyan = float3(0.0, 0.9, 1.0), amberLED = float3(1.0, 0.69, 0.0);
        col = mix(float3(0.035, 0.016, 0.07), float3(0.10, 0.04, 0.17), vy);
        col += magenta * 0.05 * exp(-pow((vy - 0.18) / 0.10, 2.0));             // low horizon haze
        // rain: thin falling streaks in fixed columns
        float cw = 5.0 * u.scale;
        float cid = floor(px.x / cw);
        float fall = fract(vy * 1.6 + t * (0.5 + u.motion) * (0.9 + hash11(cid) * 0.8) + hash11(cid + 3.0));
        float streak = smoothstep(0.0, 0.25, fall) * smoothstep(0.35, 0.25, fall) * step(0.72, hash11(cid + 11.0));
        float inCol = 1.0 - smoothstep(0.0, 0.6 * u.scale, abs(fract(px.x / cw) * cw - cw * 0.5));
        col += cyan * streak * inCol * 0.10;
        // LED meter: 7 columns x 5 segments
        float mw = r * 3.2, mx = (px.x - m - r * 0.55) / mw;
        if (mx > 0.0 && mx < 1.0) {
            float colIdx = floor(mx * 7.0), cx = fract(mx * 7.0);
            float segY = ((px.y - (c.y - r * 0.62)) / (r * 1.24));
            if (segY > 0.0 && segY < 1.0 && cx > 0.18 && cx < 0.82) {
                float seg = floor(segY * 5.0), sy = fract(segY * 5.0);
                float jitter = 1.0 - u.motion * 0.55 * hash11(colIdx * 13.1 + floor(t * (5.0 + 10.0 * u.motion)));
                float shape = 0.75 + 0.25 * sin(colIdx * 0.9 + 1.2);
                float h = clamp(lvl * (0.9 + 0.7 * u.motion) * jitter * shape, 0.06, 1.0);
                if (sy > 0.2 && sy < 0.85) {
                    float on = step(seg / 5.0, h - 0.001);
                    float3 led = mix(amberLED, magenta, seg / 4.0);
                    col = mix(col, led * (on > 0.5 ? 1.25 : 0.12), on > 0.5 ? 0.95 : 0.6);
                }
            }
        }
        // CRT scanlines + a faint rolling band
        col *= 0.82 + 0.18 * sin(px.y * 3.14159 / (1.5 * u.scale));
        col *= 1.0 + 0.06 * exp(-pow(fract(vy - t * (0.05 + 0.2 * u.motion)) - 0.5, 2.0) / 0.01);
        float flicker = 1.0 - 0.35 * step(0.965, hash11(floor(t * 14.0)));
        float3 tube = mix(magenta, cyan, xn);
        tint = u.phase > 3.5 ? amber : tube;
        glowTint = tint * flicker;
        bodyAlpha = 0.97;
    } else {
        // DEEP WATER: near-black navy, big soft veils of
        // light, fine marine snow. Speaking makes the water flow faster, sends ripples out from the orb and
        // stirs the specks; a pause lets it settle. The orange lives in the orb's core.
        float3 deep = float3(0.020, 0.039, 0.094), mid = float3(0.039, 0.106, 0.227);
        col = mix(deep, mid, pow(vy, 0.8));
        col += float3(0.114, 0.306, 0.847) * 0.10 * pow(vy, 3.0);
        float ct = u.flow * 0.08;
        float2 cuv = float2(xn * size.x / (2.0 * r) * 0.35, vy * 0.35);
        float2 warp = float2(vnoise(cuv * 1.3 + ct), vnoise(cuv * 1.3 - ct * 1.3));
        float veil = 1.0 - abs(vnoise(cuv * 1.3 + warp * (1.4 + lvl * 0.8 * u.motion) + ct * 0.5) * 2.0 - 1.0);
        veil = pow(veil, 3.0) * 0.8 + pow(1.0 - abs(vnoise(cuv * 2.6 + 4.7 + warp) * 2.0 - 1.0), 4.0) * 0.4;
        col += float3(0.25, 0.55, 1.0) * veil * mix(0.3, 1.0, vy) * (0.2 + lvl * (0.1 + 0.3 * u.motion));
        // ripples from the orb while speaking
        float2 origin = float2(m + r, c.y);
        float dist = length((px - origin) * float2(1.0, 1.6));
        for (int k = 0; k < 3; k++) {
            float ph = fract(u.flow * 0.45 + float(k) / 3.0);
            float ring = exp(-pow((dist - ph * size.x * 0.55) / (5.0 * u.scale), 2.0)) * (1.0 - ph);
            col += float3(0.35, 0.7, 1.0) * ring * lvl * 0.5 * u.motion * u.motion;   // ripples only when lively
        }
        // marine snow, drifting down; the voice pushes it sideways
        for (int i = 0; i < 16; i++) {
            float fi = float(i);
            float sx = m + fract(hash11(fi + 1.7) + u.flow * 0.012 * (0.5 + hash11(fi))) * size.x + sin(t * 0.4 + fi * 1.9) * 3.0 * u.scale;
            float sy = (c.y + r) - fract(hash11(fi + 5.3) + t * (0.015 + hash11(fi + 2.2) * 0.02)) * (2.0 * r);
            float sr = (0.5 + hash11(fi + 8.1) * 0.7 + lvl * 0.4 * u.motion) * u.scale;
            col += float3(0.7, 0.85, 1.0) * smoothstep(sr * 1.8, 0.0, length(px - float2(sx, sy))) * (0.18 + hash11(fi) * 0.2 + lvl * 0.15 * u.motion);
        }
        tint = u.phase > 3.5 ? amber : float3(0.337, 0.761, 1.0);
        glowTint = tint;
    }

    // Glass orb in the left cap (deep water + glass).
    float2 oc = vertical ? float2(c.x, u.res.y - m - r) : float2(m + r, c.y);
    if (u.orb > 0.5 && style == 0) {
        float orbR = r * 0.50 * (1.0 + lvl * (style == 0 ? 0.12 : 0.30) + 0.02 * sin(t * 1.4));
        float2 od = (px - oc) / orbR;
        float od2 = dot(od, od);
        if (od2 < 1.0) {
            // A bubble of the same water: see-through navy, the veils magnified inside, a soft rim,
            // a small highlight, and the orange core that brightens with the voice.
            float z = sqrt(1.0 - od2);
            float3 n = float3(od.x, od.y, z);
            float3 L = normalize(float3(-0.45, 0.65, 0.65));
            float fres = pow(1.0 - z, 2.4);
            float2 inside = (oc + od * orbR * 0.55 - (c - size * 0.5)) / (2.0 * r) * 0.35;
            float2 w2 = float2(vnoise(inside * 1.3 + u.flow * 0.08), vnoise(inside * 1.3 - u.flow * 0.1));
            float v2 = pow(1.0 - abs(vnoise(inside * 1.3 + w2 * 1.6) * 2.0 - 1.0), 3.0);
            float3 body = mix(float3(0.03, 0.08, 0.18), float3(0.06, 0.16, 0.34), 0.5 + od.y * 0.5);
            body += float3(0.3, 0.6, 1.0) * v2 * (0.35 + lvl * 0.4);
            body += float3(0.45, 0.75, 1.0) * fres * 0.55;
            float spec = pow(max(dot(reflect(-L, n), float3(0, 0, 1)), 0.0), 40.0);
            body += spec * 0.55;
            body += float3(0.976, 0.451, 0.086) * smoothstep(0.55, 0.0, sqrt(od2)) * (0.05 + lvl * 0.75);  // small ember at the heart
            float k = smoothstep(1.0, 0.9, od2);
            col = mix(col, body, k);
        } else {
            col += tint * exp(-(sqrt(od2) - 1.0) * 2.6) * (0.10 + lvl * 0.55);
        }
    }

    // Transcribing: a light sweep across the glass.
    if (u.phase > 0.5 && u.phase < 1.5) {
        float x = fract(u.phaseT * 0.75) * 1.5 - 0.25;
        col += glowTint * exp(-pow((xn - x) * 7.0, 2.0)) * 0.30;
    }
    // Pasted: a ripple rings out from the left.
    if (u.phase > 1.5 && u.phase < 2.5) {
        float k = clamp(u.phaseT / 0.9, 0.0, 1.0);
        col += glowTint * exp(-pow((length(px - oc) - k * size.x) / (7.0 * u.scale), 2.0)) * (1.0 - k) * 0.9;
    }

    // Rim light, stronger on top; glass gets a crisper, whiter rim.
    float edge = exp(-abs(sd) / (1.1 * u.scale));
    if (style == 2) { col += glowTint * edge * 1.1; } else if (style == 1) { col += float3(0.78, 0.6, 0.32) * edge * (0.35 + 0.35 * smoothstep(0.3, 1.0, vy)); } else
    col += edge * (style == 1 ? (0.18 + 0.35 * smoothstep(0.3, 1.0, vy)) : (0.06 + 0.22 * smoothstep(0.35, 1.0, vy)));
    col += (style == 1 ? 0.06 : 0.035) * smoothstep(0.55, 1.0, vy);

    float a = clamp(0.5 - sd / u.scale, 0.0, 1.0);
    float ia = a * min(bodyAlpha + edge * 0.3, 0.97);
    float4 inside = float4(col * a, ia);
    return inside + outside * (1.0 - inside.a);
}
"""

struct GlassUniforms {
    var res: SIMD2<Float>
    var margin: Float
    var scale: Float
    var time: Float
    var level: Float
    var phase: Float
    var phaseT: Float
    var orb: Float = 1
    var style: Float = 0
    /// Time that runs faster while you speak, so the water flows with the voice and never jumps.
    var flow: Float = 0
    /// Deep Water's Calm↔Lively setting, 0...1.
    var motion: Float = 0.35
    /// Tape-reel rotation for On Air: speeds up with the voice, coasts down on a pause.
    var reel: Float = 0
    var pad3: Float = 0
}

final class GlassRenderer: NSObject, MTKViewDelegate {
    static let device = MTLCreateSystemDefaultDevice()
    private static var pipeline: MTLRenderPipelineState? = {
        guard let device else { return nil }
        do {
            let lib = try device.makeLibrary(source: shaderSource, options: nil)
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: "v_main")
            d.fragmentFunction = lib.makeFunction(name: "f_main")
            d.colorAttachments[0].pixelFormat = .bgra8Unorm
            return try device.makeRenderPipelineState(descriptor: d)
        } catch { debugLog("shader compile failed: \(error)"); return nil }
    }()
    private let queue = GlassRenderer.device?.makeCommandQueue()
    private let start = CACurrentMediaTime()
    private var smoothed: Float = 0
    private var flow: Float = 0
    private var reelVel: Float = 0
    private var reelAngle: Float = 0
    private var lastFrame = CACurrentMediaTime()
    private var phaseStart = CACurrentMediaTime()
    private var lastPhase: Float = -1

    var margin: CGFloat = 18
    var orb = true
    /// The edge tab always uses deep water; the pill follows Settings.
    var styleOverride: Float?
    var level: () -> Float = { 0 }
    var phase: () -> Float = { 0 }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pipeline = Self.pipeline, let queue, let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable, let cb = queue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        let target = level()
        let calm = Prefs.shared.showGraphics && (styleOverride ?? Float(Prefs.shared.pillStyle.index)) == 0
        // Deep water eases toward the voice; the other styles snap to it.
        smoothed += (target - smoothed) * (target > smoothed ? (calm ? 0.16 : 0.35) : (calm ? 0.05 : 0.07))
        let now = CACurrentMediaTime()
        let motion = Float(Prefs.shared.waterMotion)
        let dt = Float(min(now - lastFrame, 0.1))
        flow += dt * (1 + smoothed * 4 * motion)
        // Reels have weight: quick to spin up, slow to coast down.
        reelVel += (target - reelVel) * (target > reelVel ? 0.10 + 0.1 * motion : 0.02)
        reelAngle += dt * (0.6 + reelVel * 7 * (0.35 + motion))
        lastFrame = now
        let ph = phase()
        if ph != lastPhase { lastPhase = ph; phaseStart = CACurrentMediaTime() }
        let scale = Float(view.window?.backingScaleFactor ?? 2)
        var u = GlassUniforms(res: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
                              margin: Float(margin) * scale, scale: scale,
                              time: Float(CACurrentMediaTime() - start), level: smoothed,
                              phase: ph, phaseT: Float(CACurrentMediaTime() - phaseStart), orb: orb ? 1 : 0,
                              style: styleOverride ?? (Prefs.shared.showGraphics ? Float(Prefs.shared.pillStyle.index) : 3), flow: flow, motion: motion, reel: reelAngle)
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&u, length: MemoryLayout<GlassUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }
}

struct GlassSurface: NSViewRepresentable {
    let margin: CGFloat
    var orb = true
    var style: Float? = nil
    let level: () -> Float
    let phase: () -> Float

    func makeCoordinator() -> GlassRenderer { GlassRenderer() }

    func makeNSView(context: Context) -> MTKView {
        let v = MTKView(frame: .zero, device: GlassRenderer.device)
        v.colorPixelFormat = .bgra8Unorm
        v.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        v.layer?.isOpaque = false
        v.preferredFramesPerSecond = 60
        v.delegate = context.coordinator
        update(context.coordinator)
        return v
    }

    func updateNSView(_ v: MTKView, context: Context) { update(context.coordinator) }

    private func update(_ r: GlassRenderer) {
        r.margin = margin; r.orb = orb; r.styleOverride = style; r.level = level; r.phase = phase
    }
}

/// Real behind-window blur for the Liquid Glass pill (SwiftUI materials only blur this window's own content).
struct BackdropBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.wantsLayer = true
        v.layer?.cornerCurve = .continuous
        v.layer?.masksToBounds = true
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.layer?.cornerRadius = v.bounds.height / 2
    }
}
