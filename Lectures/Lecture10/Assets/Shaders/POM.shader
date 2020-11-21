﻿Shader "Custom/POM"
{
    Properties {
        // normal map texture on the material,
        // default to dummy "flat surface" normalmap
        [KeywordEnum(PLAIN, NORMAL, BUMP, POM, POM_SHADOWS)] MODE("Overlay mode", Float) = 0
        
        _NormalMap("Normal Map", 2D) = "bump" {}
        _MainTex("Texture", 2D) = "grey" {}
        _HeightMap("Height Map", 2D) = "white" {}
        _MaxHeight("Max Height", Range(0.0001, 0.02)) = 0.01
        _StepLength("Step Length", Float) = 0.000001
        _MaxStepCount("Max Step Count", Int) = 64
        
        _Reflectivity("Reflectivity", Range(1, 100)) = 0.5
    }
    
    CGINCLUDE
    #include "UnityCG.cginc"
    #include "UnityLightingCommon.cginc"
    
    inline float LinearEyeDepthToOutDepth(float z)
    {
        return (1 - _ZBufferParams.w * z) / (_ZBufferParams.z * z);
    }

    struct v2f {
        float3 worldPos : TEXCOORD0;
        float3 wTangent: TEXCOORD1;
        float3 wBitangent: TEXCOORD2;
        float3 wNormal: TEXCOORD3;
        half3 worldSurfaceNormal : TEXCOORD4;
        // texture coordinate for the normal map
        float2 uv : TEXCOORD5;
        float4 clip : SV_POSITION;
    };

    // Vertex shader now also gets a per-vertex tangent vector.
    // In Unity tangents are 4D vectors, with the .w component used to indicate direction of the bitangent vector.
    v2f vert (float4 vertex : POSITION, float3 normal : NORMAL, float4 tangent : TANGENT, float2 uv : TEXCOORD0)
    {
        v2f o;
        o.clip = UnityObjectToClipPos(vertex);
        o.worldPos = mul(unity_ObjectToWorld, vertex).xyz;
        o.wNormal = UnityObjectToWorldNormal(normal);
        o.wTangent = UnityObjectToWorldDir(tangent.xyz);
        
        o.uv = uv;
        o.worldSurfaceNormal = normal;
        
        // compute bitangent from cross product of normal and tangent and output it
        o.wBitangent = cross(o.wNormal, o.wTangent) * tangent.w;
        
        return o;
    }

    // normal map texture from shader properties
    sampler2D _NormalMap;
    sampler2D _MainTex;
    sampler2D _HeightMap;
    
    // The maximum depth in which the ray can go.
    uniform float _MaxHeight;
    // Step size
    uniform float _StepLength;
    // Count of steps
    uniform int _MaxStepCount;
    
    float _Reflectivity;

    float height(float2 uv)
    {
        return _MaxHeight * (1 - tex2D(_HeightMap, uv));
    }

    void frag (in v2f i, out half4 outColor : COLOR, out float outDepth : DEPTH)
    {
        float2 uv = i.uv;
        
        float3 worldViewDir = normalize(i.worldPos.xyz - _WorldSpaceCameraPos.xyz);
        float3x3 transform = float3x3(
            i.wTangent,
            i.wBitangent,
            i.wNormal
        );
        float3 view = mul(transform, worldViewDir);
#if MODE_BUMP
        // Change UV according to the Parallax Offset Mapping
        uv -= view.xy * height(uv) / view.z; 
#endif   
    
        float depthDif = 0;
#if MODE_POM | MODE_POM_SHADOWS    
        // Change UV according to Parallax Occclusion Mapping
        float curH, h = height(uv);
        float3 curA, a = 0;
        float3 step = view * _StepLength;
        for (int j = 0; j < 100; ++j)
        {
            curA = a + step;
            curH = height(uv + curA.xy);
            if (abs(curA.z) > curH) break;
            h = curH;
            a = curA;
        }
        float p = abs(h - abs(a.z)) / (abs(h - abs(a.z)) + abs(abs(curA.z) - curH));
        uv += (1 - p) * a.xy + p * curA.xy;
#endif

        float3 worldLightDir = normalize(_WorldSpaceLightPos0.xyz);
        float shadow = 0;
#if MODE_POM_SHADOWS
        // Calculate soft shadows according to Parallax Occclusion Mapping, assign to shadow
#endif
        
        half3 normal = i.worldSurfaceNormal;
#if !MODE_PLAIN
        // Implement Normal Mapping
        transform[1] *= -1;
        normal = mul(transform, UnpackNormal(tex2D(_NormalMap, uv)));
#endif

        // Diffuse lightning
        half cosTheta = max(0, dot(normal, worldLightDir));
        half3 diffuseLight = max(0, cosTheta) * _LightColor0 * max(0, 1 - shadow);
        
        // Specular lighting (ad-hoc)
        half specularLight = pow(max(0, dot(worldViewDir, reflect(worldLightDir, normal))), _Reflectivity) * _LightColor0 * max(0, 1 - shadow); 

        // Ambient lighting
        half3 ambient = ShadeSH9(half4(UnityObjectToWorldNormal(normal), 1));

        // Return resulting color
        float3 texColor = tex2D(_MainTex, uv);
        outColor = half4((diffuseLight + specularLight + ambient) * texColor, 0);
        outDepth = LinearEyeDepthToOutDepth(LinearEyeDepth(i.clip.z));
    }
    ENDCG
    
    SubShader
    {    
        Pass
        {
            Name "MAIN"
            Tags { "LightMode" = "ForwardBase" }
        
            ZTest Less
            ZWrite On
            Cull Back
            
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #pragma multi_compile_local MODE_PLAIN MODE_NORMAL MODE_BUMP MODE_POM MODE_POM_SHADOWS
            ENDCG
            
        }
    }
}