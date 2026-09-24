#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "../RKBlackProbe.h"
#import "../RKPreferences.h"

static NSString * const kRKChangedNotification = @"com.minis.rainbowkeyboard.changed";

static NSDictionary *RKReadPreferences(void) {
    return RKReadStoredPreferences() ?: @{};
}

static void RKSaveAndNotify(NSMutableDictionary *values) {
    if (!values) return;
    uint64_t revision = RKPreferencesRevision(values) + 1;
    values[@"RKSettingsRevision"] = @(revision);
    if (!RKSavePreferences(values)) return;
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                          (__bridge CFStringRef)kRKChangedNotification,
                                          NULL, NULL, YES);
}

static void RKApplyPerformancePreset(NSMutableDictionary *values, NSInteger mode) {
    NSArray *profiles = @[
        // 省电
        @{@"Opacity":@0.42, @"Brightness":@0.80, @"Duration":@0.42,
          @"Spread":@1.50, @"Softness":@10, @"CoreStrength":@0.32,
          @"MaxEffects":@2, @"BackgroundFeedback":@NO, @"AmbientGlow":@NO,
          @"BackgroundStrength":@0.10},
        // 平衡
        @{@"Opacity":@0.65, @"Brightness":@0.95, @"Duration":@0.55,
          @"Spread":@2.00, @"Softness":@8, @"CoreStrength":@0.50,
          @"MaxEffects":@4, @"BackgroundFeedback":@YES, @"AmbientGlow":@YES,
          @"BackgroundStrength":@0.18},
        // 极致
        @{@"Opacity":@0.78, @"Brightness":@1.00, @"Duration":@0.45,
          @"Spread":@2.25, @"Softness":@7, @"CoreStrength":@0.62,
          @"MaxEffects":@6, @"BackgroundFeedback":@YES, @"AmbientGlow":@YES,
          @"BackgroundStrength":@0.24}
    ];
    if (mode >= 0 && mode < (NSInteger)profiles.count) {
        [values addEntriesFromDictionary:profiles[mode]];
        values[@"PerformanceMode"] = @(mode);
        values[@"Preset"] = @(mode);
    }
}

@interface RKBPackageInfoController : UIViewController @end

@implementation RKBPackageInfoController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"关于与诊断";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    NSData *data = [NSData dataWithContentsOfFile:[bundle pathForResource:@"PackageInfo" ofType:@"json"]];
    NSDictionary *info = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];

    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:22],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-20],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40]
    ]];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"PackageIcon" inBundle:bundle compatibleWithTraitCollection:nil]];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [icon.heightAnchor constraintEqualToConstant:76].active = YES;
    [stack addArrangedSubview:icon];

    UILabel *(^label)(NSString *, UIFontTextStyle, UIColor *) = ^UILabel *(NSString *text, UIFontTextStyle style, UIColor *color) {
        UILabel *v = [UILabel new];
        v.text = text;
        v.numberOfLines = 0;
        v.font = [UIFont preferredFontForTextStyle:style];
        v.textColor = color;
        v.adjustsFontForContentSizeCategory = YES;
        return v;
    };

    [stack addArrangedSubview:label(info[@"name"] ?: @"彩虹键盘光效", UIFontTextStyleTitle2, UIColor.labelColor)];
    [stack addArrangedSubview:label([NSString stringWithFormat:@"%@ · %@", info[@"version"] ?: @"", info[@"author"] ?: @"MoWang"], UIFontTextStyleFootnote, UIColor.secondaryLabelColor)];
    [stack addArrangedSubview:label(info[@"summary"] ?: @"轻量设置版", UIFontTextStyleBody, UIColor.labelColor)];
    [stack addArrangedSubview:label(@"首页只保留常用选项。原有细节参数仍然保留在“高级设置”中。", UIFontTextStyleFootnote, UIColor.secondaryLabelColor)];
}
@end

@interface RKBAdvancedListController : PSListController <UIColorPickerViewControllerDelegate>
@property(nonatomic, copy) NSString *editingColorKey;
@end

@interface RKBRootListController : PSListController
@end

@implementation RKBRootListController

- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"RainbowKeyboard" target:self];
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"彩虹键盘光效";
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    NSDictionary *values = RKReadPreferences();
    id value = key ? values[key] : nil;
    return value ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key || !value) return;

    NSMutableDictionary *values = [RKReadPreferences() mutableCopy] ?: [NSMutableDictionary dictionary];
    NSInteger number = [value integerValue];

    if ([key isEqualToString:@"PerformanceMode"]) {
        RKApplyPerformancePreset(values, number);
    } else if ([key isEqualToString:@"EffectStyle"] || [key isEqualToString:@"ColorMode"]) {
        values[key] = value;
        values[@"Preset"] = @(-1);
    } else if ([key isEqualToString:@"Enabled"] || [key isEqualToString:@"CandidateGradient"]) {
        values[key] = @([value boolValue]);
    } else {
        values[key] = value;
    }

    RKSaveAndNotify(values);
    [self reloadSpecifiers];
}

