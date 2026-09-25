#import "RainbowEffectView.h"
#import "RKKeyboardGeometry.h"
#import "RKNeonPress.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import "RKPreferences.h"
#import "RKThemeEngine.h"
#import "RKAdaptivePerformance.h"
static NSDictionary *RKReadPreferences(void) {
    return RKThemeMergedPreferences(RKReadEffectivePreferences());
}

@class RainbowEffectView;
static void RKEffectPreferencesChanged(CFNotificationCenterRef center, void *observer,
                                       CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    RainbowEffectView *view = (__bridge RainbowEffectView *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (view) [view reloadConfiguration];
    });
}
// P1-3: 每个键位的波纹几何（frame/路径）只依赖键位矩形与 rimWidth 两档，
// 预构建后每次按键直接复用，避免逐键重建 path 与坐标变换。
@interface RKKeyWaveGeometry : NSObject
@property(nonatomic) CGRect edgeFrame;
@property(nonatomic, strong) UIBezierPath *outline; // 已平移到 edgeFrame 坐标系
@property(nonatomic, strong) UIBezierPath *outer;   // 圆角外框 ∪ outline（EvenOdd 环带）
@end
@implementation RKKeyWaveGeometry
@end
@interface RainbowEffectView ()
@property(nonatomic,strong) NSDictionary *config;
@property(nonatomic,strong) UIImage *underlightMaskImage;
@property(nonatomic) CGRect underlightMaskBounds;
@property(nonatomic) CGFloat hue;
@property(nonatomic) CGFloat pressHue;
@property(nonatomic,strong) CALayer *fastFeedback;
@property(nonatomic) NSInteger lastStyle;
@property(nonatomic,strong) UIBezierPath *cachedGutterPath;
@property(nonatomic,strong) NSArray<UIBezierPath *> *cachedFacePaths;
@property(nonatomic,strong) NSArray<NSValue *> *cachedCenters;
@property(nonatomic,strong) NSArray<RKKeyWaveGeometry *> *cachedWaveGeometries;
@property(nonatomic) CGRect cachedGeometryBounds;
@end
@implementation RainbowEffectView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = UIColor.clearColor;
        self.clipsToBounds = YES;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadConfiguration) name:UIApplicationDidBecomeActiveNotification object:nil];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(self),
            RKEffectPreferencesChanged, CFSTR("com.minis.rainbowkeyboard.changed"), NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        [self reloadConfiguration];
    }
    return self;
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(self),
        CFSTR("com.minis.rainbowkeyboard.changed"), NULL);
}
- (void)reloadConfiguration {
    NSDictionary *newConfig = RKReadPreferences();
    if (!newConfig) newConfig = @{};
    self.config = newConfig;
    RKAdaptiveSetEnabled(!newConfig[@"SmartPerformance"] || [newConfig[@"SmartPerformance"] boolValue]);
}
- (CGFloat)number:(NSString *)key fallback:(CGFloat)fallback low:(CGFloat)low high:(CGFloat)high {
    id x = self.config[key];
    CGFloat v = [x respondsToSelector:@selector(doubleValue)] ? [x doubleValue] : fallback;
    CGFloat result = isfinite(v) ? MIN(high,MAX(low,v)) : fallback;
    NSInteger level = RKAdaptiveLevel();
    if (level) {
        if ([key isEqualToString:@"MaxEffects"]) result = MIN(result, level == 1 ? 2 : 1);
        if ([key isEqualToString:@"Duration"] || [key isEqualToString:@"BackgroundDuration"])
            result = MIN(result, level == 1 ? 0.35 : 0.22);
        if ([key isEqualToString:@"BackgroundRadius"]) result = MIN(result, 110);
    }
    return result;
}
- (BOOL)flag:(NSString *)key {
    if (RKAdaptiveLevel() && ([key isEqualToString:@"AmbientGlow"] || [key isEqualToString:@"BackgroundFeedback"])) return NO;
    return !self.config[key] || [self.config[key] boolValue];
}
- (CGFloat)neonSaturation:(CGFloat)base {
    return base * [self number:@"NeonSaturation" fallback:.72 low:0 high:1];
}
- (BOOL)preservesBlackFaces {
    return [self flag:@"PureBlackKeyboard"];
}
- (CAShapeLayer *)keyGutterMask {
    if (!self.cachedGutterPath || !CGRectEqualToRect(self.cachedGeometryBounds, self.bounds)) {
        UIBezierPath *gaps = [UIBezierPath bezierPathWithRect:self.bounds];
        for (UIBezierPath *face in self.cachedFacePaths) [gaps appendPath:face];
        self.cachedGutterPath = gaps;
        self.cachedGeometryBounds = self.bounds;
    }
    CAShapeLayer *mask = [CAShapeLayer layer];
    mask.frame = self.bounds;
    mask.path = self.cachedGutterPath.CGPath;
    mask.fillRule = kCAFillRuleEvenOdd;
    return mask;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    if (!CGRectEqualToRect(self.cachedGeometryBounds, self.bounds)) {
        self.cachedGutterPath = nil;
        self.cachedGeometryBounds = CGRectNull;
    }
    // Old animations must not float over a new keyboard after rotation/resizing.
    for (CALayer *pulse in self.layer.sublayers.copy) {
        if (!CGRectEqualToRect(pulse.frame, self.bounds)) [pulse removeFromSuperlayer];
    }
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) for (CALayer *pulse in self.layer.sublayers.copy) [pulse removeFromSuperlayer];
}
- (void)setKeyFrames:(NSArray<NSValue *> *)keyFrames {
    if ([_keyFrames isEqualToArray:keyFrames]) return;
    _keyFrames = [keyFrames copy];
    self.underlightMaskImage = nil;
    NSMutableArray *faces = [NSMutableArray arrayWithCapacity:_keyFrames.count];
    NSMutableArray *centers = [NSMutableArray arrayWithCapacity:_keyFrames.count];
    NSMutableArray *geometries = [NSMutableArray arrayWithCapacity:_keyFrames.count * 2];
    for (NSValue *value in _keyFrames) {
        CGRect rect = value.CGRectValue;
        [faces addObject:RKKeyboardKeyFacePath(rect)];
        [centers addObject:[NSValue valueWithCGPoint:CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect))]];
        UIBezierPath *facePath = RKKeyboardKeyFacePath(rect);
        CGRect face = facePath.bounds;
        // 两档 rimWidth：普通 2.6（偶数下标）、按压 3.0（奇数下标）。
        for (NSUInteger i = 0; i < 2; i++) {
            CGFloat rim = i == 1 ? 3.0 : 2.6;
            RKKeyWaveGeometry *geometry = [RKKeyWaveGeometry new];
            CGRect edgeFrame = CGRectInset(face, -rim, -rim);
            UIBezierPath *outline = [facePath copy];
            [outline applyTransform:CGAffineTransformMakeTranslation(-edgeFrame.origin.x, -edgeFrame.origin.y)];
            CGFloat corner = MIN(5, MIN(face.size.width, face.size.height) * .16);
            UIBezierPath *outer = [UIBezierPath bezierPathWithRoundedRect:edgeFrame cornerRadius:corner + rim];
            [outer appendPath:outline];
            geometry.edgeFrame = edgeFrame;
            geometry.outline = outline;
            geometry.outer = outer;
            [geometries addObject:geometry];
        }
    }
    self.cachedFacePaths = faces;
    self.cachedCenters = centers;
    self.cachedWaveGeometries = geometries;
    self.cachedGutterPath = nil;
    self.cachedGeometryBounds = CGRectNull;
    for (CALayer *pulse in self.layer.sublayers.copy) [pulse removeFromSuperlayer];
}
- (void)addAmbientGlowToPulse:(CALayer *)pulse origin:(CGPoint)origin radius:(CGFloat)radius
                         hue:(CGFloat)hue mode:(NSInteger)mode duration:(CGFloat)duration {
    if (![self flag:@"AmbientGlow"] || ![self flag:@"BackgroundFeedback"]) return;
    CGFloat strength = [self number:@"AmbientStrength" fallback:.85 low:0 high:1];
    CGFloat alpha = [self number:@"Opacity" fallback:.65 low:0 high:1] * strength;
    if (alpha <= 0) return;
    CGFloat brightness = [self number:@"Brightness" fallback:.95 low:0 high:1];
    CALayer *ambient = [CALayer layer];
    ambient.name = @"keyboardAmbientGlow";
    ambient.frame = self.bounds;
    [pulse addSublayer:ambient];

    // Solid black mode has backlighting only; the optional wash belongs to other themes.
    for (NSUInteger pass = [self preservesBlackFaces] ? 1 : 0; pass < 2; pass++) {
        CALayer *field = [CALayer layer];
        field.name = pass ? @"gutterLight" : @"keyFaceWash";
        field.frame = self.bounds;
        [ambient addSublayer:field];
        if (pass) field.mask = [self keyGutterMask];
        CAGradientLayer *bloom = [CAGradientLayer layer];
        bloom.type = kCAGradientLayerRadial;
        bloom.frame = CGRectMake(origin.x - radius, origin.y - radius, radius * 2, radius * 2);
        bloom.startPoint = CGPointMake(.5, .5);
        bloom.endPoint = CGPointMake(1, 1);
        CGFloat level = alpha * (pass ? 1 : .24);
        UIColor *inner = [UIColor colorWithHue:hue saturation:[self neonSaturation:.82] brightness:brightness alpha:1];
        UIColor *middle = [UIColor colorWithHue:mode == 1 ? hue : fmod(hue + .13, 1)
                                    saturation:[self neonSaturation:.75] brightness:brightness alpha:1];
        UIColor *outer = [UIColor colorWithHue:mode == 1 ? hue : fmod(hue + .25, 1)
                                   saturation:[self neonSaturation:.9] brightness:brightness alpha:1];
        bloom.colors = @[(id)[inner colorWithAlphaComponent:level * .22].CGColor,
            (id)[inner colorWithAlphaComponent:level * .6].CGColor,
            (id)[middle colorWithAlphaComponent:level].CGColor,
            (id)[outer colorWithAlphaComponent:level * .5].CGColor,
            (id)[outer colorWithAlphaComponent:0].CGColor];
        bloom.locations = @[@0, @.22, @.52, @.78, @1];
        bloom.opacity = 0;
        [field addSublayer:bloom];
        CAKeyframeAnimation *spread = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
        spread.values = @[@.04, @.64, @1, @1.08];
        spread.keyTimes = @[@0, @.32, @.7, @1];
        spread.duration = duration;
        [bloom addAnimation:spread forKey:@"ambientExpansion"];
        CAKeyframeAnimation *fade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        fade.values = @[@0, @1, @.9, @0];
        fade.keyTimes = @[@0, @.08, @.52, @1];
        fade.duration = duration;
        [bloom addAnimation:fade forKey:@"ambientFade"];
    }
}
- (CALayer *)waveUnderCapMask {
    CGFloat screenScale = self.window.screen.scale;
    if (screenScale <= 0) screenScale = 2;
    // Cache an alpha mask of the actual free keyboard bed. Clear operations
    // form a union of all key faces, so overlapping keys never reopen a hole.
    if (!self.underlightMaskImage || !CGRectEqualToRect(self.underlightMaskBounds,self.bounds) ||
        self.underlightMaskImage.scale != screenScale) {
        UIGraphicsBeginImageContextWithOptions(self.bounds.size, NO, screenScale);
        CGContextRef context = UIGraphicsGetCurrentContext();
        if (!context) { UIGraphicsEndImageContext(); return nil; }
        CGContextTranslateCTM(context,-self.bounds.origin.x,-self.bounds.origin.y);
        CGRect bed = CGRectNull;
        for (NSValue *value in self.keyFrames) bed = CGRectUnion(bed,value.CGRectValue);
        [[UIColor whiteColor] setFill];
        UIRectFill(CGRectIntersection(CGRectInset(bed,-3,-4),self.bounds));
        CGContextSetBlendMode(context,kCGBlendModeClear);
        for (NSValue *value in self.keyFrames) {
            // Full detected rectangles, not shrunken faces: do not brighten text.
            CGContextFillRect(context,value.CGRectValue);
        }
        self.underlightMaskImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        self.underlightMaskBounds = self.bounds;
    }
    if (!self.underlightMaskImage) return nil;
    CALayer *mask = [CALayer layer];
    mask.frame = self.bounds;
    mask.contentsScale = screenScale;
    mask.contents = (__bridge id)self.underlightMaskImage.CGImage;
    return mask;
}
// Both effects live in the exposed keyboard bed. Neither outlines keycaps.
- (void)showBedEffectAtPoint:(CGPoint)point style:(NSInteger)style {
    CGRect pressed = CGRectNull;
    for (NSValue *value in self.keyFrames) {
        CGRect rect = value.CGRectValue;
        if (CGRectContainsPoint(rect, point) && (CGRectIsNull(pressed) ||
            rect.size.width*rect.size.height < pressed.size.width*pressed.size.height)) pressed = rect;
    }
    if (CGRectIsNull(pressed) || CGRectIsEmpty(self.bounds)) return;
    CALayer *mask = [self waveUnderCapMask];
    if (!mask) return;
    CGFloat brightness = [self number:@"Brightness" fallback:.95 low:0 high:1];
    CGFloat alpha = [self number:@"Opacity" fallback:.65 low:0 high:1];
    if (brightness <= 0 || alpha <= 0) return;
    BOOL fast = RKAdaptiveFastInput() || RKAdaptiveLevel() >= 2;
    BOOL reduce = UIAccessibilityIsReduceMotionEnabled();
    NSUInteger limit = fast ? 1 : 2;
    while (self.layer.sublayers.count >= limit) [self.layer.sublayers.firstObject removeFromSuperlayer];
    NSInteger mode = (NSInteger)[self number:@"ColorMode" fallback:0 low:0 high:2];
    self.hue = fmod(self.hue+.137,1);
    CGFloat hue = mode == 1 ? [self number:@"Hue" fallback:.55 low:0 high:1] :
        (mode == 2 ? point.x/MAX(1,self.bounds.size.width) : self.hue);
    UIColor *color = [UIColor colorWithHue:hue saturation:[self neonSaturation:1] brightness:brightness alpha:1];
    CGFloat reach = MIN(210,MAX(100,[self number:@"BackgroundRadius" fallback:180 low:60 high:360]));
    CGFloat duration = MIN(.75,MAX(.42,[self number:@"Duration" fallback:.55 low:.15 high:1.2]));
    if (fast) { duration = .38; reach = MIN(reach,145); }
    if (style == 0) {
        // Water-drop mode: compact reach and slow, even radial motion.
        // Fast input drops the second front instead of speeding up the first.
        reach = MIN(105,MAX(65,pressed.size.width*.85));
        duration = .95;
    }
    if (reduce) reach = 32;
    CGPoint origin = CGPointMake(CGRectGetMidX(pressed),CGRectGetMaxY(pressed)+1);
    if (style == 0) origin = point; // Impact follows the actual touch beneath the masked keycap.
    CALayer *pulse = [CALayer layer];
    pulse.name = style == 0 ? @"RKBedRipples" : @"RKBedSpread";
    pulse.frame = self.bounds;
    pulse.bounds = self.bounds;
    pulse.opacity = 0;
    pulse.mask = mask;
    [self.layer addSublayer:pulse];
    CFTimeInterval now = [pulse convertTime:CACurrentMediaTime() fromLayer:nil];
    if (style == 0) {
        // Two restrained water ripples; the trailing ripple is weaker.
        NSUInteger fronts = fast || reduce ? 1 : 2;
        for (NSUInteger i = 0; i < fronts; i++) {
            for (NSUInteger pass = 0; pass < 2; pass++) {
                CAShapeLayer *ring = [CAShapeLayer layer];
                ring.frame = self.bounds;
                ring.bounds = self.bounds;
                ring.contentsScale = self.window.screen.scale;
                ring.fillColor = UIColor.clearColor.CGColor;
                ring.strokeColor = [color colorWithAlphaComponent:(pass ? 1 : .12) * (i ? .52 : 1)].CGColor;
                ring.lineWidth = pass ? 2.2 : 4.5;
                ring.opacity = 0;
                CGFloat initial = reduce ? 26 : 3;
                UIBezierPath *start = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(origin.x-initial,origin.y-initial,initial*2,initial*2)];
                UIBezierPath *end = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(origin.x-reach,origin.y-reach,reach*2,reach*2)];
                ring.path = end.CGPath;
                [pulse addSublayer:ring];
                CFTimeInterval begin = now + i*duration*.22;
                if (!reduce) {
                    CABasicAnimation *expand = [CABasicAnimation animationWithKeyPath:@"path"];
                    expand.fromValue = (__bridge id)start.CGPath;
                    expand.toValue = (__bridge id)end.CGPath;
                    expand.beginTime = begin;
                    expand.duration = duration*.78;
                    expand.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
                    [ring addAnimation:expand forKey:@"roundWaveTravel"];
                }
                CAKeyframeAnimation *fade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
                fade.values = @[@0,@1,@.65,@0]; fade.keyTimes = @[@0,@.10,@.55,@1];
                fade.beginTime = begin; fade.duration = duration*.78;
                [ring addAnimation:fade forKey:@"roundWaveFade"];
            }
        }
    } else {
        // A compact, expanding pool with a defined edge, clipped to gaps.
        // No central flash, per-key outline, shadow, or key-face fill.
        CAGradientLayer *pool = [CAGradientLayer layer];
        pool.type = kCAGradientLayerRadial;
        pool.frame = CGRectMake(origin.x-reach,origin.y-reach,reach*2,reach*2);
        pool.startPoint = CGPointMake(.5,.5);
        pool.endPoint = CGPointMake(1,1);
        pool.colors = @[(id)[color colorWithAlphaComponent:.38].CGColor,
            (id)[color colorWithAlphaComponent:.75].CGColor,
            (id)color.CGColor, (id)[color colorWithAlphaComponent:0].CGColor];
        pool.locations = @[@0,@.4,@.72,@1];
        [pulse addSublayer:pool];
        if (!reduce) {
            CABasicAnimation *spread = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
            spread.fromValue = @.06; spread.toValue = @1;
            spread.duration = duration;
            spread.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            [pool addAnimation:spread forKey:@"bedSpreadTravel"];
        }
    }
    CAKeyframeAnimation *life = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    CGFloat peak = MIN(1,alpha*1.35);
    life.values = @[@0,@(peak),@(peak),@0];
    life.keyTimes = @[@0,@.06,@.65,@1];
    life.duration = duration;
    [pulse addAnimation:life forKey:@"bedEffectLifetime"];
    // Transparent when finished; at most two retained pulses, no timer queue.
}

