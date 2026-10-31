//
//  DKGlassTuning.h
//  材质参数与私有滤镜的集中调控台。
//
//  设计原则：所有"需要上真机二分校准"的数字只出现在这个文件里。
//  调材质观感不需要碰任何逻辑代码。
//

#ifndef DKGlassTuning_h
#define DKGlassTuning_h

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

#pragma mark - 几何

/// 悬浮胶囊高度。圆角恒为高度的一半（胶囊形）。
extern const CGFloat DKGlassBarHeight;
/// 胶囊左右距屏幕边缘的最小内缩。
extern const CGFloat DKGlassBarInset;
/// 独立圆键（拍摄键）与胶囊之间的间距。
extern const CGFloat DKGlassPlusGap;
/// 合成圆角半径：高度一半，保证两端是正圆弧。
CGFloat DKGlassCapsuleRadius(CGFloat height);

#pragma mark - 圆角

/// 是否使用连续曲率（squircle）。iOS 13+ 与 iOS 26 的 UICornerConfiguration 渲染一致。
extern const BOOL DKGlassContinuousCorner;

#pragma mark - 降级路径（iOS 16）的滤镜参数

// 这些值只在没有 UIGlassEffect 的系统上生效。
// 每一项都需要在真机上与 iOS 26 参考机型并排比对后二分调整。
// 改动前先读 docs/design.md 的「校准方法」一节。

/// 额外模糊半径（pt）。系统材质自带模糊，这里是追加量。
/// 起点 18：比系统 Chrome 材质更糊，接近 Clear 档的观感。
extern const CGFloat DKGlassExtraBlurRadius;

/// 饱和度倍率。iOS 26 玻璃的饱和度明显高于 iOS 16 的系统材质，起点 1.9。
extern const CGFloat DKGlassSaturationBoost;

/// 亮度偏移。-1.0 ~ 1.0，起点 0.06。这是"玻璃亮起来"的主要来源。
extern const CGFloat DKGlassBrightnessLift;

/// 是否向 backdrop 注入滤镜。私有 API 在新系统上可能不存在，探测失败会自动跳过。
extern const BOOL DKGlassInjectFilters;

#pragma mark - 边缘装饰

/// 顶边高光的起始不透明度。起点 0.50。
extern const CGFloat DKGlassRimTopAlpha;
/// 顶边高光衰减到底部时的不透明度。起点 0.05。
extern const CGFloat DKGlassRimBottomAlpha;
/// 顶边高光的线宽（pt）。
extern const CGFloat DKGlassRimLineWidth;

/// 内壁四周极细描边的不透明度。起点 0.14，这是"玻璃有厚度"的关键。
extern const CGFloat DKGlassHairlineAlpha;
/// 内壁描边线宽（pt）。0.5 在 @3x 上正好是 1.5 物理像素，视觉上是一条干净的暗线。
extern const CGFloat DKGlassHairlineWidth;

/// 底部内阴影的强度。起点 0.42，压在底边上制造厚度。
extern const CGFloat DKGlassInnerShadowAlpha;
/// 底部内阴影的线宽（pt）。
extern const CGFloat DKGlassInnerShadowWidth;

#pragma mark - 染色

/// Clear 档在深色外观下的染色黑度。起点 0.30。
/// Regular 档不染色：系统材质自己会处理，再叠会压暗两次。
extern const CGFloat DKGlassClearTintDarkAlpha;
/// Clear 档在浅色外观下的染色白度。起点 0.06。
extern const CGFloat DKGlassClearTintLightAlpha;

#pragma mark - 触摸反馈

/// 按下时的缩放。1.0 为不缩放，起点 0.962。
extern const CGFloat DKGlassPressScale;
/// 按下的动画时长（秒）。
extern const NSTimeInterval DKGlassPressDuration;
/// 柔光斑直径（pt）。
extern const CGFloat DKGlassSpecularDiameter;
/// 柔光斑最大不透明度。
extern const CGFloat DKGlassSpecularAlpha;

#pragma mark - 上报

/// 当前参数快照，供调试面板与日志输出。
NSString *DKGlassTuningSummary(void);

#ifdef __cplusplus
}
#endif

#endif /* DKGlassTuning_h */
