RainbowKeyboard Theme/Candidate V1.1 compile fix

Fix:
- Removed unused RKRGB() helper from RKThemeEngine.m.
- This fixes clang -Werror -Wunused-function reported by Theos.

Replace only:
RKThemeEngine.m

Path:
Your RainbowKeyboard project root/RKThemeEngine.m

Do not replace Tweak.xm, RainbowEffectView.m, RKNeonPress.m, or any plist for this compile fix.
