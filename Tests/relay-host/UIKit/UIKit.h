#pragma once
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
@class UIView;
@interface UIColor : NSObject
+ (instancetype)colorWithWhite:(CGFloat)white alpha:(CGFloat)alpha;
+ (instancetype)colorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha;
@end
