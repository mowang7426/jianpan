#import "RKThemeEngine.h"

static NSArray *RKRGB(CGFloat r, CGFloat g, CGFloat b) { return @[@(r), @(g), @(b)]; }
static NSDictionary *RKTheme(NSString *name, NSArray *start, NSArray *end, CGFloat sat, CGFloat bright, CGFloat opacity, CGFloat spread, CGFloat softness, CGFloat core, CGFloat bgStrength, CGFloat bgRadius, CGFloat bgBand, NSInteger colorMode, CGFloat hue) {
    return @{@"name":name, @"CandidateStart":start, @"CandidateEnd":end,
             @"NeonSaturation":@(sat), @"Brightness":@(bright), @"Opacity":@(opacity),
             @"Spread":@(spread), @"Softness":@(softness), @"CoreStrength":@(core),
             @"BackgroundStrength":@(bgStrength), @"BackgroundRadius":@(bgRadius), @"BackgroundBand":@(bgBand),
             @"ColorMode":@(colorMode), @"Hue":@(hue)};
}

NSDictionary *RKThemeDefinition(NSInteger theme) {
    switch (theme) {
        case 1: return RKTheme(@"深空", RKRGB(.05,.35,1), RKRGB(.55,.08,1), .88,.95,.68,2.0,8,.5,.18,180,.55,1,.63);
        case 2: return RKTheme(@"极夜紫", RKRGB(.42,.08,1), RKRGB(.9,.08,.75), .92,1,.68,2.0,8,.52,.2,185,.55,1,.78);
        case 3: return RKTheme(@"赛博蓝", RKRGB(.02,.55,1), RKRGB(.08,.9,1), .9,1,.7,1.9,7,.55,.2,180,.5,1,.55);
        case 4: return RKTheme(@"赤焰", RKRGB(1,.08,.03), RKRGB(1,.42,.02), .94,1,.72,1.8,7,.58,.2,175,.52,1,.03);
        case 5: return RKTheme(@"极光", RKRGB(.05,1,.55), RKRGB(.1,.35,1), .9,1,.66,2.1,9,.5,.18,190,.58,1,.42);
        case 6: return RKTheme(@"Rainbow", RKRGB(1,.08,.45), RKRGB(.1,.8,1), 1,1,.68,2.2,8,.55,.2,195,.58,0,.0);
        case 7: return RKTheme(@"冰晶", RKRGB(.55,.9,1), RKRGB(.2,.45,1), .48,1,.62,1.8,10,.46,.16,175,.5,1,.52);
        case 8: return RKTheme(@"Neon", RKRGB(.8,.05,1), RKRGB(.05,1,.85), 1,1,.72,2.2,7,.62,.22,195,.6,1,.82);
        case 9: return RKTheme(@"Cyberpunk", RKRGB(1,.05,.35), RKRGB(.45,.05,1), 1,1,.74,2.3,6,.62,.23,200,.62,1,.9);
        default: return @{@"name":@"自定义"};
    }
}
NSString *RKThemeDisplayName(NSInteger theme) { return RKThemeDefinition(theme)[@"name"] ?: @"自定义"; }
NSDictionary *RKThemeMergedPreferences(NSDictionary *preferences) {
    NSInteger theme = [preferences[@"Theme"] integerValue];
    if (theme <= 0) return preferences;
    NSMutableDictionary *merged = [preferences mutableCopy];
    NSDictionary *definition = RKThemeDefinition(theme);
    [definition enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        if (![key isEqualToString:@"name"]) merged[key] = value;
    }];
    // A theme supplies keyboard colors, but the candidate engine stays independent.
    merged[@"BackgroundFeedback"] = @YES;
    return merged;
}
