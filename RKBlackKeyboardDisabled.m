#import "RKBlackKeyboard.h"

// Safe build replacement, not just a constructor early-return. Tweak.xm still
// calls this entry when attaching its overlay. Never traverse/recolor native
// views, install hooks, or start black-keyboard diagnostics from this target.
void RKApplyBlackKeyboardHost(__unused UIView *host) {}
