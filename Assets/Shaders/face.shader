Shader "Myshader/face"
{
    Properties
    {
        [Header(Textures)]
        _BaseMap("Base Map",2D) = "white"{}
        _ShadowColor("Shadow Color (阴影颜色)", Color) = (1, 0.87, 0.87, 1)

        [Header(SDF)]
        [Toggle(_USE_SDF_SHADOW)]_UseSDFShadow("Use SDF Shadow",Range(0,1)) = 1 // SDF开关
        _SDFMap("SDF Map (SDF阈值图)",2D) = "white" {}
        _ShadowMask("Shadow Mask (遮罩贴图)",2D) ="white" {}

        [Header(Head Direction)]
        [HideInInspector] _HeadForward ("Head Forward", Vector) = (0, 0, 1, 0)
        [HideInInspector] _HeadRight ("Head Right", Vector) = (1, 0, 0, 0)
        [HideInInspector] _HeadUp ("Head Up", Vector) = (0, 1, 0, 0)
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        HLSLINCLUDE
        #pragma shader_feature_local _USE_SDF_SHADOW

        #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN

        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

        CBUFFER_START(UnityPerMaterial)
        float4 _BaseMap_ST;
        float4 _SDFMap_ST;
        float4 _ShadowMask_ST;
        float4 _ShadowColor;

        float4 _HeadForward;
        float4 _HeadRight;
        float4 _HeadUp;
        CBUFFER_END

        TEXTURE2D(_BaseMap);
        SAMPLER(sampler_BaseMap);
        TEXTURE2D(_SDFMap);
        SAMPLER(sampler_SDFMap);
        TEXTURE2D(_ShadowMask);
        SAMPLER(sampler_ShadowMask);
        ENDHLSL

        Pass{
            Name "UniversalForward"
            Tags{ "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 4.5

            struct VertIN{
                float3 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv0 : TEXCOORD0;
            };

            struct VertOUT{
                float4 positionCS : SV_POSITION;
                float3 normalWS : TEXCOORD1; 
                float2 uv0 : TEXCOORD0;
            };

            VertOUT vert(VertIN input){
                VertOUT output;
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS);
                output.positionCS = vertexInput.positionCS;

                // 计算并传递世界空间法线
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS);
                output.normalWS = normalInput.normalWS;

                output.uv0 = input.uv0;
                return output;
            }

            float4 frag(VertOUT input) : SV_Target
            {
                // 1. 采样贴图
                float4 baseMap = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv0);
                float4 shadowMask = SAMPLE_TEXTURE2D(_ShadowMask, sampler_ShadowMask, input.uv0);

                // 获取主光源方向
                Light light = GetMainLight();
                float3 L = normalize(light.direction);

                // 归一化传过来的世界法线
                float3 N = normalize(input.normalWS);

                // 获取头部坐标系
                float3 headForwardDir = normalize(_HeadForward.xyz);
                float3 headRightDir = normalize(_HeadRight.xyz);
                float3 headUpDir = normalize(_HeadUp.xyz);

                float sdf = 1.0; // 默认亮部

                #if _USE_SDF_SHADOW
                    // --- 2. SDF 核心计算 ---
                    float3 LpU = dot(L, headUpDir) * headUpDir;
                    float3 LpHeadHorizon = normalize(L - LpU);
                    float value = acos(dot(LpHeadHorizon, headRightDir)) / 3.141592654;

                    float exposeRight = step(value, 0.5);

                    float sdfRight = SAMPLE_TEXTURE2D(_SDFMap, sampler_SDFMap, input.uv0).r;
                    float sdfLeft = SAMPLE_TEXTURE2D(_SDFMap, sampler_SDFMap, float2(1.0 - input.uv0.x, input.uv0.y)).r;

                    float mixSdf = lerp(sdfRight, sdfLeft, exposeRight);

                    float valueR = pow(1.0 - value * 2.0, 3.0);
                    float valueL = pow(value * 2.0 - 1.0, 3.0);
                    float mixValue = lerp(valueL, valueR, exposeRight);

                    sdf = step(mixValue, mixSdf);

                    sdf = lerp(0, sdf, step(0, dot(LpHeadHorizon, headForwardDir)));

                    sdf *= shadowMask.g;
                    sdf = lerp(sdf, 1, shadowMask.a);
                #endif

                // --- 3. 最终颜色合并 ---
                #if _USE_SDF_SHADOW
                    float3 litColor = baseMap.rgb;
                    float3 darkColor = baseMap.rgb * (_ShadowColor.rgb+0.4);
                    float3 finalColor = lerp(darkColor, litColor, sdf);
                    #else

                    float NdotL = saturate(dot(N, L));
                    float halflambert = NdotL * 0.5 + 0.5;
                    float3 finalColor = baseMap.rgb * pow(halflambert,3);
                #endif

                return float4(finalColor, 1);
            }
            ENDHLSL
        }
    }
}