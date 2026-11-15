Shader "Hidden/NPR/MotionBlur"
{
    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" }
        Pass
        {
            Name "MotionBlur"
            ZWrite Off
            ZTest Always
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma target 3.5
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            TEXTURE2D(_SourceColor);
            float4x4 _InverseViewProjection;
            float4x4 _PreviousViewProjection;
            float _BlurStrength;
            float _MaxBlurLength;
            int _SampleCount;

            // 对透视和 Scene View 的正交模式分别计算深度差。
            float EyeDepth(float rawDepth)
            {
                if (unity_OrthoParams.w > 0.5)
                {
                    #if UNITY_REVERSED_Z
                        rawDepth = 1.0 - rawDepth;
                    #endif
                    return lerp(_ProjectionParams.y, _ProjectionParams.z, rawDepth);
                }
                return LinearEyeDepth(rawDepth, _ZBufferParams);
            }

            half4 Frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                half4 center = SAMPLE_TEXTURE2D(_SourceColor, sampler_LinearClamp, uv);
                float rawDepth = SampleSceneDepth(uv);

                // 天空没有可重建的场景表面，保留原色。
                #if UNITY_REVERSED_Z
                    if (rawDepth <= 0.000001) return center;
                    float depth = rawDepth;
                #else
                    if (rawDepth >= 0.999999) return center;
                    float depth = lerp(UNITY_NEAR_CLIP_VALUE, 1.0, rawDepth);
                #endif

                float3 positionWS = ComputeWorldSpacePosition(uv, depth, _InverseViewProjection);
                float4 previousCS = mul(_PreviousViewProjection, float4(positionWS, 1));
                if (previousCS.w <= 0.0001) return center;
                float2 previousNDC = previousCS.xy / previousCS.w;
                #if UNITY_UV_STARTS_AT_TOP
                    previousNDC.y = -previousNDC.y;
                #endif
                float2 previousUV = previousNDC * 0.5 + 0.5;
                float2 velocity = (uv - previousUV) * _BlurStrength;
                velocity *= min(1.0, _MaxBlurLength / max(length(velocity), 0.000001));

                float centerDepth = EyeDepth(rawDepth);
                float3 sum = center.rgb;
                float weightSum = 1;
                [loop]
                for (int i = 0; i < _SampleCount; i++)
                {
                    float t = (i + 0.5) / _SampleCount - 0.5;
                    float2 sampleUV = uv + velocity * t;
                    if (any(sampleUV < 0) || any(sampleUV > 1)) continue;
                    float sampleDepth = EyeDepth(SAMPLE_TEXTURE2D_X_LOD(_CameraDepthTexture, sampler_PointClamp, sampleUV, 0).r);
                    float weight = saturate(1.0 - abs(sampleDepth - centerDepth) / max(centerDepth * 0.03, 0.01));
                    sum += SAMPLE_TEXTURE2D_LOD(_SourceColor, sampler_LinearClamp, sampleUV, 0).rgb * weight;
                    weightSum += weight;
                }
                return half4(sum / weightSum, center.a);
            }
            ENDHLSL
        }
    }
}
