#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "RainbowEffectView.h"
#import "RKKeyboardGeometry.h"
#import "RKBlackKeyboard.h"
#import "RKAdaptivePerformance.h"
static char RKOverlayKey;
static char RKOverlayBoundsKey;
static char RKPendingPressKey;
@interface RKPendingPress : NSObject
@property(nonatomic) CGPoint point;
@property(nonatomic) CFTimeInterval time, lastRendered;
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
    if (!RKKeyboardSessionActive()) return;
    if (event.type != UIEventTypeTouches) return;
    for (UITouch *touch in event.allTouches) {
        if (touch.phase != UITouchPhaseBegan) continue;
        UIView *host = RKKeyboardEffectHost(touch.view);
        if (!host || !host.window) continue;
        CGPoint point = [touch locationInView:host];
        if (!CGRectContainsPoint(host.bounds, point)) continue;
        RKAdaptiveNoteInput();
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
            // Throttle decoration before geometry scanning, never UIKit input.
            if ((RKAdaptiveFastInput() || RKAdaptiveLevel() >= 2) && now - pending.lastRendered < .10) return;
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

            // 布局未变时复用缓存键位，打字过程中不再定时全量扫描（P1-1）。
            // keyplane/keys 指针与 bounds 任一变化都会触发重扫，覆盖键盘切换/旋转。
            BOOL scan = geometryChanged || !effect.keyFrames.count || RKKeyboardLayoutChanged(liveHost);
            NSArray<NSValue *> *liveKeyFrames = scan ? RKKeyboardKeyFrames(liveHost) : effect.keyFrames;
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
            pending.lastRendered = CACurrentMediaTime();
            [effect showRippleAtPoint:effectPoint sourceView:sourceView];
        });
    }
}
%end
