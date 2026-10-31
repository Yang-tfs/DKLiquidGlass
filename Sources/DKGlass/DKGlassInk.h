//
//  DKGlassInk.h
//  内容极性判定与玻璃上的文字/图标配色。
//
//  核心判据来自一条实测结论：内容的黑白极性跟【底色】走，不跟深浅色模式走。
//  首页在浅色模式下也是黑视频，消息页在深色模式下也可能是黑底——外观模式说不清底色。
//
//  因此不读 UITraitCollection.userInterfaceStyle，而是读宿主自己给内容设的颜色：
//  宿主用黑系文字，说明它认为这块底色偏亮；我们也用黑系。
//

#ifndef DKGlassInk_h
#define DKGlassInk_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef NS_ENUM(NSInteger, DKGlassPolarity) {
    /// 底色偏亮 → 玻璃上的内容用黑系
    DKGlassPolarityLight = 0,
    /// 底色偏暗 → 玻璃上的内容用白系
    DKGlassPolarityDark  = 1,
};

typedef NS_ENUM(NSInteger, DKGlassMaterial) {
    DKGlassMaterialRegular = 0,
    DKGlassMaterialClear   = 1,
};

/// 是否黑系文字色。
/// 注意：不能只看饱和度。主文字色 #161823 是偏蓝的近黑，饱和度 0.37，
/// 单看饱和度会把它误判成彩色。必须明度与饱和度双阈值。
BOOL DKGlassColorIsInk(UIColor *color);

/// 该颜色是否为不透明纯黑（识别宿主编排用的黑色垫层）。
BOOL DKGlassColorIsOpaqueBlack(UIColor *color);

/// 两个颜色是否等价。玻璃是逐帧路径，用逐字段比较而不是 isEqual:，
/// 避免颜色空间或 alpha 归一化差异导致每次比较都判不等、白白重设一次材质。
BOOL DKGlassColorEquals(UIColor *a, UIColor *b);

/// 从宿主为内容设的文字色反推极性。color 为 nil 或无法判定时返回 fallback。
DKGlassPolarity DKGlassPolarityForHostColor(UIColor *hostColor, DKGlassPolarity fallback);

/// 玻璃上目标文字色：彩色与浅色原样返回；黑系按极性与材质转白，保留原 alpha 以维持主次层级。
UIColor *DKGlassReadableColor(UIColor *original, DKGlassPolarity polarity, DKGlassMaterial material);

/// Clear 档的染色。Regular 档返回 nil（系统材质自己处理，再叠会压暗两次）。
UIColor *DKGlassClearTint(DKGlassPolarity polarity);

/// 是否处于深色外观。降级路径用它决定染色方向；原生路径交给 overrideUserInterfaceStyle。
BOOL DKGlassIsDarkAppearance(UITraitCollection *traits);

#ifdef __cplusplus
}
#endif

#endif /* DKGlassInk_h */
