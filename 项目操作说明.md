# NPR 卡通角色渲染项目操作说明

本文对应当前 main 分支，说明如何打开项目、查看效果、调整参数以及排查常见问题。参数名称以实际 Inspector 为准。

## 一 环境与工程打开

| 项目项 | 配置 |
| --- | --- |
| Unity Editor | 6000.3.10f1 |
| 渲染管线 | Universal Render Pipeline 17.3.0 |
| 推荐查看配置 | PC，使用 PC_RPAsset 与 PC_Renderer |
| 演示场景 | Assets/Scenes/SampleScene.unity |
| 控制方式 | Unity Scene View 原生操作，以及材质和 Renderer Feature 的 Inspector 参数 |

1. 使用 Git 获取项目。项目模型、部分贴图使用 Git LFS，首次获取后执行 `git lfs pull`，确认拿到真实资源而非指针文件。
2. 在 Unity Hub 中将仓库根目录添加为项目，使用指定版本打开。
3. 等待包解析、资源导入和 Shader 编译完成，检查 Console 是否有红色错误。
4. 打开 [SampleScene](Assets/Scenes/SampleScene.unity)。
5. 检查 `Edit > Project Settings > Graphics` 的默认管线，以及 `Quality` 当前档位所指定的管线。质量档位可以覆盖 Graphics 的默认值，实际应使用 [PC_RPAsset](Assets/Settings/PC_RPAsset.asset)。
6. 在 PC_RPAsset 的 Renderer List 中确认使用 [PC_Renderer](Assets/Settings/PC_Renderer.asset)。当前的描边、运动模糊均接在该 Renderer 上。

本项目代码按 Render Graph 路径编写，不要切换到旧的 Compatibility Mode 后再用同一套步骤判断自定义 Pass 是否工作。

## 二 先用 Scene View 查看

不进入 Play 也可以查看大部分效果，包括相机运动模糊。

1. 在 Hierarchy 中选择角色 `Lumine FBX`，将鼠标移到 Scene 窗口，按 F 聚焦。
2. 使用透视、正常着色视图观察，避免用线框模式判断最终颜色。
3. 使用鼠标右键配合 WASD 移动 Scene 相机；也可以使用 Unity 编辑器的环绕、平移和缩放操作。
4. 选择 `Directional Light`，调整旋转角度，观察身体高光和脸部明暗变化。
5. 在 Scene 中移动或旋转视角，观察运动模糊。相机静止后应恢复清晰；必要时轻微移动鼠标或重绘 Scene 窗口。

当前 main 没有额外的自由相机脚本或角色转向快捷键。Scene 窗口的导航属于 Unity 编辑器操作；运行后的角色和 Game 相机不由这些按键自动控制。

### 使用 Game View

1. 选中 Main Camera，检查 Game 窗口是否能看到角色。
2. 如果镜头未对准角色，先在 Scene 中调整好视角，再选中 Main Camera，使用 `GameObject > Align With View` 对齐。
3. 保存场景后进入 Play，观察最终相机输出。
4. 若要在 Game 输出中检查运动模糊，需要让 Main Camera 实际移动或旋转；静止相机不会因为角色独自转动而产生本项目的模糊。

## 三 调整角色材质

身体、头发、服装和饰品的主要材质位于 [Assets/Lumine FBX/body](Assets/Lumine%20FBX/body)。脸部材质位于 [Assets/Lumine FBX/face](Assets/Lumine%20FBX/face)。

建议在退出 Play 后调整并记录参数。Play 中的场景对象参数通常在退出后恢复，而直接修改材质资源可能保留，不要把所有参数都当作临时试验值。

### 身体的贴图与 Ramp 阴影

使用 `Myshader/body` 的材质提供以下设置：

| 参数 | 操作效果 |
| --- | --- |
| Base Map | 角色基础颜色贴图 |
| Light Map | 控制材质区域、AO 和高光的打包数据贴图 |
| Use AO | 是否让 LightMap 的 G 通道参与现有 AO/阴影计算 |
| Use Ramp Shadow | 开启或关闭 Ramp 阴影方案 |
| Ramp Tex | 明暗颜色渐变贴图 |
| Is Day | 在已有日夜 Ramp 区域之间选择 |
| Use Shadow2 至 Use Shadow5 | 控制对应材质分区是否采用独立 Ramp 行 |
| Shadow Position | 明暗分界位置 |
| Shadow Softness | 明暗过渡曲线参数 |
| Shadow Width | 与顶点颜色 G 配合影响阴影宽度 |

调整建议：先只改 Shadow Position 观察范围，再改 Softness 和 Width。当前基础实现存在分母未完整保护的地方，调试时将 Position 和 Width 保持为正值，不要用零作为关闭开关；关闭效果使用对应功能开关。

