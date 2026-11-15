using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

public sealed class NPROutlineRendererFeature : ScriptableRendererFeature
{
    [Tooltip("开启或关闭描边")]
    public bool enableOutline = true;

    private OutlinePass outlinePass;

    public override void Create()
    {
        outlinePass = new OutlinePass
        {
            // 配合描边 Shader 的 ZWrite Off，
            // 放在天空盒之后，避免描边被天空覆盖。
            renderPassEvent = RenderPassEvent.AfterRenderingSkybox
        };
    }

    public override void AddRenderPasses(
        ScriptableRenderer renderer,
        ref RenderingData renderingData)
    {
        // Inspector 中的总开关
        if (!enableOutline)
            return;

        var cameraData = renderingData.cameraData;

        // 只处理 Game 和 Scene 相机，跳过预览、反射相机。
        if (cameraData.cameraType != CameraType.Game &&
            cameraData.cameraType != CameraType.SceneView)
        {
            return;
        }

        // 这版用于普通基础相机。
        if (cameraData.renderType == CameraRenderType.Overlay ||
            cameraData.xrRendering)
        {
            return;
        }

        renderer.EnqueuePass(outlinePass);
    }

    private sealed class OutlinePass : ScriptableRenderPass
    {
        // 只绘制具有此 LightMode 的 Shader Pass。
        private static readonly ShaderTagId OutlineTag =
            new ShaderTagId("NPROutline");

        private sealed class PassData
        {
            public RendererListHandle rendererList;
        }

        public OutlinePass()
        {
            profilingSampler = new ProfilingSampler("NPR Outline");
        }

        public override void RecordRenderGraph(
            RenderGraph renderGraph,
            ContextContainer frameData)
        {
            var resources = frameData.Get<UniversalResourceData>();
            var cameraData = frameData.Get<UniversalCameraData>();
            var renderingData = frameData.Get<UniversalRenderingData>();
            var lightData = frameData.Get<UniversalLightData>();

            if (!resources.activeColorTexture.IsValid() ||
                !resources.activeDepthTexture.IsValid())
            {
                return;
            }

            // 根据 LightMode 选择描边 Pass。
            var drawingSettings = RenderingUtils.CreateDrawingSettings(
                OutlineTag,
                renderingData,
                cameraData,
                lightData,
                cameraData.defaultOpaqueSortFlags
            );

            // 使用物体自己的材质与描边参数。
            drawingSettings.overrideMaterial = null;
            drawingSettings.overrideShader = null;

            // 包含所有 Layer，只筛选不透明渲染队列。
            var filteringSettings = new FilteringSettings(
                RenderQueueRange.opaque,
                -1
            );

            var listParams = new RendererListParams(
                renderingData.cullResults,
                drawingSettings,
                filteringSettings
            );

            var rendererList = renderGraph.CreateRendererList(listParams);

            using (var builder =
                renderGraph.AddRasterRenderPass<PassData>(
                    "NPR Outline",
                    out var passData,
                    profilingSampler))
            {
                passData.rendererList = rendererList;

                builder.UseRendererList(rendererList);

                // 保留场景颜色，在上面绘制描边。
                builder.SetRenderAttachment(
                    resources.activeColorTexture,
                    0,
                    AccessFlags.ReadWrite
                );

                // 使用已有深度测试，不修改深度。
                builder.SetRenderAttachmentDepth(
                    resources.activeDepthTexture,
                    AccessFlags.Read
                );

                builder.SetRenderFunc(
                    (PassData data, RasterGraphContext context) =>
                    {
                        context.cmd.DrawRendererList(data.rendererList);
                    }
                );
            }
        }
    }
}