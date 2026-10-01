#import "RKThemeEngine.h"
#import "RKBuildConfiguration.h"
static NSDictionary *RKTheme(NSString *name, CGFloat sat, CGFloat bright, CGFloat opacity, CGFloat spread, CGFloat softness, CGFloat core, CGFloat bgStrength, CGFloat bgRadius, CGFloat bgBand, NSInteger colorMode, CGFloat hue) {
    return @{@"name":name, @"NeonSaturation":@(sat), @"Brightness":@(bright), @"Opacity":@(opacity),
             @"Spread":@(spread), @"Softness":@(softness), @"CoreStrength":@(core), @"BackgroundStrength":@(bgStrength),
             @"BackgroundRadius":@(bgRadius), @"BackgroundBand":@(bgBand), @"ColorMode":@(colorMode), @"Hue":@(hue)};
}
static NSDictionary *RKWeChatKeycapTheme(NSString *name, NSArray *background, NSArray *keycap,
                                         NSArray *text, NSArray *pressed, NSArray *candidateStart,
                                         NSArray *candidateEnd) {
    return @{@"name":name, @"KeyboardBackgroundColor":background, @"KeycapColor":keycap,
             @"KeycapTextColor":text, @"KeycapPressedColor":pressed,
             @"CandidateStart":candidateStart, @"CandidateEnd":candidateEnd,
             @"CandidateGradient":@NO, @"CandidateWeType":@NO,
             @"PressColor":candidateStart, @"PressColorMode":@1,
             @"PureBlackKeyboard":@YES, @"WeChatKeyboard":@YES};
}
NSDictionary *RKWeChatKeycapThemeDefinition(NSInteger theme) {
    switch (theme) {
        case 1: return RKWeChatKeycapTheme(@"天空主题", @[@.16,@.55,@.90], @[@.98,@.99,@.99],
            @[@.05,@.16,@.30], @[@.55,@.82,@.98], @[@.06,@.48,@.92], @[@.24,@.78,@.98]);
        case 2: return RKWeChatKeycapTheme(@"薄荷清风", @[@.10,@.48,@.42], @[@.93,@.99,@.96],
            @[@.04,@.20,@.17], @[@.52,@.86,@.76], @[@.05,@.52,@.46], @[@.18,@.78,@.64]);
        case 3: return RKWeChatKeycapTheme(@"日落珊瑚", @[@.76,@.28,@.20], @[@.99,@.94,@.88],
            @[@.28,@.10,@.08], @[@.96,@.56,@.32], @[@.86,@.22,@.12], @[@.98,@.62,@.22]);
        case 4: return RKWeChatKeycapTheme(@"黑曜深海", @[@.04,@.11,@.17], @[@.12,@.21,@.29],
            @[@.82,@.93,@.98], @[@.20,@.43,@.58], @[@.08,@.62,@.86], @[@.22,@.86,@.98]);
        case 5: return RKWeChatKeycapTheme(@"奶油珊瑚", @[@.94,@.72,@.58], @[@.99,@.91,@.80],
            @[@.30,@.12,@.08], @[@.98,@.62,@.42], @[@.88,@.28,@.18], @[@.98,@.56,@.32]);
        case 6: return RKWeChatKeycapTheme(@"黑白红", @[@.10,@.10,@.11], @[@.94,@.94,@.92],
            @[@.08,@.08,@.09], @[@.88,@.18,@.16], @[@.78,@.06,@.06], @[@.98,@.30,@.22]);
        case 7: return RKWeChatKeycapTheme(@"森林翡翠", @[@.10,@.26,@.20], @[@.89,@.96,@.88],
            @[@.06,@.18,@.12], @[@.42,@.72,@.48], @[@.10,@.50,@.30], @[@.42,@.82,@.50]);
        case 8: return RKWeChatKeycapTheme(@"哆啦A梦", @[@.12,@.48,@.78], @[@.93,@.97,@.98],
            @[@.03,@.20,@.38], @[@.56,@.80,@.96], @[@.02,@.42,@.86], @[@.18,@.70,@.98]);
        default: return @{@"name":@"关闭"};
    }
}
static BOOL RKKeycapThemeIsWeTypeProcess(void) {
    return [NSBundle.mainBundle.bundleIdentifier.lowercaseString containsString:@"wetype"];
}
static NSInteger RKActiveKeycapTheme(NSDictionary *preferences) {
#if RK_SAFE_TEST_BUILD
    return 0; // Keep saved choices, but inactive keycap themes must not recolor candidates.
#endif
    NSString *key = RKKeycapThemeIsWeTypeProcess() ? @"WeChatTheme" : @"NativeTheme";
    return [preferences[key] integerValue];
}
static void RKApplyNativeKeycapTheme(NSMutableDictionary *merged, NSInteger theme) {
    NSDictionary *keycap = RKWeChatKeycapThemeDefinition(theme);
    for (NSString *key in @[@"KeyboardBackgroundColor", @"KeycapColor", @"KeycapTextColor",
                            @"KeycapPressedColor", @"CandidateStart", @"CandidateEnd",
                            @"PressColor", @"PressColorMode"]) {
        if (keycap[key]) merged[key] = keycap[key];
    }
    merged[@"PureBlackKeyboard"] = @YES;
    merged[@"NativeKeyboard"] = @YES;
}
NSDictionary *RKThemePreferencesForAppearance(NSDictionary *preferences, BOOL darkMode) {
    NSMutableDictionary *result = [preferences mutableCopy] ?: [NSMutableDictionary dictionary];
    NSInteger theme = RKActiveKeycapTheme(result);
    if (!darkMode || theme < 1 || theme > 8) return result;

    NSArray *backgrounds = @[@[@.025,@.065,@.13], @[@.025,@.10,@.09], @[@.14,@.045,@.035], @[@.015,@.045,@.075], @[@.16,@.075,@.045], @[@.025,@.025,@.03], @[@.025,@.09,@.065], @[@.025,@.10,@.20]];
    NSArray *keycaps = @[@[@.11,@.22,@.36], @[@.10,@.27,@.23], @[@.36,@.16,@.12], @[@.08,@.20,@.29], @[@.34,@.18,@.12], @[@.16,@.16,@.18], @[@.10,@.25,@.18], @[@.10,@.25,@.42]];
    NSArray *texts = @[@[@.92,@.97,@1.0], @[@.90,@.98,@.94], @[@1.0,@.91,@.84], @[@.86,@.95,@1.0], @[@1.0,@.94,@.88], @[@.98,@.98,@.98], @[@.90,@1.0,@.93], @[@.92,@.98,@1.0]];
    NSArray *pressed = @[@[@.19,@.40,@.63], @[@.17,@.47,@.39], @[@.63,@.28,@.17], @[@.12,@.40,@.58], @[@.72,@.32,@.20], @[@.70,@.10,@.10], @[@.16,@.46,@.30], @[@.20,@.50,@.78]];
    NSArray *candidateStart = @[@[@.55,@.85,@1.0], @[@.52,@.96,@.80], @[@1.0,@.75,@.54], @[@.12,@.68,@.94], @[@1.0,@.48,@.28], @[@.95,@.12,@.12], @[@.24,@.78,@.44], @[@.08,@.52,@1.0]];
    NSArray *candidateEnd = @[@[@.84,@.94,@1.0], @[@.79,@1.0,@.88], @[@1.0,@.90,@.77], @[@.36,@.88,@1.0], @[@1.0,@.82,@.56], @[@1.0,@.42,@.28], @[@.54,@.96,@.62], @[@.32,@.82,@1.0]];
    NSUInteger index = (NSUInteger)(theme - 1);
    result[@"KeyboardBackgroundColor"] = backgrounds[index];
    result[@"KeycapColor"] = keycaps[index];
    result[@"KeycapTextColor"] = texts[index];
    result[@"KeycapPressedColor"] = pressed[index];
    result[@"CandidateStart"] = candidateStart[index];
    result[@"CandidateEnd"] = candidateEnd[index];
    if (RKKeycapThemeIsWeTypeProcess()) {
        result[@"CandidateGradient"] = @YES;
        result[@"CandidateWeType"] = @YES;
    }
    return result;
}
NSDictionary *RKThemeDefinition(NSInteger theme) {
    NSDictionary *definition;
    switch (theme) {
        case 1: definition = RKTheme(@"深空", .88,.95,.68,2.0,8,.50,.18,180,.55,1,.63); break;
        case 2: definition = RKTheme(@"极夜紫", .92,1,.68,2.0,8,.52,.20,185,.55,1,.78); break;
        case 3: definition = RKTheme(@"赛博蓝", .90,1,.70,1.9,7,.55,.20,180,.50,1,.55); break;
        case 4: definition = RKTheme(@"赤焰", .94,1,.72,1.8,7,.58,.20,175,.52,1,.03); break;
        case 5: definition = RKTheme(@"极光", .90,1,.66,2.1,9,.50,.18,190,.58,1,.42); break;
        case 6: definition = RKTheme(@"Rainbow", 1,1,.68,2.2,8,.55,.20,195,.58,0,.0); break;
        case 7: definition = RKTheme(@"冰晶", .48,1,.62,1.8,10,.46,.16,175,.50,1,.52); break;
        case 8: definition = RKTheme(@"Neon", 1,1,.72,2.2,7,.62,.22,195,.60,1,.82); break;
        case 9: definition = RKTheme(@"Cyberpunk", 1,1,.74,2.3,6,.62,.23,200,.62,1,.90); break;
        case 10: definition = RKTheme(@"微信·墨夜", .90,.88,.64,1.7,9,.42,.12,155,.48,1,.55); break;
        case 11: definition = RKTheme(@"微信·深海", .82,.92,.60,1.6,10,.38,.10,145,.44,1,.52); break;
        case 12: definition = RKTheme(@"微信·樱粉", .78,.94,.60,1.5,10,.36,.10,140,.42,1,.90); break;
        case 13: definition = RKTheme(@"微信·极简", .35,.82,.38,1.0,12,.20,.04,110,.30,1,.58); break;
        default: definition = @{@"name":@"自定义"}; break;
    }
    if (theme >= 10 && theme <= 13) {
        NSMutableDictionary *preset = [definition mutableCopy];
        preset[@"WeChatOnly"] = @YES;
        preset[@"KeyboardBackgroundColor"] = @[@0.015, @0.02, @0.03];
        preset[@"KeycapColor"] = @[@0.06, @0.08, @0.11];
        preset[@"CandidateStart"] = @[@0.10, @0.80, @1.0];
        preset[@"CandidateEnd"] = @[@0.75, @0.30, @1.0];
        preset[@"PressColor"] = @[@0.10, @0.75, @1.0];
        if (theme == 11) {
            preset[@"KeyboardBackgroundColor"] = @[@0.01, @0.05, @0.09];
            preset[@"KeycapColor"] = @[@0.03, @0.15, @0.22];
            preset[@"CandidateStart"] = @[@0.05, @0.75, @0.95];
            preset[@"CandidateEnd"] = @[@0.15, @0.45, @1.0];
        } else if (theme == 12) {
            preset[@"KeyboardBackgroundColor"] = @[@0.07, @0.025, @0.10];
            preset[@"KeycapColor"] = @[@0.18, @0.06, @0.22];
            preset[@"CandidateStart"] = @[@1.0, @0.35, @0.70];
            preset[@"CandidateEnd"] = @[@0.50, @0.35, @1.0];
            preset[@"PressColor"] = @[@1.0, @0.25, @0.60];
        } else if (theme == 13) {
            preset[@"KeyboardBackgroundColor"] = @[@0.92, @0.94, @0.97];
            preset[@"KeycapColor"] = @[@0.78, @0.82, @0.88];
            preset[@"CandidateStart"] = @[@0.05, @0.40, @0.85];
            preset[@"CandidateEnd"] = @[@0.10, @0.65, @0.70];
            preset[@"PressColor"] = @[@0.05, @0.45, @0.85];
            preset[@"BackgroundFeedback"] = @NO;
            preset[@"AmbientGlow"] = @NO;
            preset[@"MaxEffects"] = @2;
        }
        return preset;
    }
    return definition;
}
NSString *RKThemeDisplayName(NSInteger theme) { return RKThemeDefinition(theme)[@"name"] ?: @"自定义"; }
NSDictionary *RKThemeMergedPreferences(NSDictionary *preferences) {
    NSMutableDictionary *merged = [preferences mutableCopy] ?: [NSMutableDictionary dictionary];
    BOOL wetype = RKKeycapThemeIsWeTypeProcess();
    NSInteger weChatTheme = [preferences[@"WeChatTheme"] integerValue];
    NSInteger nativeTheme = [preferences[@"NativeTheme"] integerValue];
#if RK_SAFE_TEST_BUILD
    // Preserve disk settings for a future full build. Only stop inactive keycap
    // themes forcing CandidateGradient/keyboard flags and press colors at read time.
    weChatTheme = nativeTheme = 0;
#endif
    if (wetype && weChatTheme > 0 && weChatTheme <= 8) {
        NSDictionary *keycap = RKWeChatKeycapThemeDefinition(weChatTheme);
        [keycap enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
            if (![key isEqualToString:@"name"]) merged[key] = value;
        }];
    }
    NSInteger theme = [preferences[@"Theme"] integerValue];
    if (theme > 0) {
        NSDictionary *definition = RKThemeDefinition(theme);
        if (![definition[@"WeChatOnly"] boolValue] || wetype) {
            [definition enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
                if (![key isEqualToString:@"name"]) merged[key] = value;
            }];
        }
    }
    if (wetype && weChatTheme > 0 && weChatTheme <= 8) {
        NSDictionary *keycap = RKWeChatKeycapThemeDefinition(weChatTheme);
        [keycap enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
            if (![key isEqualToString:@"name"]) merged[key] = value;
        }];
    } else if (!wetype && nativeTheme > 0 && nativeTheme <= 8) {
        RKApplyNativeKeycapTheme(merged, nativeTheme);
    }
    return merged;
}
