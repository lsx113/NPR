Shader "Myshader/body"
{
    Properties
    {
        [Header(Textures)]
        _BaseMap("Base Map",2D)="white"{}
        _LightMap("Light Map",2D)="white"{}
        [Toggle(_USE_AO)]_UseAO("Use AO",Range(0,1)) = 1//AO开关

        [Header(Rampshadow)]
        [Toggle(_USE_RAMP_SHADOW)]_UseRampShadow("Use Ramp Shadow",Range(0,1)) = 1//色阶阴影开关
        [Toggle]_UseShadow2("Use Shadow2",Range(0,1)) = 1
        [Toggle]_UseShadow3("Use Shadow3",Range(0,1)) = 1
        [Toggle]_UseShadow4("Use Shadow4",Range(0,1)) = 1
        [Toggle]_UseShadow5("Use Shadow5",Range(0,1)) = 1
        [Toggle]_IsDay("Is Day(是否为白天)",Range(0,1)) = 1
        _RampTex ("Ramp Tex (色阶渐变图)", 2D) = "white" {}
        _ShadowPosition ("Shadow Position(明暗分界线位置)",Range(0,1)) = 0.5
        _ShadowSoftness ("Shadow Softness(阴影边缘硬度)", Float) = 0.1
        _ShadowWidth("Shadow Width(阴影宽度)",Float)=1.0
        [Header(Fresnel Rim)]
        [HDR] _RimColor("Rim Color", Color) = (0.6, 0.8, 1, 1)
        _RimIntensity("Rim Intensity(边缘光强度)", Range(0, 3)) = 0.3
        _RimPower("Rim Power(边缘光收紧)", Range(0.1, 10)) = 3
        [Header(Blinn Phong Specular)]
        [HDR] _SpecularColor("Specular Color", Color) = (1, 1, 1, 1)
        _SpecularIntensity("Specular Intensity(高光强度)", Range(0, 5)) = 0.8
        _Shininess("Shininess(高光收紧)", Range(1, 256)) = 48
        [Header(Outline)]
        _OutlineColor("Outline Color(描边颜色)", Color) = (0.04, 0.025, 0.035, 1)
        _OutlineWidth("Outline Width(描边宽度)", Range(0, 0.02)) = 0.003
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        HLSLINCLUDE
        //自定义开关
        #pragma shader_feature_local _USE_AO
        #pragma shader_feature_local _USE_RAMP_SHADOW
        //URP
        #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
        #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
        #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
        #pragma multi_compile_fragment _ _SHADOWS_SOFT
        //头文件
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
        //常量缓冲区
        CBUFFER_START(UnityPerMaterial)
            float _ShadowPosition;
            float _ShadowSoftness;
            float _ShadowWidth;
            float _UseShadow2;
            float _UseShadow3;
            float _UseShadow4;
            float _UseShadow5;
            float _IsDay;
            float4 _RimColor;
            float _RimIntensity;
            float _RimPower;
            float4 _SpecularColor;
            float _SpecularIntensity;
            float _Shininess;
            float4 _OutlineColor;
            float _OutlineWidth;
        CBUFFER_END
        //纹理
        TEXTURE2D(_BaseMap);
        SAMPLER(sampler_BaseMap);
        TEXTURE2D(_RampTex);
        SAMPLER(sampler_RampTex);
        TEXTURE2D(_LightMap);
        SAMPLER(sampler_LightMap);
        ENDHLSL

        Pass{
            Name "UniversalForward"
            Tags{ "Lightmode" = "UniversalForward" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 4.5
            // 官方版本的RampShadowID函数
            float RampShadowID(float input, float useShadow2, float useShadow3, float useShadow4, float useShadow5, 
            float shadowValue1, float shadowValue2, float shadowValue3, float shadowValue4, float shadowValue5)
            {
                // 根据input值将模型分为5个区域
                float v1 = step(0.6, input) * step(input, 0.8); // 0.6-0.8区域
                float v2 = step(0.4, input) * step(input, 0.6); // 0.4-0.6区域
                float v3 = step(0.2, input) * step(input, 0.4); // 0.2-0.4区域
                float v4 = step(input, 0.2);                    // 0-0.2区域

                // 根据开关控制是否使用不同材质的值
                float blend12 = lerp(shadowValue1, shadowValue2, useShadow2);
                float blend15 = lerp(shadowValue1, shadowValue5, useShadow5);
                float blend13 = lerp(shadowValue1, shadowValue3, useShadow3);
                float blend14 = lerp(shadowValue1, shadowValue4, useShadow4);

                // 根据区域选择对应的材质值
                float result = blend12;                // 默认使用材质1或2
                result = lerp(result, blend15, v1);    // 0.6-0.8区域使用材质5
                result = lerp(result, blend13, v2);    // 0.4-0.6区域使用材质3
                result = lerp(result, blend14, v3);    // 0.2-0.4区域使用材质4
                result = lerp(result, shadowValue1, v4); // 0-0.2区域使用材质1

                return result;
			}

            //顶点输入
            struct VertIN{
                float3 positionOS:POSITION;
                float3 normalOS:NORMAL;
                float3 color:COLOR;
                float2 uv0:TEXCOORD0;
            };
            //顶点输出
            struct VertOUT{
                float4 positionCS:SV_POSITION;
                float2 uv0:TEXCOORD0;//第一套纹理
                float3 normalWS:TEXCOORD1;//世界空间法线
                float3 color:TEXCOORD2;//顶点颜色
                float3 positionWS : TEXCOORD3;//世界位置
            };
            VertOUT vert(VertIN input){
                VertOUT output;
                //位置
                VertexPositionInputs vertexInput=GetVertexPositionInputs(input.positionOS);
                output.positionCS=vertexInput.positionCS;
                output.positionWS=vertexInput.positionWS;
                //法线
                VertexNormalInputs vertexNormal=GetVertexNormalInputs(input.normalOS);
                output.normalWS=vertexNormal.normalWS;
                //uv
                output.uv0=input.uv0;
                //color
                output.color=input.color;
                return output;
            }

            float4 frag(VertOUT input):SV_Target
            {
                //获取光照
                Light light=GetMainLight();
                //归一化方向
                float3 N=normalize(input.normalWS);
                float3 L=normalize(light.direction);
                half NdotL=dot(N,L);
                //采样
                float4 lightmap=SAMPLE_TEXTURE2D(_LightMap,sampler_LightMap,input.uv0);
                float3 basecolor=SAMPLE_TEXTURE2D(_BaseMap,sampler_BaseMap,input.uv0).rgb;
                //Lambert
                half lambert=NdotL;
                half halflambert=lambert*0.5+0.5;//归到1到1的区间
                halflambert*=pow(halflambert,2);
                #if _USE_AO//是否用AO
                    half ambient=lightmap.g;
                #else
                    half ambient=halflambert;
                #endif
                half shadow=(ambient+halflambert)*0.5;
                //小于0.05和大于0.95的两边移动
                shadow=lerp(shadow,1,step(0.95,ambient));
                shadow=lerp(shadow,0,step(ambient,0.05));
                //色阶阴影
                bool isAtShadow=step(shadow,_ShadowPosition);//判断是否处于阴影
                half ShadowDepth=saturate((_ShadowPosition-shadow)/_ShadowPosition);//计算阴影深度
                ShadowDepth=min(pow(ShadowDepth,_ShadowSoftness),1);//计算柔和度
                half rampWidthFactor=input.color.g*2*_ShadowWidth;//根据顶点颜色算长度因子
                //Ramp
                half RampU=1-saturate(ShadowDepth/rampWidthFactor);
                half rampID=RampShadowID(lightmap.a,_UseShadow2,_UseShadow3,_UseShadow4,_UseShadow5,1,2,3,4,5);//计算材质ID
                half RampV=0.45-(rampID-1)*0.1;
                //根据白天黑夜选择不同阴影
                half2 DayRampUV=half2(RampU,RampV+0.5);
                half2 NightRampUV=half2(RampU,RampV);
                float3 Daycolor=SAMPLE_TEXTURE2D(_RampTex,sampler_RampTex,DayRampUV).rgb;
                float3 Nightcolor=SAMPLE_TEXTURE2D(_RampTex,sampler_RampTex,NightRampUV).rgb;
                float3 Rampcolor=lerp(Nightcolor,Daycolor,_IsDay);//根据是否为白天选择阴影
                #if _USE_RAMP_SHADOW
                    float3 finalColor=basecolor*Rampcolor*(isAtShadow?1:1.2);
                #else
                    float3 finalColor=basecolor*halflambert*(shadow+0.2);
                #endif
                // 表面指向相机的世界空间方向
                float3 V = GetWorldSpaceNormalizeViewDir(input.positionWS);

                // ---------- 菲涅尔边缘光 ----------
                float NdotV = saturate(dot(N, V));

                float rim = pow(
                1.0 - NdotV,
                max(_RimPower, 0.001)
                );

                float3 rimColor =
                rim * _RimColor.rgb * _RimIntensity;

                // ---------- Blinn-Phong 高光 ----------
                float3 H = SafeNormalize(L + V);
                float NdotH = saturate(dot(N, H));

                float specular = pow(
                NdotH,
                max(_Shininess, 1.0)
                );

                // B 通道控制高光强度，黑色区域没有高光
                specular *= saturate(lightmap.b);

                // 降低背光面的高光
                specular *= saturate(dot(N, L));

                // R 通道控制普通高光与金属色高光的过渡
                float3 specularTint = lerp(
                _SpecularColor.rgb,
                _SpecularColor.rgb * basecolor,
                saturate(lightmap.r)
                );

                float3 specularColor =
                specularTint *
                specular *
                _SpecularIntensity *
                light.color;

                // ---------- 合成 ----------
                finalColor += rimColor + specularColor;
                return float4(finalColor,0);
            }

            ENDHLSL
		}
        //描边
		Pass
		{
			Name "NPROutline"
			Tags { "LightMode" = "NPROutline" }

			Cull Front
			ZWrite Off
			ZTest LEqual

			HLSLPROGRAM
			#pragma vertex OutlineVert
			#pragma fragment OutlineFrag

			struct OutlineAttributes
			{
				float3 positionOS : POSITION;
				float3 normalOS   : NORMAL;
			};

			struct OutlineVaryings
			{
				float4 positionCS : SV_POSITION;
			};

			OutlineVaryings OutlineVert(OutlineAttributes input)
			{
				OutlineVaryings output;

				// 1. 顶点位置转换到世界空间
				float3 positionWS =
				TransformObjectToWorld(input.positionOS);

				// 2. 法线转换到世界空间并归一化
				float3 normalWS =
				normalize(TransformObjectToWorldNormal(input.normalOS));

				// 3. 沿世界空间法线外扩
				positionWS += normalWS * _OutlineWidth;

				// 4. 转换到裁剪空间
				output.positionCS =
				TransformWorldToHClip(positionWS);

				return output;
			}

			half4 OutlineFrag(OutlineVaryings input) : SV_Target
			{
				// 宽度为 0 时关闭描边
				clip(_OutlineWidth - 0.000001);

				return half4(_OutlineColor.rgb, 1);
			}
			ENDHLSL
		}
	}
}
