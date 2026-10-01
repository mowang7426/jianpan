#import <Foundation/Foundation.h>
#import "RKCandidateEmoji.h"
#import "RKCandidateInk.h"
static void check(BOOL ok, NSString *name) { if (!ok) { NSLog(@"FAIL %@", name); exit(1); } }
int main(void) {
 @autoreleasepool {
  check(!RKCandidateStringContainsEmoji(@"abc中文123#*"), @"ordinary CJK Latin digits hash star");
  for (NSString *s in @[@"😀", @"❤️", @"👍🏽", @"👨‍👩‍👧‍👦", @"🇨🇳", @"1️⃣", @"#⃣", @"*️⃣", @"☕️", @"©️", @"中😀文", @"🏴‍☠️", @"✈︎", @"☹", @"A\uFE0F", @"\uFFFC"]) check(RKCandidateStringContainsEmoji(s), s);
  check(RKCandidateStringContainsEmoji(@"©"), @"ambiguous text presentation conservatively preserved");
  for (NSString *s in @[@"", @"中文", @"abc", @"0123456789", @"#*", @"é", @"A\uFE0E"]) {
      check(!RKCandidateStringContainsEmoji(s), s);
      check(!RKCandidateAttributedStringContainsEmoji([[NSAttributedString alloc] initWithString:s]), s);
  }
  check(RKCandidateStringContainsEmoji([@"a" stringByPaddingToLength:513 withString:@"a" startingAtIndex:0]), @"bounded long run");
  check(RKCandidateAttributedStringContainsEmoji([[NSAttributedString alloc] initWithString:@"中😀文"]), @"attributed mixed emoji");
  NSMutableAttributedString *a = [[NSMutableAttributedString alloc] initWithString:@"plain"];
  [a addAttribute:@"NSAttachment" value:[NSObject new] range:NSMakeRange(0, 1)];
  check(RKCandidateAttributedStringContainsEmoji(a), @"attachment");
  __block NSUInteger depth = 0;
  __block unsigned calls = 0;
  RKWithCandidateOriginal(&depth, ^{
      check(depth == 1, @"outer depth"); calls++;
      RKWithCandidateOriginal(&depth, ^{ check(depth == 2, @"nested depth"); calls++; });
      check(depth == 1, @"nested depth restored");
  });
  check(depth == 0 && calls == 2, @"original called exactly once per layer");
  @try { RKWithCandidateOriginal(&depth, ^{ @throw [NSException exceptionWithName:@"test" reason:nil userInfo:nil]; }); }
  @catch (NSException *exception) { check(depth == 0, @"exception restores depth"); }
  uint8_t gray[] = {100,100,100,255, 0,0,0,0};
  uint8_t color[] = {100,100,100,255, 10,20,40,255};
  check(!RKScanCandidateInk(gray, 2, 1).chromatic, @"grayscale glyph");
  check(RKScanCandidateInk(color, 2, 1).chromatic, @"color glyph");
  check(RKScanCandidateInk(color, 2, 1).minX == 0 && RKScanCandidateInk(color, 2, 1).maxX == 1, @"ink bounds");
 }
 puts("PASS emoji preservation helper tests"); return 0;
}
