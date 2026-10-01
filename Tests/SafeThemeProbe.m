#import <Foundation/Foundation.h>
#import "../RKThemeEngine.h"
#import "../RKBuildConfiguration.h"
#include <stdlib.h>

static void Require(BOOL ok, NSString *label) {
    if (!ok) { fprintf(stderr, "FAIL: %s\n", label.UTF8String); exit(1); }
}
int main(void) {
    @autoreleasepool {
        Require(RK_SAFE_TEST_BUILD == 1, @"safe mode must be selected");
        for (NSInteger theme = 1; theme <= 8; theme++) {
            for (NSNumber *enabled in @[@NO, @YES]) {
                NSDictionary *saved = @{@"NativeTheme":@(theme), @"WeChatTheme":@(theme),
                    @"Theme":@0, @"Enabled":enabled, @"NativeKeyboard":enabled,
                    @"WeChatKeyboard":enabled, @"RippleEnabled":enabled,
                    @"CandidateGradient":enabled, @"CandidateNative":enabled, @"CandidateWeType":enabled,
                    @"CandidateStart":@[@.17,@.6,@.23], @"CandidateEnd":@[@.7,@.2,@.5],
                    @"Opacity":@.37, @"Brightness":@.48, @"Duration":@.44,
                    @"PressColorMode":@1, @"PressColor":@[@.1,@.2,@.9]};
                NSDictionary *merged = RKThemeMergedPreferences(saved);
                Require([merged isEqual:saved], @"inactive keycap theme changed saved effect/candidate values");
                Require([RKThemePreferencesForAppearance(merged, YES) isEqual:saved], @"dark appearance override");
                Require([RKThemePreferencesForAppearance(merged, NO) isEqual:saved], @"light appearance override");
                Require([saved[@"NativeTheme"] integerValue] == theme, @"saved keycap choice lost");
            }
        }
        NSDictionary *result = RKThemeMergedPreferences(@{@"Theme":@1, @"NativeTheme":@8, @"WeChatTheme":@8});
        Require([result[@"Brightness"] isEqual:RKThemeDefinition(1)[@"Brightness"]], @"normal glow theme lost");
        printf("PASS safe theme: %s (all 8 keycap themes, on/off, light/dark, saved choices preserved)\n",
            NSBundle.mainBundle.bundleIdentifier.UTF8String);
    }
    return 0;
}