LightMap 通道约定：

| 通道 | 当前用途 |
| --- | --- |
| R | 控制高光类型与金属色倾向 |
| G | 参与 AO/常驻阴影 |
| B | 高光强度，黑色区域不产生对应高光 |
| A | 选择材质分区与 Ramp 行，不作为透明度 |

基础颜色贴图通常启用 sRGB。LightMap、SDF、遮罩等保存计算数据的贴图通常关闭 sRGB，并保留需要的 Alpha。不要将角色的 LightMap 与 Unity 场景烘焙 Lightmap 混为一谈。

### 菲涅尔边缘光

在材质的 `Fresnel Rim` 区域调整：

| 参数 | 含义 |
| --- | --- |
| Rim Color | 边缘光颜色，可使用 HDR 颜色 |
| Rim Intensity | 边缘光强度；设为 0 可关闭 |
| Rim Power | 收紧程度；越大越窄，越小覆盖范围越宽 |

先将 Intensity 设为 0 对比，再恢复到较小值，最后旋转视角观察。此处是基于 N·V 的材质边缘光，不会自动生成屏幕空间轮廓线。

### Blinn-Phong 高光

在 `Blinn Phong Specular` 区域调整：

| 参数 | 含义 |
| --- | --- |
| Specular Color | 高光颜色 |
| Specular Intensity | 高光强度；设为 0 可关闭 |
| Shininess | 高光集中程度；越大高光越小、越集中 |

观察时同时改变视角或主光方向。若高光不明显，先检查 LightMap.B 是否接近黑色，再检查 Intensity、Shininess 和光向。强度和集中程度分别调节，不要只通过增大 Shininess 试图提亮。

## 四 脸部 SDF 阴影

脸部材质使用 `Myshader/face`。主要输入是 Base Map、SDF Map、Shadow Mask 和 Shadow Color。

1. 确认脸部材质使用脸部 Shader，并开启 Use SDF Shadow。
2. 确认 SDF Map 和 Shadow Mask 正确绑定，保持数据贴图的导入设置。
3. 检查场景中设置脸部方向的组件，Head、HeadForward、HeadRight、HeadUp 和 FaceMaterial 引用完整。
4. HeadForward 应指向脸部前方，HeadRight 指向角色自身右方，HeadUp 指向头顶；辅助点方向由相对 Head 的位置决定，不能只凭对象名字判断。
5. 转动角色或头部，再转动主光，检查阴影是否随相对方向变化。

当前暗部使用 `baseMap.rgb * _ShadowColor.rgb`。如果希望阴影明显暗于亮部，将 Shadow Color 的 RGB 设为小于 1 的值，例如从 `(0.6, 0.5, 0.5)` 开始调整。避免给暗部额外加一个正数后反而比亮部更亮。

如果怀疑明暗反向，临时显示 `sdf.xxx`：白色表示算法认为的亮部，黑色表示暗部。先分清是遮罩/头部方向反向，还是最终暗部颜色设置过亮，再改公式。

## 五 法线外扩描边

### 总开关

打开 PC_Renderer，在 `NPROutlineRendererFeature` 中勾选或取消 `Enable Outline`。

该功能筛选的是 Shader 中 `LightMode = NPROutline` 的 Pass，不需要为角色单独设置描边 Layer。当前筛选不透明队列；未提供该 Pass 的材质不会自动获得描边。

### 单材质参数

在使用身体 Shader 的材质 `Outline` 区域调整：

- Outline Color：描边颜色。
- Outline Width：世界空间外扩距离，默认起点约为 `0.003`。
- Width 设为 0 时，该材质的描边片元被关闭。

当前是世界空间宽度，所以远处会变细、近处会变粗。它不是固定像素宽度版本。硬法线接缝、薄片和重叠表面可能出现裂缝或黑块，先减少宽度观察。

描边在天空盒之后执行，Shader 使用 Cull Front、ZWrite Off 和 ZTest LEqual。若自行为脸部或其他材质增加同名 Pass，应保持 C# 中的深度附件声明与 Shader 实际深度写入行为一致。

## 六 相机运动模糊

### 入口与参数

打开 PC_Renderer 中的 `NPR Motion Blur`，对应脚本为 [NPRMotionBlurRendererFeature.cs](Assets/NPRMotionBlurRendererFeature.cs)。

| 参数 | 当前初始值 | 调整方式 |
| --- | --- | --- |
| Enable Blur | 开 | 整体开启/关闭 |
| Blur Shader | Hidden/NPR/MotionBlur | 应绑定 MotionBlur.shader |
| Intensity | 1 | 增大后拖影更强，0 时没有模糊贡献 |
| Shutter Seconds | 0.0333 | 曝光时间；增大后轨迹更长 |
| Max Blur Length | 0.05 | 最大 UV 轨迹长度，防止过长拖影 |
| Sample Count | 8 | 采样数，可在 4—16 之间调整 |

