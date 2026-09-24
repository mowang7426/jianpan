# RainbowKeyboard Theme + Candidate Gradient Engine V1

基于 `houxuan-main-samsung171-source.tar.gz` 原工程制作。

## 这版做什么

### 1. 主题系统
新增 9 个内置主题：
- 深空
- 极夜紫
- 赛博蓝
- 赤焰
- 极光
- Rainbow
- 冰晶
- Neon
- Cyberpunk

主题主要控制键盘光效的色相、饱和度、亮度、扩散、柔化、核心强度和背景色带参数。

选择“自定义”后恢复手动参数逻辑。

### 2. 候选栏独立动态渐变
新增模式：
- 关闭
- 静态渐变
- 流动渐变
- 呼吸渐变
- 彩虹渐变
- 跟随输入

新增：
- 动画速度
- 渐变强度

候选栏仍然独立使用 `CandidateStart` / `CandidateEnd`，键盘主题不会覆盖这两个颜色。

动态模式使用单个 CADisplayLink，默认 30 FPS，并且只有候选视图实际出现后才启动，候选栏消失后自动停止。

## 文件替换
请严格按原工程路径替换：

### 根目录替换
- `Makefile`
- `RainbowEffectView.m`
- `CandidateGradient.xm`
- `defaults.plist`

### 根目录新增
- `RKThemeEngine.h`
- `RKThemeEngine.m`

### PreferenceBundle 替换
- `RainbowKeyboardPrefs/RKBRootListController.m`
- `RainbowKeyboardPrefs/Resources/RainbowKeyboard.plist`

## 注意

本补丁没有修改 `Tweak.xm`、`RKNeonPress.m` 和 Performance V1 的其它文件，方便与已经测试通过的 Performance V1 继续叠加。

如果你当前源码已经应用过 Performance V1，请不要用旧工程重新覆盖这几个性能文件；只按上面的路径替换/新增即可。

编译方式仍然使用你原来的 Theos 工程。