- (void)showRippleAtPoint:(CGPoint)point {
    [self showRippleAtPoint:point sourceView:nil];
}
- (void)showCrispUnderlightAtPoint:(CGPoint)point {
    CGRect pressed = CGRectNull;
    for (NSValue *value in self.keyFrames) {
        CGRect r = value.CGRectValue;
        if (CGRectContainsPoint(r, point) &&
            (CGRectIsNull(pressed) || r.size.width*r.size.height < pressed.size.width*pressed.size.height)) pressed = r;
    }
    if (CGRectIsNull(pressed) || CGRectIsEmpty(self.bounds)) return;
    CGFloat brightness = [self number:@"Brightness" fallback:.95 low:0 high:1];
    CGFloat opacity = [self number:@"Opacity" fallback:.65 low:0 high:1];
    if (brightness <= 0 || opacity <= 0) return;
    CGFloat screenScale = self.window.screen.scale;
    if (screenScale <= 0) screenScale = 2;
    // Cache an alpha mask of the actual free keyboard bed. Clear operations
    // form a union of all key faces, so overlapping keys never reopen a hole.
    if (!self.underlightMaskImage || !CGRectEqualToRect(self.underlightMaskBounds,self.bounds) ||
        self.underlightMaskImage.scale != screenScale) {
        UIGraphicsBeginImageContextWithOptions(self.bounds.size, NO, screenScale);
        CGContextRef context = UIGraphicsGetCurrentContext();
        if (!context) { UIGraphicsEndImageContext(); return; }
        CGContextTranslateCTM(context,-self.bounds.origin.x,-self.bounds.origin.y);
        CGRect bed = CGRectNull;
        for (NSValue *value in self.keyFrames) bed = CGRectUnion(bed,value.CGRectValue);
        [[UIColor whiteColor] setFill];
        UIRectFill(CGRectIntersection(CGRectInset(bed,-3,-4),self.bounds));
        CGContextSetBlendMode(context,kCGBlendModeClear);
        for (NSValue *value in self.keyFrames) {
            // Full detected rectangles, not shrunken faces: do not brighten text.
            CGContextFillRect(context,value.CGRectValue);
        }
        self.underlightMaskImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        self.underlightMaskBounds = self.bounds;
    }
    if (!self.underlightMaskImage) return;
    BOOL fast = RKAdaptiveFastInput() || RKAdaptiveLevel() >= 2;
    BOOL reduce = UIAccessibilityIsReduceMotionEnabled();
    NSUInteger limit = fast ? 1 : 2;
    while (self.layer.sublayers.count >= limit) [self.layer.sublayers.firstObject removeFromSuperlayer];
    NSInteger mode = (NSInteger)[self number:@"ColorMode" fallback:0 low:0 high:2];
    self.hue = fmod(self.hue + .137,1);
    CGFloat hue = mode == 1 ? [self number:@"Hue" fallback:.55 low:0 high:1] :
        (mode == 2 ? point.x/MAX(1,self.bounds.size.width) : self.hue);
    UIColor *color = [UIColor colorWithHue:hue saturation:[self neonSaturation:1] brightness:brightness alpha:1];
    CALayer *pulse = [CALayer layer];
    pulse.name = @"RKExpandingUnderlight";
    pulse.frame = self.bounds;
    pulse.bounds = self.bounds;
    pulse.opacity = 0;
    CALayer *mask = [CALayer layer];
    mask.frame = self.bounds;
    mask.contentsScale = screenScale;
    mask.contents = (__bridge id)self.underlightMaskImage.CGImage;
    pulse.mask = mask;
    [self.layer addSublayer:pulse];
    // Launch from just underneath the pressed key, rather than its letter.
    CGPoint origin = CGPointMake(CGRectGetMidX(pressed),CGRectGetMaxY(pressed)+1);
    CGFloat reach = MIN(210,MAX(105,[self number:@"BackgroundRadius" fallback:180 low:60 high:360]));
    CGFloat duration = MIN(.65,MAX(.38,[self number:@"Duration" fallback:.55 low:.15 high:1.2]));
    if (fast) { reach = MIN(reach,145); duration = .38; }
    CGFloat initial = reduce ? 26 : 5;
    CGFloat finalRadius = reduce ? initial : reach;
    UIBezierPath *start = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(origin.x-initial,origin.y-initial,initial*2,initial*2)];
    UIBezierPath *end = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(origin.x-finalRadius,origin.y-finalRadius,finalRadius*2,finalRadius*2)];
    // A 20pt moving band with an 8pt bright core. No Gaussian blur or
    // whole-keyboard color wash. Both layers are clipped to the same gaps.
    for (NSUInteger pass = 0; pass < 2; pass++) {
        CAShapeLayer *ring = [CAShapeLayer layer];
        ring.frame = self.bounds;
        ring.bounds = self.bounds;
        ring.contentsScale = screenScale;
        ring.fillColor = UIColor.clearColor.CGColor;
        ring.strokeColor = [color colorWithAlphaComponent:pass ? 1 : .28].CGColor;
        ring.lineWidth = pass ? 8 : 20;
        ring.path = end.CGPath;
        [pulse addSublayer:ring];
        if (!reduce) {
            CABasicAnimation *expand = [CABasicAnimation animationWithKeyPath:@"path"];
            expand.fromValue = (__bridge id)start.CGPath;
            expand.toValue = (__bridge id)end.CGPath;
            expand.duration = duration;
            expand.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            [ring addAnimation:expand forKey:@"underlightExpansion"];
        }
    }
    CAKeyframeAnimation *fade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    CGFloat peak = MIN(1,opacity*1.35);
    fade.values = @[@0,@(peak),@(peak),@0];
    fade.keyTimes = @[@0,@.06,@.62,@1];
    fade.duration = duration;
    [pulse addAnimation:fade forKey:@"underlightLifetime"];
    // Transparent after expiration; the next press evicts old layers (max two).
}

