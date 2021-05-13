
// XE Mod Water.fx
// MGE XE 0.12.1
// Water plane rendering. Can be used as a core mod.


//------------------------------------------------------------
// Samplers, clamping mode

sampler sampReflect = sampler_state { texture = <tex0>; minfilter = linear; magfilter = linear; mipfilter = none; addressu = clamp; addressv = clamp; };
sampler sampRefract = sampler_state { texture = <tex2>; minfilter = linear; magfilter = linear; mipfilter = none; addressu = clamp; addressv = clamp; };

//------------------------------------------------------------
// Water constants

static const float kDistantZBias = 5e-6;
static const float sunlightFactor = 1 - pow(1 - sunVis, 2);
static const float3 sunColAdjusted = sunCol * sunlightFactor;
static const float3 depthBaseColor = sunColAdjusted * float3(0.03, 0.04, 0.05) + (2 * skyCol + fogColFar) * float3(0.075, 0.08, 0.085);
static const float windFactor = (length(windVec) + 1.5) / 140;
static const float waterLevel = world[3][2];
static const float causticsStrength = 0.05 * alphaRef * saturate(0.75 * sunlightFactor + 0.35 * length(fogColFar));

shared texture tex4, tex5;
shared float3 rippleOrigin;
shared float waveHeight;

sampler sampRain = sampler_state { texture = <tex4>; minfilter = linear; magfilter = linear; mipfilter = linear; addressu = wrap; addressv = wrap; };
sampler sampWave = sampler_state { texture = <tex5>; minfilter = linear; magfilter = linear; mipfilter = linear; bordercolor = 0; addressu = border; addressv = border; };

static const float waveTexResolution = 512;
static const float waveTexWorldSize = waveTexResolution * 2.5;
static const float waveTexRcpRes = 1.0 / waveTexResolution;
static const float playerWaveSize = 12.0 / waveTexWorldSize; // 12 world units radius

//------------------------------------------------------------
// Static functions

float3 getFinalWaterNormal(float2 texcoord1, float2 texcoord2, float dist, float2 vertXY) : NORMAL
{
    // Calculate the W texture coordinate based on the time that has passed
    float t = 0.4 * time;
    float3 w1 = float3(texcoord1, t);
    float3 w2 = float3(texcoord2, t);
    
    // Blend together the normals from different sized areas of the same texture
    float2 far_normal = tex3D(sampWater3d, w1).rg;
    float2 close_normal = tex3D(sampWater3d, w2).rg;

#ifdef DYNAMIC_RIPPLES
    // Blend normals from rain and player ripples
    close_normal.rg += tex2Dlod(sampRain, float4(texcoord2, 0, 0)).ba;
    close_normal.rg += tex2Dlod(sampWave, float4((vertXY - rippleOrigin) / waveTexWorldSize, 0, 0)).ba;
#endif

    float2 normal_R = 2 * lerp(close_normal, far_normal, saturate(dist / 8000)) - 1;
    return normalize(float3(normal_R, 1));
}

#ifndef FILTER_WATER_REFLECTION

float3 getProjectedReflection(float4 tex)
{
    return tex2Dproj(sampReflect, tex).rgb;
}

#else

float3 getProjectedReflection(float4 tex)
{
    float4 radius = 0.006 * saturate(0.11 + tex.w/6000) * tex.w * float4(1, rcpRes.y/rcpRes.x, 0, 0);
    
    float3 reflected = tex2Dproj(sampReflect, tex);
    reflected += tex2Dproj(sampReflect, tex + radius*float4(0.60, 0.10, 0, 0));
    reflected += tex2Dproj(sampReflect, tex + radius*float4(0.30, -0.21, 0, 0));
    reflected += tex2Dproj(sampReflect, tex + radius*float4(0.96, -0.03, 0, 0));
    reflected += tex2Dproj(sampReflect, tex + radius*float4(-0.40, 0.06, 0, 0));
    reflected += tex2Dproj(sampReflect, tex + radius*float4(-0.70, 0.18, 0, 0));
    reflected /= 6.0;
    
    return reflected.rgb;
}

#endif

//------------------------------------------------------------
// Water shader

