# RainbowKeyboard Performance V1

基于 `houxuan-main-samsung171-source` 原始工程制作的轻量性能补丁。

## 这版只改 3 个文件

把以下文件覆盖到原工程对应位置：

- `Tweak.xm`
- `RainbowEffectView.m`
- `RKNeonPress.m`

不需要替换设置界面、plist、Makefile 或其它文件。

## V1 优化内容

1. **不再每次按键调用 `reloadConfiguration`**
   - 配置继续由现有 `RKReadEffectivePreferences()` 负责缓存。
   - 光效视图只在 App 激活或 `com.minis.rainbowkeyboard.changed` 设置通知到达时刷新配置。

2. **缓存键盘几何数据**
   - `RKKeyboardKeyFacePath()` 生成的 key face path 缓存。
   - key center 缓存。
   - 键盘 gutter mask 的路径缓存。
   - 只有键盘几何/尺寸变化时重新生成。

3. **输入事件与光效初始化解耦**
   - UIKit 完成当前 touch 事件后，再在下一次主 RunLoop 创建光效 layer。
   - 目的是减少光效 path/layer 创建对实际输入事件的阻塞。

4. **Neon 按键前景图缓存**
   - 避免每一次重复按同一个键都重新执行 `drawViewHierarchyInRect` + 像素扫描。
   - 使用弱引用 key view 的小型缓存，单键最多保留 4 个视觉状态。

## 预期效果

主要针对：

- 连续快速输入时的轻微拖拍
- Neon 模式首帧延迟
- Ripple 模式重复构造 key path / mask
- 光效初始化对 UIKit touch 事件的影响

本补丁没有删除任何设置项，也没有主动降低默认光效强度、颜色或动画参数。

## 测试建议

安装后先不要修改其它参数，保持当前配置，连续快速输入：

`aaaaaaaaaaaaaaaaaaaaaaaa`

然后测试：

- 普通 Ripple
- Neon
- Rainbow/扩散模式
- 中英文切换
- 删除键快速连按
- 横竖屏切换后继续输入

如果 V1 仍有明显拖拍，再做 V1.1，重点会转向减少 Ripple 每次创建的 CALayer 数量，而不是继续降低动画速度。
