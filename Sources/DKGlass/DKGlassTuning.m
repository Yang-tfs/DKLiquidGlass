//
//  DKGlassTuning.m
//

#import "DKGlassTuning.h"

const CGFloat DKGlassBarHeight   = 66.0;
const CGFloat DKGlassBarInset    = 26.0;
const CGFloat DKGlassPlusGap     = 14.0;
const BOOL    DKGlassContinuousCorner = YES;

const CGFloat DKGlassExtraBlurRadius   = 18.0;
const CGFloat DKGlassSaturationBoost   = 1.9;
const CGFloat DKGlassBrightnessLift    = 0.06;
// 默认关闭：私有 CAFilter 在 16.3.1 上的实际可用性未验证（本项目目前没有真机）。
// 关掉时观感靠「系统模糊 + 叠加层亮度」实现，是零私有 API 的安全路径。
// 想追那 5% 的饱和度差距，把它改成 YES 再上机二分校准。
const BOOL    DKGlassInjectFilters     = NO;

const CGFloat DKGlassRimTopAlpha       = 0.50;
const CGFloat DKGlassRimBottomAlpha    = 0.05;
const CGFloat DKGlassRimLineWidth      = 1.0;

const CGFloat DKGlassHairlineAlpha     = 0.14;
const CGFloat DKGlassHairlineWidth     = 0.5;

const CGFloat DKGlassInnerShadowAlpha  = 0.42;
const CGFloat DKGlassInnerShadowWidth  = 1.2;

const CGFloat DKGlassClearTintDarkAlpha  = 0.30;
const CGFloat DKGlassClearTintLightAlpha = 0.06;

const CGFloat DKGlassPressScale          = 0.962;
const NSTimeInterval DKGlassPressDuration = 0.26;
const CGFloat DKGlassSpecularDiameter    = 120.0;
const CGFloat DKGlassSpecularAlpha       = 0.30;

CGFloat DKGlassCapsuleRadius(CGFloat height) {
    return height / 2.0;
}

NSString *DKGlassTuningSummary(void) {
    return [NSString stringWithFormat:
            @"bar %.0fpt · blur +%.0f · sat %.2f · lift %+.2f · rim %.2f/%.2f · hairline %.2f · shadow %.2f · press %.3f",
            DKGlassBarHeight,
            DKGlassExtraBlurRadius,
            DKGlassSaturationBoost,
            DKGlassBrightnessLift,
            DKGlassRimTopAlpha,
            DKGlassRimBottomAlpha,
            DKGlassHairlineAlpha,
            DKGlassInnerShadowAlpha,
            DKGlassPressScale];
}
