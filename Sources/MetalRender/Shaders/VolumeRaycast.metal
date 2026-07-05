#include <metal_stdlib>
using namespace metal;

// Must match `RaycastUniforms` in Uniforms.swift (byte-for-byte).
struct RaycastUniforms {
    float4 camPos;      // eye in physical (mm) space, volume centered at origin
    float4 camForward;  // unit
    float4 camRight;    // unit
    float4 camUp;       // unit
    float4 boxHalf;     // physical half-extents (mm)
    float4 clipMin;     // normalized texcoord clip box (xyz)
    float4 clipMax;
    float2 tanHalfFov;  // (tanHalfFovY * aspect, tanHalfFovY)
    float slope;
    float intercept;
    float winCenter;    // MIP windowing (HU)
    float winWidth;
    float stepMM;
    float lutMinHU;     // TF LUT maps [lutMinHU, lutMaxHU] -> [0,1]
    float lutMaxHU;
    uint  mode;         // 0 MIP · 1 MinIP · 2 X-Ray · 3 Volume(TF) · 4 Surface
    uint  lightEnabled;
    float isoValue;     // HU threshold for surface mode
};

struct VOut {
    float4 position [[position]];
    float2 ndc;     // [-1,1]
};

constant float2 kQuad[4] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1) };

vertex VOut vertex_raycast(uint vid [[vertex_id]]) {
    VOut o;
    o.position = float4(kQuad[vid], 0.0, 1.0);
    o.ndc = kQuad[vid];
    return o;
}

