#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "RainbowEffectView.h"
#import "RKKeyboardGeometry.h"
#import "RKBlackKeyboard.h"
static char RKOverlayKey;
static char RKOverlayBoundsKey;
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
        CGPoint touchPoint = point;
        __weak UIView *weakHost = host;
        __weak UIView *weakSourceView = touch.view;
        // Let UIKit finish delivering the touch before building the visual effect.
        // The input event is therefore not held behind path/layer construction.
        dispatch_async(dispatch_get_main_queue(), ^{
            UIView *liveHost = weakHost;
            if (!liveHost || !liveHost.window) return;
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
            if (geometryChanged) {
                effect.frame = liveHost.bounds;
                [liveHost bringSubviewToFront:effect];
                UIBezierPath *visible = [UIBezierPath bezierPathWithRect:effect.bounds];
                RKCollectExclusions(liveHost, liveHost, visible, 0);
                CAShapeLayer *mask = [CAShapeLayer layer];
                mask.frame = effect.bounds;
                mask.path = visible.CGPath;
                mask.fillRule = kCAFillRuleEvenOdd;
                effect.layer.mask = mask;
                effect.keyFrames = RKKeyboardKeyFrames(liveHost);
                objc_setAssociatedObject(liveHost, &RKOverlayBoundsKey,
                    [NSValue valueWithCGRect:liveHost.bounds], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            CGPoint effectPoint = [liveHost convertPoint:touchPoint toView:effect];
            [effect showRippleAtPoint:effectPoint sourceView:weakSourceView];
        });
    }
}
%end