struct WaterVertOut
{
    float4 position : POSITION;
    float4 pos : TEXCOORD0;
    float4 texcoords : TEXCOORD1;
    float4 screenpos : TEXCOORD2;
#ifdef DYNAMIC_RIPPLES
    float4 screenposclamp : TEXCOORD3;
#endif
};

#ifndef DYNAMIC_RIPPLES

WaterVertOut WaterVS (in float4 pos : POSITION)
{
    WaterVertOut OUT;

    // Add z bias to avoid fighting with MW ripples quads
    OUT.pos = mul(pos, world);
    OUT.pos.z -= 0.1;

    // Calculate various texture coordinates
    OUT.texcoords.xy = OUT.pos.xy / 3900;
    OUT.texcoords.zw = OUT.pos.xy / 527;

    OUT.position = mul(OUT.pos, view);
    OUT.position = mul(OUT.position, proj);

    // Match bias in distant land projection
    OUT.position.z *= 1.0 + kDistantZBias * step(nearViewRange, OUT.position.w);
    
    OUT.screenpos = float4(0.5 * (1 + rcpRes) * OUT.position.w + float2(0.5, -0.5) * OUT.position.xy, OUT.position.zw);

    return OUT;
}

#else

WaterVertOut WaterVS (in float4 pos : POSITION)
{
    WaterVertOut OUT;
    
    // Move to world space
    OUT.pos = mul(pos, world);

    // Calculate various texture coordinates
    OUT.texcoords.xy = OUT.pos.xy / 3900;
    OUT.texcoords.zw = OUT.pos.xy / 527;

    // Apply vertex displacement
    float t = 0.4 * time;
    float height = tex3Dlod(sampWater3d, float4(OUT.pos.xy / 1104, t, 0)).a;
    float height2 = tex3Dlod(sampWater3d, float4(OUT.pos.xy / 3900, t, 0)).a;
    float dist = length(eyePos.xyz - OUT.pos.xyz);

    float addheight = waveHeight * (lerp(height, height2, saturate(dist/8000)) - 0.5) * saturate(1 - dist/6400) * saturate(dist/200);
    OUT.pos.z += addheight;

    // Match bias in distant land projection
    OUT.position = mul(OUT.pos, view);
    OUT.position = mul(OUT.position, proj);
    OUT.position.z *= 1.0 + kDistantZBias * step(nearViewRange, OUT.position.w);
    OUT.screenpos = float4(0.5 * (1 + rcpRes) * OUT.position.w + float2(0.5, -0.5) * OUT.position.xy, OUT.position.zw);

    // Clamp reflection point to be above surface
    float4 clampedPos = OUT.pos - float4(0, 0, abs(addheight), 0);
    clampedPos = mul(clampedPos, view);
    clampedPos = mul(clampedPos, proj);
    clampedPos.z *= 1.0 + kDistantZBias * step(nearViewRange, clampedPos.w);
    OUT.screenposclamp = float4(0.5 * (1 + rcpRes) * clampedPos.w + float2(0.5, -0.5) * clampedPos.xy, clampedPos.zw);
    
    return OUT;
}
#endif

