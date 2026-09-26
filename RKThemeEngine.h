#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

NSDictionary *RKThemeDefinition(NSInteger theme);
NSDictionary *RKWeChatKeycapThemeDefinition(NSInteger theme);
NSString *RKThemeDisplayName(NSInteger theme);
NSDictionary *RKThemeMergedPreferences(NSDictionary *preferences);

#ifdef __cplusplus
}
#endif