- (void)showAdvanced {
    RKBAdvancedListController *controller = [RKBAdvancedListController new];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)showPackageInfo {
    RKBPackageInfoController *controller = [RKBPackageInfoController new];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)resetToDefaults {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"恢复默认设置"
                                                                    message:@"只恢复彩虹键盘的设置，不会删除插件。"
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复默认" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        NSString *path = [[NSBundle bundleForClass:self.class] pathForResource:@"defaults" ofType:@"plist"];
        NSDictionary *defaults = path.length ? [NSDictionary dictionaryWithContentsOfFile:path] : nil;
        NSMutableDictionary *values = defaults ? [defaults mutableCopy] : [NSMutableDictionary dictionary];
        RKSaveAndNotify(values);
        [self reloadSpecifiers];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end

@implementation RKBAdvancedListController

- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"RainbowKeyboardAdvanced" target:self];
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"高级设置";
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    NSDictionary *values = RKReadPreferences();
    return (key ? values[key] : nil) ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key || !value) return;
    NSMutableDictionary *values = [RKReadPreferences() mutableCopy] ?: [NSMutableDictionary dictionary];
    values[key] = value;
    values[@"Preset"] = @(-1);
    RKSaveAndNotify(values);
    [self reloadSpecifiers];
}

- (void)chooseColor:(NSString *)key {
    self.editingColorKey = key;
    UIColorPickerViewController *picker = [UIColorPickerViewController new];
    picker.delegate = self;
    picker.supportsAlpha = NO;

    NSDictionary *titles = @{
        @"CandidateStart": @"候选词起始颜色",
        @"CandidateEnd": @"候选词结束颜色",
        @"KeyboardBackgroundColor": @"键盘底色",
        @"KeycapColor": @"键帽颜色",
        @"PressColor": @"单色灯光颜色"
    };
    picker.title = titles[key];

    id rgb = RKReadPreferences()[key];
    if ([rgb isKindOfClass:NSArray.class] && [rgb count] == 3) {
        picker.selectedColor = [UIColor colorWithRed:[rgb[0] doubleValue]
                                                 green:[rgb[1] doubleValue]
                                                  blue:[rgb[2] doubleValue]
                                                 alpha:1.0];
    }
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)chooseCandidateStart { [self chooseColor:@"CandidateStart"]; }
- (void)chooseCandidateEnd { [self chooseColor:@"CandidateEnd"]; }
- (void)chooseKeyboardBackground { [self chooseColor:@"KeyboardBackgroundColor"]; }
- (void)chooseKeycapColor { [self chooseColor:@"KeycapColor"]; }
- (void)choosePressColor { [self chooseColor:@"PressColor"]; }

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)picker {
    CGFloat r = 0, g = 0, b = 0, a = 1;
    if (![picker.selectedColor getRed:&r green:&g blue:&b alpha:&a]) return;

    NSString *key = self.editingColorKey;
    self.editingColorKey = nil;

    NSMutableDictionary *values = [RKReadPreferences() mutableCopy] ?: [NSMutableDictionary dictionary];
    values[key] = @[@(r), @(g), @(b)];
    values[@"Preset"] = @(-1);
    RKSaveAndNotify(values);
    [self reloadSpecifiers];
}

- (void)showPackageInfo {
    RKBPackageInfoController *controller = [RKBPackageInfoController new];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)copyBlackDiagnostic {
    NSDictionary *values = RKReadPreferences();
    NSDictionary *report = @{
        @"build": @"1.0.25~samsung17.1",
        @"systemVersion": UIDevice.currentDevice.systemVersion,
        @"preferenceSync": RKPreferencesDiagnostic(),
        @"native": RKReadBlackProbe(NO),
        @"weType": RKReadBlackProbe(YES),
        @"settings": @{
            @"revision": @(RKPreferencesRevision(values)),
            @"CandidateGradient": values[@"CandidateGradient"] ?: @YES,
            @"CandidateNative": values[@"CandidateNative"] ?: @YES,
            @"CandidateWeType": values[@"CandidateWeType"] ?: @YES
        }
    };

    NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
    if (!data) return;
    UIPasteboard.generalPasteboard.string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"诊断已复制"
                                                                     message:@"仅包含版本、接口状态和设置状态，不包含输入文字或图片。"
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
