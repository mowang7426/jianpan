from pathlib import Path
p=Path('/var/minis/workspace/jianpan/RainbowEffectView.m')
s=p.read_text()
marker='\n\n- (void)showRippleAtPoint:(CGPoint)point sourceView:(UIView *)sourceView {'
method=r'''

- (void)showKeyBottomSpreadAtPoint:(CGPoint)point {
    CGRect key=[self pressedKeyAtPoint:point];
    if (CGRectIsNull(key) || CGRectIsEmpty(self.bounds)) return;
    for (CALayer *layer in self.layer.sublayers.copy)
        if ([layer.name isEqualToString:@"RKKeyBottomSpread"]) [layer removeFromSuperlayer];
    CGFloat alpha=[self number:@"Opacity" fallback:.65 low:0 high:1];
    CGFloat brightness=[self number:@"Brightness" fallback:.95 low:0 high:1];
    if (alpha<=0 || brightness<=0) return;
    self.hue=fmod(self.hue+.11,1);
    UIColor *color=[UIColor colorWithHue:self.hue saturation:.88 brightness:brightness alpha:1];
    CGPoint origin=CGPointMake(CGRectGetMidX(key),CGRectGetMaxY(key)+2);
    CGFloat reach=MIN(MAX(self.bounds.size.width,self.bounds.size.height)*.72,360);
    CGFloat duration=MIN(.95,MAX(.58,[self number:@"Duration" fallback:.7 low:.15 high:1.2]));
    CALayer *pulse=[CALayer layer]; pulse.name=@"RKKeyBottomSpread"; pulse.frame=self.bounds; pulse.opacity=0;
    pulse.mask=[self waveUnderCapMask];
    CAGradientLayer *wash=[CAGradientLayer layer]; wash.type=kCAGradientLayerRadial;
    wash.frame=CGRectMake(origin.x-reach,origin.y-reach,reach*2,reach*2);
    wash.startPoint=CGPointMake(.5,.5); wash.endPoint=CGPointMake(1,1);
    wash.colors=@[(id)[color colorWithAlphaComponent:.95].CGColor,
                  (id)[color colorWithAlphaComponent:.62].CGColor,
                  (id)[color colorWithAlphaComponent:.18].CGColor,
                  (id)[color colorWithAlphaComponent:0].CGColor];
    wash.locations=@[@0,@.16,@.52,@1];
    [pulse addSublayer:wash]; [self.layer addSublayer:pulse];
    CABasicAnimation *spread=[CABasicAnimation animationWithKeyPath:@"transform.scale"];
    spread.fromValue=@.035; spread.toValue=@1.0; spread.duration=duration;
    spread.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [wash addAnimation:spread forKey:@"bottomLightSpread"];
    CAShapeLayer *originGlow=[CAShapeLayer layer]; originGlow.frame=self.bounds;
    CGFloat w=MAX(18,key.size.width*.72), h=MAX(7,key.size.height*.16);
    originGlow.path=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(origin.x-w/2,origin.y-h/2,w,h) cornerRadius:h/2].CGPath;
    originGlow.fillColor=[color colorWithAlphaComponent:alpha].CGColor;
    originGlow.shadowColor=color.CGColor; originGlow.shadowRadius=12; originGlow.shadowOpacity=.9;
    [pulse addSublayer:originGlow];
    CAKeyframeAnimation *originFade=[CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    originFade.values=@[@0,@1,@.55,@0]; originFade.keyTimes=@[@0,@.08,@.35,@1]; originFade.duration=duration+.2;
    [originGlow addAnimation:originFade forKey:@"bottomGlowFade"];
    CAKeyframeAnimation *life=[CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    life.values=@[@0,@(alpha),@(alpha*.78),@0]; life.keyTimes=@[@0,@.08,@.62,@1]; life.duration=duration+.22;
    [pulse addAnimation:life forKey:@"bottomSpreadFade"];
}
'''
assert marker in s
s=s.replace(marker,method+marker,1)
s=s.replace('high:7];','high:6];',1)
s=s.replace('if(style==7){[self showGapFlowAtPoint:point];return;}\n','if(style==6){[self showKeyBottomSpreadAtPoint:point];return;}\n',1)
p.write_text(s)

q=Path('/var/minis/workspace/jianpan/RainbowKeyboardPrefs/RKBRootListController.m')
t=q.read_text()
t=t.replace('@["波纹", @"扩散", @"轻弹", @"流光底韵", @"RGB 底板氛围", @"机械波", @"余烬残光", @"底部缝隙传光"]','@["波纹", @"扩散", @"轻弹", @"流光底韵", @"RGB 底板氛围", @"机械波", @"键底扩散"]')
t=t.replace('@[@0, @1, @2, @3, @4, @5, @6, @7]','@[@0, @1, @2, @3, @4, @5, @6]')
q.write_text(t)
