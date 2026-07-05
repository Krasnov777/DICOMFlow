#include <metal_stdlib>
using namespace metal;

// Must match `MPRUniforms` in Uniforms.swift (byte-for-byte).
struct MPRUniforms {
    float4 originTC;   // plane origin in normalized texture coords (xyz)
    float4 uAxisTC;    // plane horizontal axis (xyz)
    float4 vAxisTC;    // plane vertical axis (xyz)
    float2 fitScale;   // clip-space scale to letterbox to physical aspect
    float slope;
    float intercept;
    float winCenter;   // window/level in HU (modality units)
    float winWidth;
    float zoom;
    uint invert;
    float2 pan;
    uint quarter;     // 90° turns (0…3)
    uint flipMask;    // bit0 = flip X, bit1 = flip Y
};

struct VOut {
    float4 position [[position]];
    float2 uv;
};

constant float2 kQuad[4]  = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1) };
// uv with v flipped so uv.y==0 maps to the top of the screen (row 0).
constant float2 kUV[4]    = { float2(0,1),   float2(1,1),  float2(0,0),  float2(1,0) };

vertex VOut vertex_mpr(uint vid [[vertex_id]],
                       constant MPRUniforms& u [[buffer(0)]]) {
    VOut o;
    o.position = float4(kQuad[vid] * u.fitScale, 0.0, 1.0);
    o.uv = kUV[vid];
    return o;
}

fragment float4 fragment_mpr(VOut in [[stage_in]],
                             constant MPRUniforms& u [[buffer(0)]],
                             texture3d<float> vol [[texture(0)]],
                             sampler samp [[sampler(0)]]) {
    // Apply zoom (about center) and pan in plane space.
    float2 uv = (in.uv - 0.5) / max(u.zoom, 0.01) + 0.5 + u.pan;
    // Flip, then rotate by 90° steps about the center.
    if (u.flipMask & 1u) uv.x = 1.0 - uv.x;
    if (u.flipMask & 2u) uv.y = 1.0 - uv.y;
    float2 c = uv - 0.5;
    for (uint i = 0u; i < u.quarter; i++) c = float2(-c.y, c.x);
    uv = c + 0.5;
    float3 tc = u.originTC.xyz + uv.x * u.uAxisTC.xyz + uv.y * u.vAxisTC.xyz;
    if (any(tc < 0.0) || any(tc > 1.0)) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }
    float stored = vol.sample(samp, tc).r * 32767.0;   // r16Snorm → stored value
    float hu = stored * u.slope + u.intercept;
    float lo = u.winCenter - u.winWidth * 0.5;
    float g = clamp((hu - lo) / max(u.winWidth, 1.0), 0.0, 1.0);
    if (u.invert != 0u) g = 1.0 - g;
    return float4(g, g, g, 1.0);
}
