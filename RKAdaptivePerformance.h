#import <Foundation/Foundation.h>
// Main-thread only. Session-local state, no text capture or disk writes.
void RKAdaptiveSetEnabled(BOOL enabled);
void RKAdaptiveNoteInput(void);
NSInteger RKAdaptiveLevel(void);
