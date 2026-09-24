RainbowKeyboard Theme + Candidate Gradient V1.1 (Corrected)

这版基于已验证的轻量设置版与 Performance V1。

修复：
1. 恢复轻量版首页，不再使用旧的复杂首页。
2. 候选栏继续使用 RKReadEffectivePreferences，保留原有跨进程/沙盒传输，因此原来的静态渐变不会丢。
3. 在原有 CandidateStart/CandidateEnd 渐变基础上新增：静态、流动、呼吸、彩虹、跟随输入。
4. 主题只覆盖键盘光效参数，不覆盖候选栏颜色，因此两套系统独立。
5. 动态候选栏使用单个 30 FPS CADisplayLink，候选栏没有动态模式时不运行。

替换/新增路径以本包目录为准。不要删除你工程里其他原文件。
