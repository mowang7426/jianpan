#pragma once
#import <Foundation/Foundation.h>
#import "RKCandidateEmojiData.h"

static inline void RKWithCandidateOriginal(NSUInteger *depth, void (^original)(void)) {
    (*depth)++;
    @try { original(); } @finally { (*depth)--; }
}

static inline BOOL RKCandidateStringContainsEmoji(NSString *string) {
    if (![string isKindOfClass:NSString.class] || string.length == 0) return NO;
    // Bound work on every drawing entry, including pathological combining runs.
    // Long strings retain their original appearance rather than allocate/scan.
    if (string.length > 512) return YES;
    __block BOOL found = NO;
    [string enumerateSubstringsInRange:NSMakeRange(0, string.length)
        options:NSStringEnumerationByComposedCharacterSequences
        usingBlock:^(NSString *part, NSRange range, NSRange enclosing, BOOL *stop) {
        for (NSUInteger index = 0; index < part.length; index++) {
            uint32_t scalar = [part characterAtIndex:index];
            if (scalar >= 0xD800 && scalar <= 0xDBFF && index + 1 < part.length) {
                uint32_t low = [part characterAtIndex:index + 1];
                if (low >= 0xDC00 && low <= 0xDFFF) {
                    scalar = 0x10000 + ((scalar - 0xD800) << 10) + low - 0xDC00;
                    index++;
                }
            }
            if (RKCandidateEmojiScalar(scalar)) { found = YES; *stop = YES; break; }
        }
    }];
    return found;
}

static inline BOOL RKCandidateAttributedStringContainsEmoji(NSAttributedString *value) {
    if (![value isKindOfClass:NSAttributedString.class]) return NO;
    __block BOOL found = RKCandidateStringContainsEmoji(value.string);
    if (found) return YES;
    // UIKit/AppKit NSAttachmentAttributeName both use this stable string key.
    [value enumerateAttribute:@"NSAttachment" inRange:NSMakeRange(0, value.length)
        options:0 usingBlock:^(id attachment, NSRange range, BOOL *stop) {
        if (attachment) { found = YES; *stop = YES; }
    }];
    return found;
}
