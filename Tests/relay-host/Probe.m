#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import "RKPreferences.h"
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static NSUInteger changes, requests;
static uint64_t originalCommit;
static NSDictionary *Command(NSDictionary *message) {
    NSString *op = message[@"op"];
    if ([op isEqual:@"read"]) {
        NSDictionary *snapshot = RKReceiveDisplaySnapshot();
        return @{@"bundle":NSBundle.mainBundle.bundleIdentifier ?: @"", @"pid":@(getpid()),
            @"stored":RKReadStoredPreferences(), @"snapshot":snapshot ?: (id)NSNull.null,
            @"effective":RKReadEffectivePreferences()};
    }
    if ([op isEqual:@"stats"]) return @{@"changes":@(changes), @"requests":@(requests)};
    if ([op isEqual:@"save"]) {
        NSMutableDictionary *values = [message[@"values"] mutableCopy];
        BOOL ok = RKSavePreferences(values);
        return @{@"ok":@(ok), @"values":values};
    }
    if ([op isEqual:@"cleanup"]) {
        NSArray *keys = CFBridgingRelease(CFPreferencesCopyKeyList(RKPreferencesDomain,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
        for (NSString *key in keys)
            CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, RKPreferencesDomain);
        BOOL ok = CFPreferencesAppSynchronize(RKPreferencesDomain);
        [NSFileManager.defaultManager removeItemAtPath:RKPreferencesPath error:NULL];
        return @{@"ok":@(ok)};
    }
    BOOL ok = YES;
    if ([op isEqual:@"clear"]) {
        for (NSUInteger i = 0; i <= RKDisplayWordCount; i++)
            ok &= notify_set_state(RKDisplayToken(i), 0) == NOTIFY_STATUS_OK;
        for (NSNumber *token in @[@(RKSettingsRevisionToken()), @(RKColorStateToken()),
                                 @(RKKeyboardPaletteToken())])
            ok &= notify_set_state(token.intValue, 0) == NOTIFY_STATUS_OK;
        // No changed post: recovery must come from a reader's request.
    } else if ([op isEqual:@"partial"]) {
        ok &= notify_get_state(RKDisplayToken(RKDisplayWordCount), &originalCommit) == NOTIFY_STATUS_OK;
        ok &= notify_set_state(RKDisplayToken(RKDisplayWordCount), UINT64_MAX) == NOTIFY_STATUS_OK;
        ok &= notify_post("com.minis.rainbowkeyboard.changed") == NOTIFY_STATUS_OK;
    } else if ([op isEqual:@"checksum"]) {
        uint64_t word = 0;
        ok &= notify_get_state(RKDisplayToken(2), &word) == NOTIFY_STATUS_OK;
        ok &= notify_set_state(RKDisplayToken(2), word ^ 1) == NOTIFY_STATUS_OK;
        ok &= notify_set_state(RKDisplayToken(RKDisplayWordCount), originalCommit) == NOTIFY_STATUS_OK;
        ok &= notify_post("com.minis.rainbowkeyboard.changed") == NOTIFY_STATUS_OK;
    } else if ([op isEqual:@"request"]) {
        for (NSUInteger i = 0; i < [message[@"count"] unsignedIntegerValue]; i++)
            ok &= notify_post("com.minis.rainbowkeyboard.settings.request.v2") == NOTIFY_STATUS_OK;
    } else if ([op isEqual:@"hot"]) {
        NSUInteger before = RKStoredPreferenceReads;
        for (NSUInteger i = 0; i < 10000; i++) RKReadEffectivePreferences();
        return @{@"reads":@(RKStoredPreferenceReads - before)};
    } else return @{@"error":@"unknown command"};
    return @{@"ok":@(ok)};
}

int main(void) {
    @autoreleasepool {
        int changeToken, requestToken;
        if (notify_register_dispatch("com.minis.rainbowkeyboard.changed", &changeToken,
                dispatch_get_main_queue(), ^(int token) { changes++; }) != NOTIFY_STATUS_OK ||
            notify_register_dispatch("com.minis.rainbowkeyboard.settings.request.v2", &requestToken,
                dispatch_get_main_queue(), ^(int token) { requests++; }) != NOTIFY_STATUS_OK) return 2;
        // The separately linked production constructor is the ONLY relay startup.
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            char *line = NULL;
            size_t capacity = 0;
            while (getline(&line, &capacity, stdin) >= 0) {
                @autoreleasepool {
                    NSData *data = [[NSString stringWithUTF8String:line] dataUsingEncoding:NSUTF8StringEncoding];
                    NSDictionary *message = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
                    dispatch_sync(dispatch_get_main_queue(), ^{
                        @autoreleasepool {
                            NSDictionary *result = message ? Command(message) : @{@"error":@"invalid JSON"};
                            NSData *reply = [NSJSONSerialization dataWithJSONObject:result options:0 error:NULL];
                            fwrite(reply.bytes, 1, reply.length, stdout);
                            fputc('\n', stdout);
                            fflush(stdout);
                        }
                    });
                }
            }
            free(line);
            exit(0);
        });
        dispatch_main();
    }
}