float4 WaterPS(in WaterVertOut IN): COLOR0
{
    // Calculate eye vector
    float3 EyeVec = IN.pos.xyz - eyePos.xyz;
    float dist = length(EyeVec);
    EyeVec /= dist;

    // Define fog
    float4 fog = fogColourWater(EyeVec, dist);
    float3 depthColor = fogApply(depthBaseColor, fog);
    
    // Calculate water normal
    float3 normal = getFinalWaterNormal(IN.texcoords.xy, IN.texcoords.zw, dist, IN.pos.xy);

    // Reflection/refraction pixel distortion factor, wind strength increases distortion
    float2 reffactor = (windFactor * dist + 0.1) * normal.xy;

    // Distort refraction dependent on depth
    float4 newscrpos = IN.screenpos + float4(reffactor.yx, 0, 0);
    float depth = max(0, tex2Dproj(sampDepth, newscrpos).r - IN.screenpos.w);

    // Refraction
    float3 refracted = depthColor;
    float shorefactor = 0;

    // Avoid sampling deep water
    if(depth < 4000)
    {
        // Sample refraction texture
        newscrpos = IN.screenpos + saturate(depth / 100) * float4(reffactor.yx, 0, 0);
        refracted = tex2Dproj(sampRefract, newscrpos).rgb;

        // Get distorted depth
        depth = max(0, tex2Dproj(sampDepth, newscrpos).r - IN.screenpos.w);
        depth /= dot(EyeVec, float3(view[0][2], view[1][2], view[2][2]));

        // Small scale shoreline animation
        depth += 300 * (0.95 - normal.z);

        float depthscale = saturate(exp(-depth / 800));
        shorefactor = pow(depthscale, 90);

        // Make transition between actual refraction image and depth color depending on water depth
        refracted = lerp(depthColor, refracted, 0.8 * depthscale + 0.2 * shorefactor);
    }
    
    // Sample reflection texture
#ifndef DYNAMIC_RIPPLES
    float4 screenpos = IN.screenpos;
#else
    float4 screenpos = IN.screenposclamp;
#endif
    float3 reflected = getProjectedReflection(screenpos - float4(2.1 * reffactor.x, -abs(reffactor.y), 0, 0));

    // Fade reflection into an inscatter dominated horizon
    reflected = lerp(fog.rgb, reflected, fog.a);

    // Smooth out high frequencies at a distance
    float3 adjustnormal = lerp(float3(0, 0, 0.1), normal, pow(saturate(1.05 * fog.a), 2));
    adjustnormal = lerp(adjustnormal, float3(0, 0, 1.0), (1 + EyeVec.z) * (1 - saturate(1 / (dist / 1000 + 1))));

    // Fresnel equation determines reflection/refraction
    float fresnel = dot(-EyeVec, adjustnormal);
    fresnel = 0.02 + pow(saturate(0.9988 - 0.28 * fresnel), 16);
    float3 result = lerp(refracted, reflected, fresnel);
    
    // Specular lighting
    // This should use Blinn-Phong, but it doesn't work so well for area lights like the sun
    // Instead multiply and saturate to widen a Phong specular lobe which better simulates an area light
    float vdotr = dot(-EyeVec, reflect(-sunPos, normal));
    vdotr = saturate(1.0025 * vdotr);
    float3 spec = sunColAdjusted * (pow(vdotr, 170) + 0.07 * pow(vdotr, 4));
    result += spec * fog.a;

    // Smooth transition at shore line
    result = lerp(result, refracted, shorefactor * fog.a);
    
    // Note that both refraction and reflection textures have fog applied already
    
    return float4(result, 1);
}

float4 UnderwaterPS(in WaterVertOut IN): COLOR0
{
    // Calculate eye vector
    float3 EyeVec = IN.pos.xyz - eyePos.xyz;
    float dist = length(EyeVec);
    EyeVec /= dist;

    // Special case fog, avoid fog offset
    float fog = saturate(exp(-dist / 4096));
    
    // Calculate water normal
    float3 normal = -getFinalWaterNormal(IN.texcoords.xy, IN.texcoords.zw, dist, IN.pos.xy);

    // Reflection / refraction pixel distortion factor, wind strength increases distortion
    float2 reffactor = 2 * (windFactor * dist + 0.1) * normal.xy;

    // Distort refraction
    float4 newscrpos = IN.screenpos + float4(2 * -reffactor.xy, 0, 0);
    float3 refracted = tex2Dproj(sampRefract, newscrpos).rgb;
    refracted = lerp(fogColFar, refracted, exp(-dist / 500));

    // Sample reflection texture
    float3 reflected = getProjectedReflection(IN.screenpos - float4(2.1 * reffactor.x, -abs(reffactor.y), 0, 0));

    // Fresnel equation, including total internal reflection
    float fresnel = pow(saturate(1.12 - 0.65 * dot(-EyeVec, normal)), 8);
    float3 result = lerp(refracted, reflected, fresnel);

    // Sun refraction
    float refractsun = dot(-EyeVec, normalize(-sunPos + normal));
    float3 spec = sunColAdjusted * pow(refractsun, 6) * fog;

    return float4(result + spec, 1);
}

//------------------------------------------------------------
// Caustics post-process

