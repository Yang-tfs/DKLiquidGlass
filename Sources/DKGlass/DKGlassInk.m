//
//  DKGlassInk.m
//

#import "DKGlassInk.h"

#import <math.h>
#import "DKGlassTuning.h"

BOOL DKGlassColorIsInk(UIColor *color) {
    if (!color) return NO;
    CGFloat h = 0, s = 0, b = 0, a = 0;
    if (![color getHue:&h saturation:&s brightness:&b alpha:&a]) {
        // 灰度色走不到 getHue:，直接按亮度判。
        CGFloat w = 0;
        if (![color getWhite:&w alpha:&a]) return NO;
        return w < 0.4;
    }
    // 双阈值：够暗 且 不够艳。缺一不可。
    return b < 0.40 && s < 0.55;
}

BOOL DKGlassColorIsOpaqueBlack(UIColor *color) {
    if (!color) return NO;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) return NO;
    return a > 0.98 && r < 0.03 && g < 0.03 && b < 0.03;
}

BOOL DKGlassColorEquals(UIColor *a, UIColor *b) {
    if (a == b) return YES;
    if (!a || !b) return NO;
    CGFloat ar = 0, ag = 0, ab = 0, aa = 0;
    CGFloat br = 0, bg = 0, bb = 0, ba = 0;
    if (![a getRed:&ar green:&ag blue:&ab alpha:&aa]) return NO;
    if (![b getRed:&br green:&bg blue:&bb alpha:&ba]) return NO;
    // 量化到 1/255 再比，避开浮点尾差。
    const CGFloat q = 255.0;
    return round(ar * q) == round(br * q)
        && round(ag * q) == round(bg * q)
        && round(ab * q) == round(bb * q)
        && round(aa * q) == round(ba * q);
}

DKGlassPolarity DKGlassPolarityForHostColor(UIColor *hostColor, DKGlassPolarity fallback) {
    if (!hostColor) return fallback;
    CGFloat a = 0;
    [hostColor getWhite:NULL alpha:&a];
    // 过渡态里宿主会把文字整体淡出，那一帧的色不能用来判极性。
    if (a < 0.5) return fallback;
    // 宿主用黑系 → 它认为底色偏亮。
    return DKGlassColorIsInk(hostColor) ? DKGlassPolarityLight : DKGlassPolarityDark;
}

BOOL DKGlassIsDarkAppearance(UITraitCollection *traits) {
    return traits.userInterfaceStyle == UIUserInterfaceStyleDark;
}

UIColor *DKGlassClearTint(DKGlassPolarity polarity) {
    // 深色底 → 压一层黑，让玻璃沉下去；浅色底 → 提一点点白，制造通透感。
    if (polarity == DKGlassPolarityDark) {
        return [UIColor colorWithWhite:0.0 alpha:DKGlassClearTintDarkAlpha];
    }
    return [UIColor colorWithWhite:1.0 alpha:DKGlassClearTintLightAlpha];
}

UIColor *DKGlassReadableColor(UIColor *original, DKGlassPolarity polarity, DKGlassMaterial material) {
    if (!original) return nil;
    if (!DKGlassColorIsInk(original)) return original;   // 彩色原样

    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![original getRed:&r green:&g blue:&b alpha:&a]) return original;

    if (polarity == DKGlassPolarityLight) {
        // 底色亮，黑系文字本来就对，但清透档要压一点对比度
        if (material == DKGlassMaterialClear) {
            return [UIColor colorWithWhite:0.0 alpha:a];
        }
        return original;
    }
    // 底色暗，黑系必须转白，保留原 alpha 以维持主 / 次文字层级
    return [UIColor colorWithWhite:1.0 alpha:a];
}
