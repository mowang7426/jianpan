#import "RKPreferences.h"

// Configuration delivery must not depend on the optional keyboard recoloring
// hooks. fd4ab7a skipped their entire constructor and also lost this service.
// Defer work until after dyld initialization; only SpringBoard becomes the
// relay. Other processes can request the stored snapshot without UIKit hooks.
__attribute__((constructor))
static void RKInitializePreferences(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            RKStartPreferencesRelay();
            RKRequestPreferencesRelay();
        }
    });
}