DeferredOut CausticsVS(float4 pos : POSITION, float2 tex : TEXCOORD0, float2 ndc : TEXCOORD1)
{
    DeferredOut OUT;
    
    // Fix D3D9 half pixel offset    
    OUT.pos = float4(ndc.x - rcpRes.x, ndc.y + rcpRes.y, 0, 1);
    OUT.tex = float4(tex, 0, 0);
    
    // World space reconstruction vector
    OUT.eye = float3(view[0][2], view[1][2], view[2][2]);
    OUT.eye += (ndc.x / proj[0][0]) * float3(view[0][0], view[1][0], view[2][0]);
    OUT.eye += (ndc.y / proj[1][1]) * float3(view[0][1], view[1][1], view[2][1]);
    return OUT;
}

float4 CausticsPS(DeferredOut IN) : COLOR0
{
    float3 c = tex2Dlod(sampBaseTex, IN.tex).rgb;
    float depth = tex2Dlod(sampDepthPoint, IN.tex).r;
    float fog = fogMWScalar(depth);

    clip(nearViewRange - depth);

    float3 uwpos = eyePos + IN.eye * depth;
    uwpos.z -= waterLevel;
    clip(-uwpos.z);

    float3 sunray = uwpos - sunVec * (uwpos.z / sunVec.z);
    float caust = causticsStrength * tex3D(sampWater3d, float3(sunray.xy / 1104, 0.4 * time)).b;
    caust *= saturate(125 / depth * min(fwidth(sunray.x), fwidth(sunray.y)));
    c *= 1 + (caust - 0.3) * saturate(exp(uwpos.z / 400)) * saturate(uwpos.z / -30) * fog;
    
    return float4(c, 1);
}


//------------------------------------------------------------
// Dynamic waves simulation

struct WaveVertOut
{
    float4 pos : POSITION;
    float2 texcoord : TEXCOORD0;
};

WaveVertOut WaveVS(float4 pos : POSITION, float2 texcoord : TEXCOORD0)
{
    WaveVertOut OUT;
    OUT.pos = mul(pos, proj);
    OUT.texcoord = texcoord;
    return OUT;
}

float4 WaveStepPS(float2 tex : TEXCOORD0) : COLOR0
{
    // Texture content is now float16 in range [-1, 1]
    float4 tc = float4(tex, 0, 0);
    float4 c = tex2Dlod(sampRain, tc);
    float4 ret = {0, c.r, 0, 0};
    
    float4 n = {
        tex2D(sampRain, tc + float4(waveTexRcpRes, 0, 0, 0)).r,
        tex2D(sampRain, tc + float4(-waveTexRcpRes, 0, 0, 0)).r,
        tex2D(sampRain, tc + float4(0, waveTexRcpRes, 0, 0)).r,
        tex2D(sampRain, tc + float4(0, -waveTexRcpRes, 0, 0)).r
    };
    float4 n2 = {
        tex2D(sampRain, tc + float4(1.5 * waveTexRcpRes, 0, 0, 0)).r,
        tex2D(sampRain, tc + float4(-1.5 * waveTexRcpRes, 0, 0, 0)).r,
        tex2D(sampRain, tc + float4(0, 1.5 * waveTexRcpRes, 0, 0)).r,
        tex2D(sampRain, tc + float4(0, -1.5 * waveTexRcpRes, 0, 0)).r
    };
    
    // dampened discrete two-dimensional wave equation
    // red channel: u(t)
    // green channel: u(t - 1)
    // u(t + 1) = (1 - udamp) * u(t) + a * (nsum - 4 * u(t)) + (1 - vdamp) * (u(t) - u(t - 1))
    //        = a * nsum + ((2 - udamp - vdamp) - 4 * a) * u(t) - (1 - vdamp) * u(t - 1);
    float nsum = n.x + n.y + n.z + n.w;
    ret.r = 0.14 * nsum + (1.96 - 0.56) * c.r - 0.98 * c.g;
    
    // calculate normal map
    ret.ba = 2 * (n.xy - n.zw) + 0.5 * (n2.xy - n2.zw);
    return ret;
}

float4 PlayerWavePS(float2 tex : TEXCOORD0) : COLOR0
{
    float4 ret = tex2Dlod(sampRain, float4(tex, 0, 0));
    float wavesize = (1.0 + 0.055 * sin(16 * time) + 0.065 * sin(12.87645 * time)) * playerWaveSize;
    float displace = saturate(2 * abs(length(tex - rippleOrigin) / wavesize - 1));
    ret.rg = lerp(-1, ret.rg, displace);
    return ret;
}