fragment float4 fragment_raycast(VOut in [[stage_in]],
                                 constant RaycastUniforms& u [[buffer(0)]],
                                 texture3d<float> vol [[texture(0)]],
                                 texture1d<float> lut [[texture(1)]],
                                 sampler samp [[sampler(0)]]) {
    float3 ro = u.camPos.xyz;
    float3 rd = normalize(u.camForward.xyz
                          + in.ndc.x * u.tanHalfFov.x * u.camRight.xyz
                          + in.ndc.y * u.tanHalfFov.y * u.camUp.xyz);

    // Ray vs axis-aligned box [-boxHalf, +boxHalf].
    float3 invD = 1.0 / rd;
    float3 t0 = (-u.boxHalf.xyz - ro) * invD;
    float3 t1 = ( u.boxHalf.xyz - ro) * invD;
    float3 tmin = min(t0, t1);
    float3 tmax = max(t0, t1);
    float tNear = max(max(tmin.x, tmin.y), tmin.z);
    float tFar  = min(min(tmax.x, tmax.y), tmax.z);
    if (tNear > tFar || tFar < 0.0) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }
    tNear = max(tNear, 0.0);

    float3 size = 2.0 * u.boxHalf.xyz;
    float step = max(u.stepMM, 0.01);
    float3 g3 = 1.0 / float3(vol.get_width(), vol.get_height(), vol.get_depth());
    // Fixed world-space key light (front-left-above) so highlights sweep across the
    // form as the camera turns — rotation reads like MIP. Ambient terms keep
    // back-facing angles from going fully black.
    float3 lightDir = normalize(float3(-0.3, -0.8, 0.5));
    float lo = u.winCenter - u.winWidth * 0.5;

    // --- Projection modes: MIP / MinIP / X-Ray (average) ---
    if (u.mode <= 2u) {
        float acc = (u.mode == 1u) ? 1e6 : (u.mode == 0u ? -1e6 : 0.0);
        float n = 0.0;
        for (float t = tNear; t < tFar; t += step) {
            float3 pos = ro + rd * t;
            float3 tc = (pos + u.boxHalf.xyz) / size;
            if (any(tc < u.clipMin.xyz) || any(tc > u.clipMax.xyz)) continue;
            float hu = (vol.sample(samp, tc).r * 32767.0) * u.slope + u.intercept;
            if (u.mode == 0u) acc = max(acc, hu);
            else if (u.mode == 1u) acc = min(acc, hu);
            else { acc += hu; n += 1.0; }
        }
        if (u.mode == 2u && n > 0.0) acc /= n;
        float g = clamp((acc - lo) / max(u.winWidth, 1.0), 0.0, 1.0);
        return float4(g, g, g, 1.0);
    }

    // --- Iso-surface: first hit above threshold, gradient-shaded ---
    if (u.mode == 4u) {
        for (float t = tNear; t < tFar; t += step) {
            float3 pos = ro + rd * t;
            float3 tc = (pos + u.boxHalf.xyz) / size;
            if (any(tc < u.clipMin.xyz) || any(tc > u.clipMax.xyz)) continue;
            float hu = (vol.sample(samp, tc).r * 32767.0) * u.slope + u.intercept;
            if (hu >= u.isoValue) {
                float gx = (vol.sample(samp, tc + float3(g3.x,0,0)).r * 32767.0) - (vol.sample(samp, tc - float3(g3.x,0,0)).r * 32767.0);
                float gy = (vol.sample(samp, tc + float3(0,g3.y,0)).r * 32767.0) - (vol.sample(samp, tc - float3(0,g3.y,0)).r * 32767.0);
                float gz = (vol.sample(samp, tc + float3(0,0,g3.z)).r * 32767.0) - (vol.sample(samp, tc - float3(0,0,g3.z)).r * 32767.0);
                float3 nrm = float3(gx,gy,gz);
                float gl = length(nrm);
                float3 base = float3(0.92, 0.88, 0.80);
                if (gl > 1e-4) {
                    float3 nn = -nrm / gl;
                    float diff = max(dot(nn, lightDir), 0.0);
                    float spec = pow(max(dot(reflect(-lightDir, nn), -rd), 0.0), 24.0);
                    return float4(base * (0.30 + 0.70 * diff) + spec * 0.4, 1.0);
                }
                return float4(base * 0.5, 1.0);
            }
        }
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    // --- Volume: front-to-back transfer-function compositing with shading ---
    float3 accColor = float3(0.0);
    float accAlpha = 0.0;
    float range = max(u.lutMaxHU - u.lutMinHU, 1.0);
    for (float t = tNear; t < tFar && accAlpha < 0.99; t += step) {
        float3 pos = ro + rd * t;
        float3 tc = (pos + u.boxHalf.xyz) / size;
        if (any(tc < u.clipMin.xyz) || any(tc > u.clipMax.xyz)) continue;
        float hu = (vol.sample(samp, tc).r * 32767.0) * u.slope + u.intercept;
        float lutU = clamp((hu - u.lutMinHU) / range, 0.0, 1.0);
        float4 c = lut.sample(samp, lutU);
        float a = c.a;
        if (a > 0.001) {
            float3 rgb = c.rgb;
            if (u.lightEnabled != 0u) {
                float gx = (vol.sample(samp, tc + float3(g3.x,0,0)).r * 32767.0) - (vol.sample(samp, tc - float3(g3.x,0,0)).r * 32767.0);
                float gy = (vol.sample(samp, tc + float3(0,g3.y,0)).r * 32767.0) - (vol.sample(samp, tc - float3(0,g3.y,0)).r * 32767.0);
                float gz = (vol.sample(samp, tc + float3(0,0,g3.z)).r * 32767.0) - (vol.sample(samp, tc - float3(0,0,g3.z)).r * 32767.0);
                float3 grad = float3(gx, gy, gz);
                float gl = length(grad);
                if (gl > 1e-4) {
                    float3 nn = -grad / gl;
                    float diff = max(dot(nn, lightDir), 0.0);
                    rgb *= (0.35 + 0.75 * diff);
                }
            }
            a = 1.0 - pow(1.0 - clamp(a, 0.0, 1.0), step);
            accColor += (1.0 - accAlpha) * a * rgb;
            accAlpha += (1.0 - accAlpha) * a;
        }
    }
    return float4(accColor, 1.0);
}