- (void)showRippleAtPoint:(CGPoint)point sourceView:(UIView *)sourceView {
    // Configuration is cached and invalidated by the settings Darwin notification.
    // Do not perform preference/transport checks on every key press.
    // Input activity is recorded once in sendEvent, before decoration coalescing.
    NSString *bid = NSBundle.mainBundle.bundleIdentifier.lowercaseString ?: @"";
    BOOL weType = [bid containsString:@"wetype"];
    if (![self flag:@"Enabled"] || ![self flag:@"RippleEnabled"] || ![self flag:weType ? @"WeChatKeyboard" : @"NativeKeyboard"]) {
        for (CALayer *l in self.layer.sublayers.copy) [l removeFromSuperlayer];
        return;
    }
    if (!self.window || self.hidden) return;
    // Keep the original wave/ripple appearance during fast input too.
    // Tweak.xm still coalesces/throttles decoration work to protect typing.
    [self.fastFeedback removeAllAnimations];
    [self.fastFeedback removeFromSuperlayer];
    NSInteger style = (NSInteger)[self number:@"EffectStyle" fallback:0 low:0 high:3];
    // Keep the user's original configured style; adaptive mode only reduces work.
    if (style != self.lastStyle) {
        for (CALayer *layer in self.layer.sublayers.copy) [layer removeFromSuperlayer];
        self.lastStyle = style;
    }
    if (style == 3) {
        [self showCrispUnderlightAtPoint:point];
        return;
    }
    if (style == 0 || style == 1) {
        [self showBedEffectAtPoint:point style:style];
        return;
    }
    CGFloat brightness = [self number:@"Brightness" fallback:.95 low:0 high:1];
    CGFloat duration = [self number:@"Duration" fallback:.55 low:.15 high:1.2];
    NSUInteger limit = (NSUInteger)[self number:@"MaxEffects" fallback:4 low:1 high:8];
    while (self.layer.sublayers.count >= limit) [self.layer.sublayers.firstObject removeFromSuperlayer];
    NSInteger mode = (NSInteger)[self number:@"ColorMode" fallback:0 low:0 high:2];
    self.hue = fmod(self.hue + .137, 1);
    CGFloat hue = mode == 1 ? [self number:@"Hue" fallback:.55 low:0 high:1] : (mode == 2 ? point.x / MAX(1,self.bounds.size.width) : self.hue);
    if (style == 2) {
        for (NSValue *value in self.keyFrames) {
            if (!CGRectContainsPoint(value.CGRectValue, point)) continue;
            self.pressHue = fmod(self.pressHue + .38196601125, 1);
            BOOL single = [self number:@"PressColorMode" fallback:0 low:0 high:1] == 1;
            UIColor *color = single ? RKKeyboardColor(self.config, @"PressColor") :
                [UIColor colorWithHue:self.pressHue saturation:1 brightness:1 alpha:1];
            CGFloat pressBrightness = [self number:@"PressBrightness" fallback:1 low:0 high:1];
            NSInteger theme = [self.config[@"Theme"] integerValue];
            if (theme >= 1 && theme <= 9) {
                // Preset themes take priority; Custom retains independent press colors.
                color = [UIColor colorWithHue:hue saturation:[self neonSaturation:1]
                                   brightness:1 alpha:1];
                pressBrightness = brightness;
            }
            RKShowNeonKeyPress(self, value.CGRectValue, color,
                pressBrightness,
                duration, UIAccessibilityIsReduceMotionEnabled() || [self flag:@"SmartPerformance"], sourceView);
            break;
        }
        return;
    }
}
@end
