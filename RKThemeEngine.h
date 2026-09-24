#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Theme IDs: 0 = custom/off; 1..9 are built-in themes.
FOUNDATION_EXPORT NSDictionary *RKThemeDefinition(NSInteger theme);
FOUNDATION_EXPORT NSDictionary *RKThemeMergedPreferences(NSDictionary *preferences);
FOUNDATION_EXPORT NSString *RKThemeDisplayName(NSInteger theme);

NS_ASSUME_NONNULL_END
