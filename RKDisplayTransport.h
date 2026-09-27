#import <Foundation/Foundation.h>
#import <notify.h>
#include <math.h>
#include <stdint.h>
#include <string.h>

// Display preferences only. Darwin state is not an authenticated IPC channel.
enum { RKDisplayWordCount = 15 };
static inline NSArray<NSString *> *RKDisplayNumbers(void) {
    return @[@"Opacity", @"Brightness", @"NeonSaturation", @"Duration", @"Spread", @"Softness",
        @"CoreStrength", @"MaxEffects", @"AmbientStrength", @"BackgroundStrength",
        @"BackgroundDuration", @"BackgroundRadius", @"BackgroundBand", @"ColorMode",
        @"Hue", @"EffectStyle", @"Preset"];
}
static inline NSArray<NSString *> *RKDisplayFlags(void) {
    return @[@"CandidateGradient", @"CandidateNative", @"CandidateWeType", @"PureBlackKeyboard",
        @"Enabled", @"NativeKeyboard", @"WeChatKeyboard", @"RippleEnabled", @"AmbientGlow", @"BackgroundFeedback"];
}
static inline NSArray<NSString *> *RKDisplayColors(void) {
    return @[@"CandidateStart", @"CandidateEnd", @"KeyboardBackgroundColor", @"KeycapColor"];
}
static inline NSArray<NSString *> *RKDisplayKeys(void) {
    return [[[RKDisplayNumbers() arrayByAddingObjectsFromArray:RKDisplayFlags()]
        arrayByAddingObjectsFromArray:RKDisplayColors()]
        arrayByAddingObjectsFromArray:@[@"PressColorMode", @"PressBrightness", @"PressColor", @"Theme", @"WeChatTheme", @"NativeTheme", @"SmartPerformance", @"KeyboardLock"]];
}
static inline void RKEncodeDisplaySnapshot(NSDictionary *prefs, uint64_t words[RKDisplayWordCount]) {
    memset(words, 0, RKDisplayWordCount * sizeof(uint64_t));
    words[0] = [prefs[@"RKSettingsRevision"] unsignedLongLongValue];
    words[1] = UINT64_C(0xD1) << 56;
    NSArray *numbers = RKDisplayNumbers(), *flags = RKDisplayFlags(), *colors = RKDisplayColors();
    for (NSUInteger i = 0; i < numbers.count; i++) {
        id value = prefs[numbers[i]];
        if (![value isKindOfClass:NSNumber.class] || !isfinite([value doubleValue])) continue;
        float number = [value floatValue];
        if (!isfinite(number)) continue;
        uint32_t bits;
        memcpy(&bits, &number, sizeof(bits));
        words[1] |= UINT64_C(1) << i;
        words[6 + i / 2] |= (uint64_t)bits << ((i % 2) * 32);
    }
    for (NSUInteger i = 0; i < colors.count; i++) {
        id value = prefs[colors[i]];
        if (![value isKindOfClass:NSArray.class] || [value count] != 3) continue;
        BOOL valid = YES;
        uint64_t rgb = 0;
        for (NSUInteger c = 0; c < 3; c++) {
            id component = value[c];
            if (![component isKindOfClass:NSNumber.class] || !isfinite([component doubleValue])) { valid = NO; break; }
            rgb |= (uint64_t)llround(MIN(1, MAX(0, [component doubleValue])) * 65535) << (c * 16);
        }
        if (valid) {
            words[1] |= UINT64_C(1) << (17 + i);
            words[2 + i] = rgb;
        }
    }
    for (NSUInteger i = 0; i < flags.count; i++) {
        id value = prefs[flags[i]];
        if (![value isKindOfClass:NSNumber.class]) continue;
        words[1] |= UINT64_C(1) << (21 + i);
        if ([value boolValue]) words[1] |= UINT64_C(1) << (31 + i);
    }
    // Optional extension in v2's unused bits. Older clients ignore these fields.
    // Theme uses spare bits 45..49, leaving existing snapshot fields intact.
    id smart = prefs[@"SmartPerformance"];
    if ([smart isKindOfClass:NSNumber.class]) {
        words[1] |= UINT64_C(1) << 50;
        if ([smart boolValue]) words[1] |= UINT64_C(1) << 51;
    }
    id lock = prefs[@"KeyboardLock"];
    if ([lock isKindOfClass:NSNumber.class]) {
        words[1] |= UINT64_C(1) << 52;
        if ([lock boolValue]) words[1] |= UINT64_C(1) << 53;
    }
    id theme = prefs[@"Theme"];
    if ([theme isKindOfClass:NSNumber.class] && isfinite([theme doubleValue]) &&
        [theme doubleValue] == [theme integerValue] &&
        [theme integerValue] >= 0 && [theme integerValue] <= 13) {
        words[1] |= UINT64_C(1) << 45;
        words[1] |= (uint64_t)[theme integerValue] << 46;
    }
    id weChatTheme = prefs[@"WeChatTheme"];
    if ([weChatTheme isKindOfClass:NSNumber.class] && [weChatTheme integerValue] >= 0 && [weChatTheme integerValue] <= 8) {
        // Keep the legacy 2-bit field and use the unused word 5 for themes 4-8.
        words[1] |= (uint64_t)([weChatTheme integerValue] & 3) << 54;
        words[5] = (uint64_t)[weChatTheme integerValue];
    }
    id nativeTheme = prefs[@"NativeTheme"];
    if ([nativeTheme isKindOfClass:NSNumber.class] && [nativeTheme integerValue] >= 0 && [nativeTheme integerValue] <= 8)
        words[5] |= ((uint64_t)[nativeTheme integerValue] & 15) << 4;
    id mode = prefs[@"PressColorMode"];
    if ([mode isKindOfClass:NSNumber.class] && isfinite([mode doubleValue])) {
        words[1] |= UINT64_C(1) << 41;
        if ([mode integerValue] == 1) words[1] |= UINT64_C(1) << 42;
    }
    id brightness = prefs[@"PressBrightness"];
    if ([brightness isKindOfClass:NSNumber.class] && isfinite([brightness doubleValue])) {
        float value = MIN(1, MAX(0, [brightness doubleValue]));
        uint32_t bits;
        memcpy(&bits, &value, sizeof(bits));
        words[14] |= (uint64_t)bits << 32;
        words[1] |= UINT64_C(1) << 43;
    }
    id pressColor = prefs[@"PressColor"];
    if ([pressColor isKindOfClass:NSArray.class] && [pressColor count] == 3) {
        BOOL valid = YES;
        for (id component in pressColor)
            valid &= [component isKindOfClass:NSNumber.class] && isfinite([component doubleValue]);
        if (valid) {
            words[1] |= UINT64_C(1) << 44;
            for (NSUInteger c = 0; c < 3; c++)
                words[2 + c] |= (uint64_t)llround(MIN(1, MAX(0, [pressColor[c] doubleValue])) * 65535) << 48;
        }
    }
    id appearance = prefs[@"AppearanceModes"];
    if ([appearance isKindOfClass:NSNumber.class]) {
        NSInteger lightStyle = prefs[@"LightEffectStyle"] ? [prefs[@"LightEffectStyle"] integerValue] : 2;
        NSInteger darkStyle = prefs[@"DarkEffectStyle"] ? [prefs[@"DarkEffectStyle"] integerValue] : 1;
        NSInteger lightColor = prefs[@"LightColorMode"] ? [prefs[@"LightColorMode"] integerValue] : 0;
        NSInteger darkColor = prefs[@"DarkColorMode"] ? [prefs[@"DarkColorMode"] integerValue] : 0;
        NSInteger lightPress = prefs[@"LightPressColorMode"] ? [prefs[@"LightPressColorMode"] integerValue] : (lightColor == 1 ? 1 : 0);
        NSInteger darkPress = prefs[@"DarkPressColorMode"] ? [prefs[@"DarkPressColorMode"] integerValue] : (darkColor == 1 ? 1 : 0);
        uint64_t pack = 1;
        if ([appearance boolValue]) pack |= 2;
        pack |= (uint64_t)(lightStyle & 3) << 2;
        pack |= (uint64_t)(darkStyle & 3) << 4;
        pack |= (uint64_t)(lightColor & 3) << 6;
        pack |= (uint64_t)(darkColor & 3) << 8;
        pack |= (uint64_t)(lightPress & 1) << 10;
        pack |= (uint64_t)(darkPress & 1) << 11;
        if ([prefs[@"LightHue"] isKindOfClass:NSNumber.class] && isfinite([prefs[@"LightHue"] doubleValue])) {
            pack |= UINT64_C(1) << 12;
            pack |= (uint64_t)llround(MIN(1, MAX(0, [prefs[@"LightHue"] doubleValue])) * 255) << 16;
        }
        if ([prefs[@"DarkHue"] isKindOfClass:NSNumber.class] && isfinite([prefs[@"DarkHue"] doubleValue])) {
            pack |= UINT64_C(1) << 13;
            pack |= (uint64_t)llround(MIN(1, MAX(0, [prefs[@"DarkHue"] doubleValue])) * 255) << 24;
        }
        NSArray *sides = @[@"LightPressColor", @"DarkPressColor"];
        for (NSUInteger side = 0; side < sides.count; side++) {
            id rgb = prefs[sides[side]];
            if (![rgb isKindOfClass:NSArray.class] || [rgb count] != 3) continue;
            BOOL valid = YES;
            uint64_t packed = 0;
            for (NSUInteger c = 0; c < 3; c++) {
                id component = rgb[c];
                if (![component isKindOfClass:NSNumber.class] || !isfinite([component doubleValue])) { valid = NO; break; }
                packed |= (uint64_t)llround(MIN(1, MAX(0, [component doubleValue])) * 255) << ((2 - c) * 8);
            }
            if (!valid) continue;
            pack |= UINT64_C(1) << (14 + side);
            words[5] |= packed << (16 + side * 24);
        }
        words[14] |= pack;
    }
}
static inline uint64_t RKDisplayChecksum(const uint64_t words[RKDisplayWordCount]) {
    uint64_t hash = UINT64_C(14695981039346656037);
    for (NSUInteger i = 0; i < RKDisplayWordCount; i++)
        for (NSUInteger byte = 0; byte < 8; byte++) {
            hash ^= (words[i] >> (byte * 8)) & 255;
            hash *= UINT64_C(1099511628211);
        }
    // Reserve zero for absent state and UINT64_MAX for an in-progress write.
    return (hash & UINT64_C(0x7FFFFFFFFFFFFFFF)) | 1;
}
static inline NSDictionary *RKDecodeDisplaySnapshot(const uint64_t words[RKDisplayWordCount], uint64_t checksum) {
    if ((words[1] >> 56) != 0xD1 || !checksum || checksum == UINT64_MAX ||
        RKDisplayChecksum(words) != checksum) return nil;
    NSMutableDictionary *result = [@{@"RKSettingsRevision":@(words[0])} mutableCopy];
    NSArray *numbers = RKDisplayNumbers(), *flags = RKDisplayFlags(), *colors = RKDisplayColors();
    for (NSUInteger i = 0; i < numbers.count; i++) {
        if (!(words[1] & (UINT64_C(1) << i))) continue;
        uint32_t bits = (uint32_t)(words[6 + i / 2] >> ((i % 2) * 32));
        float value;
        memcpy(&value, &bits, sizeof(value));
        if (!isfinite(value)) return nil;
        result[numbers[i]] = @(value);
    }
    for (NSUInteger i = 0; i < colors.count; i++) {
        if (!(words[1] & (UINT64_C(1) << (17 + i)))) continue;
        NSMutableArray *rgb = [NSMutableArray array];
        for (NSUInteger c = 0; c < 3; c++) [rgb addObject:@(((words[2 + i] >> (c * 16)) & 65535) / 65535.0)];
        result[colors[i]] = rgb;
    }
    for (NSUInteger i = 0; i < flags.count; i++)
        if (words[1] & (UINT64_C(1) << (21 + i))) result[flags[i]] = @((words[1] >> (31 + i)) & 1);
    if (words[1] & (UINT64_C(1) << 50)) result[@"SmartPerformance"] = @((words[1] >> 51) & 1);
    if (words[1] & (UINT64_C(1) << 52)) result[@"KeyboardLock"] = @((words[1] >> 53) & 1);

    if (words[1] & (UINT64_C(1) << 45)) {
        NSUInteger theme = (words[1] >> 46) & 15;
        if (theme > 13) return nil;
        result[@"Theme"] = @(theme);
    }
    NSUInteger weChatTheme = (NSUInteger)(words[5] & 15);
    if (weChatTheme > 8) weChatTheme = (NSUInteger)((words[1] >> 54) & 3);
    result[@"WeChatTheme"] = @(weChatTheme);
    NSUInteger nativeTheme = (NSUInteger)((words[5] >> 4) & 15);
    result[@"NativeTheme"] = @(nativeTheme > 8 ? 0 : nativeTheme);
    if (words[14] & 1) {
        result[@"AppearanceModes"] = @((words[14] & 2) != 0);
        result[@"LightEffectStyle"] = @((words[14] >> 2) & 3);
        result[@"DarkEffectStyle"] = @((words[14] >> 4) & 3);
        result[@"LightColorMode"] = @((words[14] >> 6) & 3);
        result[@"DarkColorMode"] = @((words[14] >> 8) & 3);
        result[@"LightPressColorMode"] = @((words[14] >> 10) & 1);
        result[@"DarkPressColorMode"] = @((words[14] >> 11) & 1);
        if (words[14] & (UINT64_C(1) << 12)) result[@"LightHue"] = @(((words[14] >> 16) & 255) / 255.0);
        if (words[14] & (UINT64_C(1) << 13)) result[@"DarkHue"] = @(((words[14] >> 24) & 255) / 255.0);
        if (words[14] & (UINT64_C(1) << 14)) {
            uint64_t rgb = (words[5] >> 16) & 0xFFFFFF;
            result[@"LightPressColor"] = @[@(((rgb >> 16) & 255) / 255.0), @(((rgb >> 8) & 255) / 255.0), @((rgb & 255) / 255.0)];
        }
        if (words[14] & (UINT64_C(1) << 15)) {
            uint64_t rgb = (words[5] >> 40) & 0xFFFFFF;
            result[@"DarkPressColor"] = @[@(((rgb >> 16) & 255) / 255.0), @(((rgb >> 8) & 255) / 255.0), @((rgb & 255) / 255.0)];
        }
    }
    if (words[1] & (UINT64_C(1) << 41)) result[@"PressColorMode"] = @((words[1] >> 42) & 1);
    if (words[1] & (UINT64_C(1) << 43)) {
        uint32_t bits = (uint32_t)(words[14] >> 32);
        float value;
        memcpy(&value, &bits, sizeof(value));
        if (!isfinite(value) || value < 0 || value > 1) return nil;
        result[@"PressBrightness"] = @(value);
    }
    if (words[1] & (UINT64_C(1) << 44))
        result[@"PressColor"] = @[@((words[2] >> 48) / 65535.0),
            @((words[3] >> 48) / 65535.0), @((words[4] >> 48) / 65535.0)];
    return result;
}
static inline int RKDisplayToken(NSUInteger index) {
    static int tokens[RKDisplayWordCount + 1];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        for (NSUInteger i = 0; i <= RKDisplayWordCount; i++) {
            tokens[i] = -1;
            NSString *name = [NSString stringWithFormat:@"com.minis.rainbowkeyboard.snapshot.v2.%lu", (unsigned long)i];
            int token = -1;
            if (notify_register_check(name.UTF8String, &token) == NOTIFY_STATUS_OK) tokens[i] = token;
        }
    });
    return tokens[index];
}
static inline BOOL RKPublishDisplaySnapshot(NSDictionary *prefs) {
    uint64_t words[RKDisplayWordCount];
    RKEncodeDisplaySnapshot(prefs, words);
    int commit = RKDisplayToken(RKDisplayWordCount);
    if (commit < 0 || notify_set_state(commit, UINT64_MAX) != NOTIFY_STATUS_OK) return NO;
    BOOL valid = YES;
    for (NSUInteger i = 0; i < RKDisplayWordCount; i++) {
        int token = RKDisplayToken(i);
        uint64_t check = 0;
        valid &= token >= 0 && notify_set_state(token, words[i]) == NOTIFY_STATUS_OK &&
            notify_get_state(token, &check) == NOTIFY_STATUS_OK && check == words[i];
    }
    uint64_t hash = RKDisplayChecksum(words), check = 0;
    return valid && notify_set_state(commit, hash) == NOTIFY_STATUS_OK &&
        notify_get_state(commit, &check) == NOTIFY_STATUS_OK && check == hash;
}
static inline NSDictionary *RKReceiveDisplaySnapshot(void) {
    int commit = RKDisplayToken(RKDisplayWordCount);
    uint64_t before = 0, after = 0, words[RKDisplayWordCount] = {};
    if (commit < 0 || notify_get_state(commit, &before) != NOTIFY_STATUS_OK ||
        !before || before == UINT64_MAX) return nil;
    for (NSUInteger i = 0; i < RKDisplayWordCount; i++) {
        int token = RKDisplayToken(i);
        if (token < 0 || notify_get_state(token, &words[i]) != NOTIFY_STATUS_OK) return nil;
    }
    if (notify_get_state(commit, &after) != NOTIFY_STATUS_OK || before != after) return nil;
    return RKDecodeDisplaySnapshot(words, before);
}
static inline NSDictionary *RKMergeDisplaySnapshot(NSDictionary *stored, NSDictionary *snapshot) {
    if (!snapshot || [stored[@"RKSettingsRevision"] unsignedLongLongValue] >
        [snapshot[@"RKSettingsRevision"] unsignedLongLongValue]) return stored ?: @{};
    NSMutableDictionary *result = [stored mutableCopy] ?: [NSMutableDictionary dictionary];
    // Absence means use the renderer's existing default, not an older saved value.
    [result removeObjectsForKeys:RKDisplayKeys()];
    [result addEntriesFromDictionary:snapshot];
    return result;
}