建议先以默认参数移动视角，并切换 Enable Blur 对照。若太弱，将 Shutter Seconds 调至 `0.05` 左右观察；若过强，先降低曝光时间或 Intensity，再调整最大长度。

采样数主要影响轨迹的平滑程度与成本，不是模糊强度开关。不要单纯把采样数加大来追求更长拖影。

### 当前行为范围

- 支持 Game 相机和 Scene View，相机移动、旋转时产生效果。
- 未 Play 的 Scene View 也执行；每台相机独立保存上次 VP 与实际渲染时间。
- 不处理 Preview 和 Reflection 相机。
- 当前 C# 没有将相机的 Post Processing 开关作为硬性启用条件，自定义模糊是否执行看 Feature 与相机类型。
- 使用相机运动重投影，不支持相机静止时角色独立移动、转身和骨骼动画产生的物体运动模糊。
- 天空没有有效表面深度时保留原色，透明表面也不能保证获得正确的自身深度和速度。
- 当前是简化历史：只有首帧初始化与停用清理，没有分辨率变化、跳切、大位移、大旋转等重置逻辑；突然切镜头可能出现被最大长度限制过的拖影。

## 七 自动接线和验证菜单

Unity 顶部 `NPR` 菜单提供：

| 菜单项 | 用途 |
| --- | --- |
| Setup Motion Blur | 将模糊 Feature 接到 PC_Renderer，绑定配套 Shader 并开启 |
| Validate Motion Blur | 检查相机筛选、Shader 编译，以及 GPU 静止—运动—静止图像行为 |
| Validate Scene View Blur | 检查 Scene 相机是否实际登记了模糊 Pass |

使用步骤：

1. 如果 Renderer 中缺少模糊功能，执行 Setup Motion Blur。
2. 执行 Validate Motion Blur，在 Console 中查看 `NPR motion blur validation PASS`。
3. 打开并显示 Scene 窗口，轻微移动视角使其重绘，再执行 Validate Scene View Blur。
4. 验证结果保存在忽略目录 `Temp/NPRMotionBlur/`。它不是提交到 Git 的项目资源，重新打开 Unity 后可能需要重新运行验证。

自动图像检查只能证明基础算法与接线行为，不代表完成了美术验收、目标平台性能测试或所有边界场景验证。

## 八 常见问题

| 现象 | 优先检查 |
| --- | --- |
| Game 窗口看不到角色 | Main Camera 是否对准角色、裁剪面是否合适，必要时 Align With View |
| 模型粉色或 Shader 无法选择 | Console 编译错误、URP 包是否导入、是否使用正确渲染管线 |
| 模型或贴图缺失 | Git LFS 是否下载完成，材质与纹理引用是否完整 |
| 所有 Renderer Feature 都没效果 | 实际质量档是否用了另一个 RP Asset/Renderer |
| 描边不显示 | Feature 开关、材质是否有对应 LightMode Pass、Width 是否为 0、是否为不透明队列 |
| 描边太粗或出现黑块 | 减小 Width，检查硬法线、薄片和重叠网格 |
| 边缘光像覆盖整张脸/身体 | 增大 Rim Power，降低 Intensity |
| 高光没有变化 | 检查 B 通道、光向、视角、强度与高光指数 |
| 脸部正面反而更暗 | 检查暗部颜色、HeadForward 方向，再显示黑白 SDF 遮罩判断 |
| 模糊完全不明显 | 确认移动的是产生当前画面的相机；检查 Feature、Shader 引用、曝光和最大长度 |
| 只旋转角色没有模糊 | 这是当前相机运动方案的范围，不能靠提高采样数补出物体速度 |
| Scene View 验证没有记录 | 显示 Scene 窗口并重绘，确认使用 PC Renderer 后重试 |
| 亮部发白但没有光晕 | HDR 数值不自动产生 Bloom；当前材质效果与 Bloom 是不同功能 |

## 九 演示与保存

推荐演示顺序：基础 Ramp → 脸部随光变化 → 单独关闭/恢复边缘光与高光 → 开关描边 → 移动相机对比模糊。

调好效果后保存场景及相关资产，在 Git 中检查 `.mat`、`.unity`、Renderer `.asset` 与 Shader/脚本的改动。新脚本和 Shader 的 `.meta` 需要一并保存，避免其他机器丢失引用。

本说明描述的是基础学习版本。真实 GPU 耗时、移动端表现、复杂透明、XR 和完整 TAA 配合尚需专项验证，展示时应说明使用的环境和已知范围。
