using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

public sealed class NPRMotionBlurRendererFeature : ScriptableRendererFeature
{
    public bool enableBlur = true;
    public Shader blurShader;
    [Range(0, 2)] public float intensity = 1f;
    [Range(0, 0.1f)] public float shutterSeconds = 1f / 30f;
    [Range(0, 0.15f)] public float maxBlurLength = 0.05f;
    [Range(4, 16)] public int sampleCount = 8;

    private Material blurMaterial;
    private MotionBlurPass blurPass;

    public static bool SupportsCamera(CameraType type)
    {
        return type == CameraType.Game || type == CameraType.SceneView;
    }

    public override void Create()
    {
        CoreUtils.Destroy(blurMaterial);
        blurMaterial = blurShader != null ? CoreUtils.CreateEngineMaterial(blurShader) : null;
        blurPass = new MotionBlurPass
        {
            renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing
        };
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (!enableBlur || blurMaterial == null)
        {
            blurPass.ClearHistory();
            return;
        }

        // Game 相机和未进入 Play 时的 Scene View 相机都执行。
        if (!SupportsCamera(renderingData.cameraData.cameraType)) return;

        blurPass.Setup(blurMaterial, intensity, shutterSeconds, maxBlurLength, sampleCount);
        renderer.EnqueuePass(blurPass);
    }

    protected override void Dispose(bool disposing)
    {
        CoreUtils.Destroy(blurMaterial);
        blurPass?.ClearHistory();
    }

    private sealed class MotionBlurPass : ScriptableRenderPass
    {
        private Material material;
        private float intensity, shutterSeconds, maxBlurLength;
        private int sampleCount;

        // 只保存上一张画面的 VP 和渲染时间，不判断窗口、帧号、位移或旋转。
        private readonly Dictionary<Camera, (Matrix4x4 vp, double time)> histories =
            new Dictionary<Camera, (Matrix4x4 vp, double time)>();

        private sealed class PassData
        {
            public TextureHandle source, depth;
            public Material material;
            public MaterialPropertyBlock properties;
        }

        public MotionBlurPass()
        {
            profilingSampler = new ProfilingSampler("NPR Motion Blur");
            ConfigureInput(ScriptableRenderPassInput.Depth);
            requiresIntermediateTexture = true;
        }

        public void Setup(Material mat, float strength, float shutter, float maxLength, int samples)
        {
            material = mat;
            intensity = strength;
            shutterSeconds = shutter;
            maxBlurLength = maxLength;
            sampleCount = Mathf.Clamp(samples, 4, 16);
        }

        public void ClearHistory() => histories.Clear();

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            var resources = frameData.Get<UniversalResourceData>();
            var cameraData = frameData.Get<UniversalCameraData>();
            var camera = cameraData.camera;

            // 只检查执行所必需的输入资源。
            if (resources.isActiveTargetBackBuffer || !resources.activeColorTexture.IsValid() ||
                !resources.cameraDepthTexture.IsValid()) return;

            var projection = GL.GetGPUProjectionMatrix(cameraData.GetProjectionMatrix(), true);
            var currentVP = projection * cameraData.GetViewMatrix();

            // Scene View 在编辑模式中也会重绘，用实际时间代替游戏帧间隔。
            double now = Time.realtimeSinceStartupAsDouble;
            Matrix4x4 previousVP = currentVP;
            float seconds = 1f / 60f;
            if (histories.TryGetValue(camera, out var previous))
            {
                previousVP = previous.vp;
                seconds = (float)(now - previous.time);
            }
            histories[camera] = (currentVP, now);

            var properties = new MaterialPropertyBlock();
            properties.SetMatrix("_InverseViewProjection", currentVP.inverse);
            properties.SetMatrix("_PreviousViewProjection", previousVP);
            properties.SetFloat("_BlurStrength", intensity * shutterSeconds / Mathf.Max(seconds, 0.0001f));
            properties.SetFloat("_MaxBlurLength", maxBlurLength);
            properties.SetInt("_SampleCount", sampleCount);
            properties.SetVector("_BlitScaleBias", new Vector4(1, 1, 0, 0));

            var descriptor = renderGraph.GetTextureDesc(resources.activeColorTexture);
            descriptor.name = "NPR Motion Blur Color";
            descriptor.depthBufferBits = DepthBits.None;
            descriptor.msaaSamples = MSAASamples.None;
            descriptor.clearBuffer = false;
            var destination = renderGraph.CreateTexture(descriptor);

            using (var builder = renderGraph.AddRasterRenderPass<PassData>(
                "NPR Motion Blur", out var passData, profilingSampler))
            {
                passData.source = resources.activeColorTexture;
                passData.depth = resources.cameraDepthTexture;
                passData.material = material;
                passData.properties = properties;
                builder.UseTexture(passData.source, AccessFlags.Read);
                builder.UseTexture(passData.depth, AccessFlags.Read);
                builder.SetRenderAttachment(destination, 0, AccessFlags.Write);
                builder.SetRenderFunc((PassData data, RasterGraphContext context) =>
                {
                    RTHandle source = data.source;
                    RTHandle depth = data.depth;
                    data.properties.SetTexture("_SourceColor", source.rt);
                    data.properties.SetTexture("_CameraDepthTexture", depth.rt);
                    context.cmd.DrawProcedural(Matrix4x4.identity, data.material, 0,
                        MeshTopology.Triangles, 3, 1, data.properties);
                });
            }
            resources.cameraColor = destination;
        }
    }
}
