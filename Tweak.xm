#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "RainbowEffectView.h"
#import "RKKeyboardGeometry.h"
#import "RKBlackKeyboard.h"
static char RKOverlayKey;
static char RKOverlayBoundsKey;
static char RKPendingPressKey;
static char RKGeometryTimeKey;
@interface RKPendingPress : NSObject
@property(nonatomic) CGPoint point;
@property(nonatomic) CFTimeInterval time;
@property(nonatomic, weak) UIView *source;
@property(nonatomic) BOOL queued;
@end
@implementation RKPendingPress
@end
static void RKCollectExclusions(UIView *node, UIView *host, UIBezierPath *path, NSUInteger depth) {
    if (depth > 8) return;
    for (UIView *v in node.subviews) {
        if ([v isKindOfClass:RainbowEffectView.class] || v.hidden || v.alpha < .01) continue;
        if (RKKeyboardExcludedView(v)) {
            CGRect r = CGRectIntersection(host.bounds, [v convertRect:v.bounds toView:host]);
            if (!CGRectIsNull(r) && !CGRectIsEmpty(r)) [path appendPath:[UIBezierPath bezierPathWithRect:r]];
        } else RKCollectExclusions(v, host, path, depth + 1);
    }
}
%hook UIApplication
- (void)sendEvent:(UIEvent *)event {
    %orig;
    if (event.type != UIEventTypeTouches) return;
    for (UITouch *touch in event.allTouches) {
        if (touch.phase != UITouchPhaseBegan) continue;
        UIView *host = RKKeyboardEffectHost(touch.view);
        if (!host || !host.window) continue;
        CGPoint point = [touch locationInView:host];
        if (!CGRectContainsPoint(host.bounds, point)) continue;
        RKPendingPress *pending = objc_getAssociatedObject(host, &RKPendingPressKey);
        if (!pending) {
            pending = [RKPendingPress new];
            objc_setAssociatedObject(host, &RKPendingPressKey, pending, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        pending.point = point;
        pending.time = CACurrentMediaTime();
        pending.source = touch.view;
        // Coalesce decoration only. Every original input event was already delivered.
        if (pending.queued) continue;
        pending.queued = YES;
        __weak UIView *weakHost = host;
        // Let UIKit finish delivering the touch before building the visual effect.
        // The input event is therefore not held behind path/layer construction.
        dispatch_async(dispatch_get_main_queue(), ^{
            pending.queued = NO;
            UIView *liveHost = weakHost;
            CFTimeInterval now = CACurrentMediaTime();
            if (!liveHost || !liveHost.window || liveHost.hidden || now - pending.time > .080) return;
            CGPoint touchPoint = pending.point;
            UIView *sourceView = pending.source;
            RainbowEffectView *effect = objc_getAssociatedObject(liveHost, &RKOverlayKey);
            if (!effect) {
                effect = [[RainbowEffectView alloc] initWithFrame:liveHost.bounds];
                objc_setAssociatedObject(liveHost, &RKOverlayKey, effect, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [liveHost addSubview:effect];
                RKApplyBlackKeyboardHost(liveHost);
            }
            NSValue *oldBoundsValue = objc_getAssociatedObject(liveHost, &RKOverlayBoundsKey);
            BOOL geometryChanged = !oldBoundsValue ||
                !CGRectEqualToRect(oldBoundsValue.CGRectValue, liveHost.bounds);

            // Revalidate equal-sized layout changes at most every 200 ms.
            // Bounds changes and missing geometry still refresh immediately.
            CFTimeInterval lastScan = [objc_getAssociatedObject(liveHost, &RKGeometryTimeKey) doubleValue];
            BOOL scan = geometryChanged || !effect.keyFrames.count || now - lastScan >= .2;
            NSArray<NSValue *> *liveKeyFrames = scan ? RKKeyboardKeyFrames(liveHost) : effect.keyFrames;
            if (scan) objc_setAssociatedObject(liveHost, &RKGeometryTimeKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            BOOL keyGeometryChanged = ![effect.keyFrames isEqualToArray:liveKeyFrames];
            if (geometryChanged || keyGeometryChanged) {
                effect.frame = liveHost.bounds;
                [liveHost bringSubviewToFront:effect];
                if (geometryChanged) {
                    UIBezierPath *visible = [UIBezierPath bezierPathWithRect:effect.bounds];
                    RKCollectExclusions(liveHost, liveHost, visible, 0);
                    CAShapeLayer *mask = [CAShapeLayer layer];
                    mask.frame = effect.bounds;
                    mask.path = visible.CGPath;
                    mask.fillRule = kCAFillRuleEvenOdd;
                    effect.layer.mask = mask;
                }
                effect.keyFrames = liveKeyFrames;
                objc_setAssociatedObject(liveHost, &RKOverlayBoundsKey,
                    [NSValue valueWithCGRect:liveHost.bounds], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            CGPoint effectPoint = [liveHost convertPoint:touchPoint toView:effect];
            if (CACurrentMediaTime() - pending.time > .080) return;
            [effect showRippleAtPoint:effectPoint sourceView:sourceView];
        });
    }
}
%end
