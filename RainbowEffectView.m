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
- (void)showKeyWaveAtPoint:(CGPoint)point hue:(CGFloat)hue mode:(NSInteger)mode {
    if (!self.keyFrames.count) return;
    CGFloat alpha = [self number:@"Opacity" fallback:.65 low:0 high:1];
    CGFloat brightness = [self number:@"Brightness" fallback:.95 low:0 high:1];
    CGFloat duration = [self number:@"Duration" fallback:.55 low:.15 high:1.2];
    CGFloat travel = [self number:@"BackgroundDuration" fallback:.4 low:.1 high:1.5];
    CGFloat spread = [self number:@"Spread" fallback:2 low:.5 high:3];
    CGFloat reach = [self number:@"BackgroundRadius" fallback:180 low:60 high:360] * spread / 2;
    CGFloat softness = [self number:@"Softness" fallback:8 low:0 high:24];
    CGFloat band = [self number:@"BackgroundBand" fallback:.55 low:.2 high:.85];
    CGFloat strength = [self number:@"BackgroundStrength" fallback:.18 low:0 high:.6];
    CGFloat core = [self number:@"CoreStrength" fallback:.5 low:0 high:1];
    BOOL propagate = [self flag:@"BackgroundFeedback"];
    CGRect pressed = CGRectNull;
    CGFloat nearest = CGFLOAT_MAX;
    for (NSValue *value in self.keyFrames) {
        CGRect rect = value.CGRectValue;
        CGFloat dx = MAX(MAX(CGRectGetMinX(rect) - point.x, 0), point.x - CGRectGetMaxX(rect));
        CGFloat dy = MAX(MAX(CGRectGetMinY(rect) - point.y, 0), point.y - CGRectGetMaxY(rect));
        CGFloat distance = hypot(dx, dy);
        if (distance < nearest) { nearest = distance; pressed = rect; }
    }
    // Ignore touches in padding / language-switch strips outside the actual keys.
    if (CGRectIsNull(pressed) || nearest > 14) return;
    CGPoint origin = CGPointMake(CGRectGetMidX(pressed), CGRectGetMidY(pressed));
    CALayer *pulse = [CALayer layer];
    pulse.frame = self.bounds;
    // Clip the entire wave, including blurred shadows and overlapping presses,
    // so no colored pixels bleed through an opaque key face.
    if ([self preservesBlackFaces]) pulse.mask = [self keyGutterMask];
    [self.layer addSublayer:pulse];
    CFTimeInterval now = [pulse convertTime:CACurrentMediaTime() fromLayer:nil];
    CGFloat tail = duration * (.45 + band);
    [self addAmbientGlowToPulse:pulse origin:origin radius:reach hue:hue mode:mode duration:travel + tail];
    for (NSUInteger index = 0; index < self.keyFrames.count; index++) {
        NSValue *value = self.keyFrames[index];
        CGRect rect = value.CGRectValue;
        BOOL touched = CGRectEqualToRect(rect, pressed);
        CGPoint center = [self.cachedCenters[index] CGPointValue];
        CGFloat distance = hypot(center.x - origin.x, center.y - origin.y);
        if ((!propagate && !touched) || distance > reach) continue;
        CGFloat progress = MIN(1, distance / reach);
        CGFloat keyHue = mode == 1 ? hue : fmod(hue + progress * .24, 1);
        UIColor *first = [UIColor colorWithHue:keyHue saturation:[self neonSaturation:.78] brightness:brightness alpha:1];
        UIColor *last = [UIColor colorWithHue:mode == 1 ? hue : fmod(keyHue + .12, 1)
                                 saturation:[self neonSaturation:.9] brightness:brightness alpha:1];
        CGFloat rimWidth = touched ? 3.0 : 2.6;
        // P1-3: 使用预构建的几何模板，省去每次按键的路径复制/坐标变换/圆角路径构建。
        RKKeyWaveGeometry *geometry = self.cachedWaveGeometries[index * 2 + (touched ? 1 : 0)];
        CALayer *key = [CALayer layer];
        key.name = @"keyWave";
        key.frame = geometry.edgeFrame;
        key.opacity = 0;
        [pulse addSublayer:key];

        CAShapeLayer *halo = [CAShapeLayer layer];
        halo.frame = key.bounds;
        halo.path = geometry.outline.CGPath;
        halo.fillColor = [self preservesBlackFaces] ? UIColor.clearColor.CGColor :
            [first colorWithAlphaComponent:touched ? core * .45 : strength * .12].CGColor;
        halo.strokeColor = [first colorWithAlphaComponent:.7].CGColor;
        halo.lineWidth = rimWidth * 2;
        halo.shadowColor = first.CGColor;
        halo.shadowOffset = CGSizeZero;
        halo.shadowRadius = softness * .6;
        halo.shadowOpacity = .8;
        // P1-4: 显式 shadowPath，省掉 CA 每帧自动计算阴影形状，像素结果一致。
        halo.shadowPath = geometry.outline.CGPath;
        [key addSublayer:halo];

        CAGradientLayer *edge = [CAGradientLayer layer];
        edge.frame = key.bounds;
        edge.colors = @[(id)first.CGColor, (id)last.CGColor];
        edge.startPoint = CGPointZero;
        edge.endPoint = CGPointMake(1, 1);
        CAShapeLayer *rim = [CAShapeLayer layer];
        rim.frame = key.bounds;
        // A filled outer ring keeps its full visible width after the black-face
        // exclusion mask; a centered stroke would lose its inner half.
        rim.path = geometry.outer.CGPath;
        rim.fillRule = kCAFillRuleEvenOdd;
        rim.fillColor = UIColor.whiteColor.CGColor;
        edge.mask = rim;
        [key addSublayer:edge];

        CGFloat peak = alpha * (1 - progress * .42);
        CAKeyframeAnimation *fade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        fade.values = @[@0, @(peak), @(peak * .72), @0];
        fade.keyTimes = @[@0, @.12, @.38, @1];
        fade.duration = tail;
        fade.beginTime = now + progress * travel;
        [key addAnimation:fade forKey:@"keyWave"];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((travel + tail + .05) * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [pulse removeFromSuperlayer]; });
}
- (void)showRippleAtPoint:(CGPoint)point {
    [self showRippleAtPoint:point sourceView:nil];
}
// Draw only in the free space BELOW key rectangles. Never shrink a key
// rectangle to manufacture a gap: an unknown/tight layout should show less
// light, rather than tint the keycap or its text.
- (void)showCrispUnderlightAtPoint:(CGPoint)point {
    CGRect pressed = CGRectNull;
    for (NSValue *value in self.keyFrames) {
        CGRect r = value.CGRectValue;
        if (CGRectContainsPoint(r, point) &&
            (CGRectIsNull(pressed) || r.size.width*r.size.height < pressed.size.width*pressed.size.height)) pressed = r;
    }
    if (CGRectIsNull(pressed)) return;
    CGFloat brightness = [self number:@"Brightness" fallback:.95 low:0 high:1];
    CGFloat opacity = [self number:@"Opacity" fallback:.65 low:0 high:1];
    if (brightness <= 0 || opacity <= 0) return;
    NSInteger mode = (NSInteger)[self number:@"ColorMode" fallback:0 low:0 high:2];
    self.hue = fmod(self.hue + .137, 1);
    CGFloat hue = mode == 1 ? [self number:@"Hue" fallback:.55 low:0 high:1] :
        (mode == 2 ? point.x/MAX(1,self.bounds.size.width) : self.hue);
    UIColor *color = [UIColor colorWithHue:hue saturation:[self neonSaturation:.9] brightness:brightness alpha:1];
    BOOL reduce = UIAccessibilityIsReduceMotionEnabled();
    BOOL fast = RKAdaptiveFastInput() || RKAdaptiveLevel() >= 2;
    NSUInteger limit = fast ? 1 : 2;
    while (self.layer.sublayers.count >= limit) [self.layer.sublayers.firstObject removeFromSuperlayer];
    CALayer *pulse = [CALayer layer];
    pulse.frame = self.bounds;
    pulse.name = @"RKCrispUnderlight";
    pulse.opacity = 0;
    CGPoint origin = CGPointMake(CGRectGetMidX(pressed),CGRectGetMidY(pressed));
    NSArray<NSValue *> *ordered = [self.keyFrames sortedArrayUsingComparator:^NSComparisonResult(NSValue *a, NSValue *b) {
        CGRect ar = a.CGRectValue, br = b.CGRectValue;
        CGFloat da = hypot(CGRectGetMidX(ar)-origin.x,CGRectGetMidY(ar)-origin.y);
        CGFloat db = hypot(CGRectGetMidX(br)-origin.x,CGRectGetMidY(br)-origin.y);
        return da < db ? NSOrderedAscending : (da > db ? NSOrderedDescending : NSOrderedSame);
    }];
    CGFloat reach = MIN(140,MAX(70,pressed.size.width*1.8));
    CFTimeInterval now = CACurrentMediaTime();
    NSUInteger count = 0;
    for (NSValue *value in ordered) {
        CGRect r = value.CGRectValue;
        CGFloat distance = hypot(CGRectGetMidX(r)-origin.x,CGRectGetMidY(r)-origin.y);
        if (distance > reach || count >= (fast || reduce ? 1u : 5u)) break;
        // A bright 1pt lower edge and a faint 1pt outer edge: no blur,
        // filled key faces, shadows, central flash or full-keyboard wash.
        for (NSUInteger edge = 0; edge < 2; edge++) {
            CGFloat y = CGRectGetMaxY(r) + 1 + edge*1.2;
            CGFloat x0 = CGRectGetMinX(r)+MIN(5,r.size.width*.15);
            CGFloat x1 = CGRectGetMaxX(r)-MIN(5,r.size.width*.15);
            if (y-.65 < CGRectGetMinY(self.bounds) || y+.65 > CGRectGetMaxY(self.bounds)) continue;
            NSMutableArray<NSValue *> *segments = [NSMutableArray arrayWithObject:[NSValue valueWithCGPoint:CGPointMake(x0,x1)]];
            // Clip the entire stroke footprint against EVERY detected key,
            // including adjacent rows, space/return keys and overlapping frames.
            for (NSValue *other in self.keyFrames) {
                CGRect blocked = CGRectInset(other.CGRectValue,-.25,-.65);
                if (y < CGRectGetMinY(blocked) || y > CGRectGetMaxY(blocked)) continue;
                NSMutableArray<NSValue *> *next = [NSMutableArray array];
                for (NSValue *segment in segments) {
                    CGPoint s = segment.CGPointValue;
                    CGFloat left = CGRectGetMinX(blocked), right = CGRectGetMaxX(blocked);
                    if (right <= s.x || left >= s.y) [next addObject:segment];
                    else {
                        if (left > s.x) [next addObject:[NSValue valueWithCGPoint:CGPointMake(s.x,MIN(left,s.y))]];
                        if (right < s.y) [next addObject:[NSValue valueWithCGPoint:CGPointMake(MAX(right,s.x),s.y)]];
                    }
                }
                segments = next;
            }
            UIBezierPath *path = [UIBezierPath bezierPath];
            for (NSValue *segment in segments) {
                CGPoint s = segment.CGPointValue;
                if (s.y-s.x < 1) continue;
                [path moveToPoint:CGPointMake(s.x,y)];
                [path addLineToPoint:CGPointMake(s.y,y)];
            }
            if (path.empty) continue;
            CAShapeLayer *line = [CAShapeLayer layer];
            line.frame = self.bounds;
            line.contentsScale = self.window.screen.scale;
            line.path = path.CGPath;
            line.fillColor = UIColor.clearColor.CGColor;
            line.strokeColor = color.CGColor;
            line.lineWidth = 1;
            line.lineCap = kCALineCapButt;
            line.opacity = 0;
            [pulse addSublayer:line];
            CAKeyframeAnimation *fade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
            CGFloat strength = (edge ? .2 : 1) * (1-.5*distance/reach);
            fade.values = @[@0,@(strength),@(strength*.7),@0];
            fade.keyTimes = @[@0,@.08,@.45,@1];
            fade.duration = fast ? .16 : .26;
            fade.beginTime = now + (reduce ? 0 : distance/reach*.09);
            [line addAnimation:fade forKey:@"underlightFade"];
        }
        count++;
    }
    if (!pulse.sublayers.count) return;
    [self.layer addSublayer:pulse];
    CABasicAnimation *life = [CABasicAnimation animationWithKeyPath:@"opacity"];
    life.fromValue = @(opacity); life.toValue = @(opacity);
    life.duration = .38;
    [pulse addAnimation:life forKey:@"underlightLifetime"];
    // Expired layers are transparent and evicted by the next press (max two).
    // No per-key dispatch_after queue and no persistent display-link animation.
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
    [self showCrispUnderlightAtPoint:point];
}
@end
