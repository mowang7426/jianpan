#import "RKThemeEngine.h"
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
             @"PressColor":candidateStart, @"PressColorMode":@1,
             @"PureBlackKeyboard":@YES, @"WeChatKeyboard":@YES};
}
NSDictionary *RKWeChatKeycapThemeDefinition(NSInteger theme) {
    switch (theme) {
        case 1: return RKWeChatKeycapTheme(@"天空蓝", @[@.35,@.65,@.92], @[@.92,@.96,@.99],
            @[@.15,@.25,@.40], @[@.75,@.88,@.95], @[@.10,@.65,@.95], @[@.25,@.85,@.95]);
        case 2: return RKWeChatKeycapTheme(@"极简白", @[@.94,@.94,@.95], @[@.98,@.98,@.98],
            @[@.20,@.20,@.22], @[@.88,@.88,@.89], @[@.05,@.40,@.85], @[@.10,@.65,@.70]);
        case 3: return RKWeChatKeycapTheme(@"樱粉紫", @[@.11,@.04,@.16], @[@.28,@.10,@.32],
            @[@.98,@.88,@.98], @[@.50,@.18,@.58], @[@.98,@.30,@.70], @[@.55,@.30,@.98]);
        default: return @{@"name":@"关闭"};
    }
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
    NSInteger weChatTheme = [preferences[@"WeChatTheme"] integerValue];
    if (weChatTheme > 0 && [NSBundle.mainBundle.bundleIdentifier.lowercaseString containsString:@"wetype"]) {
        NSDictionary *keycap = RKWeChatKeycapThemeDefinition(weChatTheme);
        [keycap enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
            if (![key isEqualToString:@"name"]) merged[key] = value;
        }];
    }
    NSInteger theme = [preferences[@"Theme"] integerValue];
    if (theme > 0) {
        NSDictionary *definition = RKThemeDefinition(theme);
        if ([definition[@"WeChatOnly"] boolValue] &&
            ![NSBundle.mainBundle.bundleIdentifier.lowercaseString containsString:@"wetype"]) return preferences;
        [definition enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
            if (![key isEqualToString:@"name"]) merged[key] = value;
        }];
    }
    if (weChatTheme > 0 && [NSBundle.mainBundle.bundleIdentifier.lowercaseString containsString:@"wetype"]) {
        NSDictionary *keycap = RKWeChatKeycapThemeDefinition(weChatTheme);
        [keycap enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
            if (![key isEqualToString:@"name"]) merged[key] = value;
        }];
    }
    return merged;
}
