using System;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public static class NPRMotionBlurSetup
{
    [MenuItem("NPR/Setup Motion Blur")]
    public static void Setup()
    {
        var renderer = AssetDatabase.LoadAssetAtPath<UniversalRendererData>("Assets/Settings/PC_Renderer.asset");
        NPRMotionBlurRendererFeature feature = null;
        foreach (var item in renderer.rendererFeatures)
            if (item is NPRMotionBlurRendererFeature found) feature = found;
        if (feature == null)
        {
            feature = ScriptableObject.CreateInstance<NPRMotionBlurRendererFeature>();
            feature.name = "NPR Motion Blur";
            AssetDatabase.AddObjectToAsset(feature, renderer);
            renderer.rendererFeatures.Add(feature);
        }
        feature.blurShader = Shader.Find("Hidden/NPR/MotionBlur");
        feature.enableBlur = true;
        feature.SetActive(true);
        feature.Create();
        // 保存子资源 ID 映射，确保重载项目后 Renderer 引用仍可恢复。
        var serialized = new SerializedObject(renderer);
        var map = serialized.FindProperty("m_RendererFeatureMap");
        map.arraySize = renderer.rendererFeatures.Count;
        for (int i = 0; i < renderer.rendererFeatures.Count; i++)
        {
            AssetDatabase.TryGetGUIDAndLocalFileIdentifier(renderer.rendererFeatures[i], out string guid, out long localId);
            map.GetArrayElementAtIndex(i).longValue = localId;
        }
        serialized.ApplyModifiedPropertiesWithoutUndo();
        renderer.SetDirty();
        EditorUtility.SetDirty(feature);
        EditorUtility.SetDirty(renderer);
        AssetDatabase.SaveAssetIfDirty(renderer);
        SceneView.RepaintAll();
        Debug.Log("NPR Motion Blur registered on PC Renderer (Game + SceneView)");
    }

    [MenuItem("NPR/Validate Motion Blur")]
    public static void Validate()
    {
        Type type = null;
        foreach (var assembly in AppDomain.CurrentDomain.GetAssemblies())
        {
            type = assembly.GetType("NPRMotionBlurRendererFeature");
            if (type != null) break;
        }
        Require(type != null, "motion blur feature missing");
        var supportsCamera = type.GetMethod("SupportsCamera");
        foreach (CameraType cameraType in new[] { CameraType.Game, CameraType.SceneView })
            Require((bool)supportsCamera.Invoke(null, new object[] { cameraType }), cameraType + " must be supported");
        foreach (CameraType cameraType in new[] { CameraType.Preview, CameraType.Reflection })
            Require(!(bool)supportsCamera.Invoke(null, new object[] { cameraType }), cameraType + " must be skipped");
        var shader = Shader.Find("Hidden/NPR/MotionBlur");
        Require(shader != null && shader.isSupported, "motion blur shader missing or unsupported");
        foreach (var message in ShaderUtil.GetShaderMessages(shader))
            Require(message.severity != UnityEditor.Rendering.ShaderCompilerMessageSeverity.Error, message.message);
        ValidateGPU(shader);
        System.IO.Directory.CreateDirectory("Temp/NPRMotionBlur");
        System.IO.File.WriteAllText("Temp/NPRMotionBlur/validation.txt", "PASS: Game + SceneView supported, Preview + Reflection skipped, shader supported; GPU stationary/moving/stationary regression passed");
        Debug.Log("NPR motion blur validation PASS");
    }

    [MenuItem("NPR/Validate Scene View Blur")]
    public static void ValidateSceneView()
    {
        SceneView.RepaintAll();
            var renderer = AssetDatabase.LoadAssetAtPath<UniversalRendererData>("Assets/Settings/PC_Renderer.asset");
            NPRMotionBlurRendererFeature feature = null;
            foreach (var item in renderer.rendererFeatures)
                if (item is NPRMotionBlurRendererFeature found) feature = found;
            Require(feature != null, "feature not registered");
            var pass = typeof(NPRMotionBlurRendererFeature).GetField("blurPass", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance).GetValue(feature);
            var histories = (System.Collections.IDictionary)pass.GetType().GetField("histories", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance).GetValue(pass);
            bool foundScene = false;
            foreach (Camera camera in histories.Keys) if (camera != null && camera.cameraType == CameraType.SceneView) foundScene = true;
            Require(foundScene, "SceneView did not record the blur pass; expose Scene window and retry");
            System.IO.Directory.CreateDirectory("Temp/NPRMotionBlur");
            System.IO.File.WriteAllText("Temp/NPRMotionBlur/scene-validation.txt", "PASS: SceneView recorded blur pass; playing=" + EditorApplication.isPlaying);
            Debug.Log("NPR SceneView blur validation PASS; playing=" + EditorApplication.isPlaying);
    }

    static void ValidateGPU(Shader shader)
    {
        var material = new Material(shader);
        var input = new Texture2D(256, 16, TextureFormat.RGBA32, false, true);
        var depth = new Texture2D(1, 1, TextureFormat.RFloat, false, true);
        var readback = new Texture2D(256, 16, TextureFormat.RGBA32, false, true);
        var output = RenderTexture.GetTemporary(256, 16, 0, RenderTextureFormat.ARGB32, RenderTextureReadWrite.Linear);
        var previousTarget = RenderTexture.active;
        try
        {
            var colors = new Color[256 * 16];
            for (int i = 0; i < colors.Length; i++) colors[i] = ((i % 256) / 4) % 2 == 0 ? Color.black : Color.white;
            input.SetPixels(colors); input.Apply();
            depth.SetPixel(0, 0, new Color(0.5f, 0, 0)); depth.Apply();
            var properties = new MaterialPropertyBlock();
            properties.SetTexture("_SourceColor", input);
            properties.SetTexture("_CameraDepthTexture", depth);
            properties.SetMatrix("_InverseViewProjection", Matrix4x4.identity);
            properties.SetVector("_BlitScaleBias", new Vector4(1, 1, 0, 0));
            properties.SetFloat("_BlurStrength", 1);
            properties.SetFloat("_MaxBlurLength", 0.1f);
            properties.SetInt("_SampleCount", 16);
            Color[] stationary = null;
            for (int mode = 0; mode < 3; mode++)
            {
                properties.SetMatrix("_PreviousViewProjection", mode == 1 ? Matrix4x4.Translate(Vector3.right * 0.1f) : Matrix4x4.identity);
                var cmd = new CommandBuffer();
                cmd.SetRenderTarget(output);
                cmd.DrawProcedural(Matrix4x4.identity, material, 0, MeshTopology.Triangles, 3, 1, properties);
                Graphics.ExecuteCommandBuffer(cmd); cmd.Release();
                RenderTexture.active = output;
                readback.ReadPixels(new Rect(0, 0, 256, 16), 0, 0); readback.Apply();
                var result = readback.GetPixels();
                if (mode == 0)
                {
                    stationary = result;
                    Require(Mathf.Abs(result[8].r - result[12].r) > 0.8f, "stationary stripes should remain sharp");
                }
                else
                {
                    float difference = 0;
                    for (int i = 32; i < 224; i++) difference += Mathf.Abs(result[i].r - stationary[i].r);
                    difference /= 192;
                    Require(mode == 1 ? difference > 0.1f : difference < 0.005f,
                        "GPU blur regression failed, mode=" + mode + ", difference=" + difference);
                }
            }
        }
        finally
        {
            RenderTexture.active = previousTarget;
            RenderTexture.ReleaseTemporary(output);
            UnityEngine.Object.DestroyImmediate(material);
            UnityEngine.Object.DestroyImmediate(input);
            UnityEngine.Object.DestroyImmediate(depth);
            UnityEngine.Object.DestroyImmediate(readback);
        }
    }

    static void Require(bool condition, string message)
    {
        if (!condition) throw new Exception("NPR validation: " + message);
    }
}
