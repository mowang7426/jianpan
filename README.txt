RainbowKeyboard Performance V1 - direct replacement files

These files match the paths in the original houxuan-main-samsung171-source.tar.gz:

1. Tweak.xm -> replace original ./Tweak.xm
2. RainbowEffectView.m -> replace original ./RainbowEffectView.m
3. RKNeonPress.m -> replace original ./RKNeonPress.m

Do NOT create or look for a RainbowKeyboard folder or patches folder.
Do NOT replace RKBRootListController.m or any plist for this performance test.

This version targets the input/ripple path: avoids per-key preference reloads,
caches keyboard geometry paths, and caches expensive Neon foreground extraction.
