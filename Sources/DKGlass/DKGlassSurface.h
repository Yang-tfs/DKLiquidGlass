//
//  DKGlassSurface.h
//  一块液态玻璃材质。iOS 26 走系统 UIGlassEffect；iOS 16 用叠加层自绘降级。
//
//  调用方只认这一个类，不需要判断系统版本。版本分叉全部收在 DKGlassSurface.m 里。
//
//  为什么这么设计：
//  DKGlassSurface 之外的所有代码（底栏、面板、弹层）都只写一遍，将来 iOS 27 换了
//  新的材质 API，改动也只落在这一个文件。
//

#ifndef DKGlassSurface_h
#define DKGlassSurface_h

#import <UIKit/UIKit.h>
#import "DKGlassInk.h"

NS_ASSUME_NONNULL_BEGIN

@interface DKGlassSurface : UIVisualEffectView

/// 材质档位。改变时会重建材质（清透与磨砂是两套渲染，无法原地切换）。
@property (nonatomic, assign, readonly) DKGlassMaterial material;

/// 内容极性：决定玻璃上的文字与图标用黑系还是白系。
@property (nonatomic, assign, readonly) DKGlassPolarity polarity;

/// 圆角半径。传 0 表示按当前高度取胶囊形（height / 2）。
@property (nonatomic, assign) CGFloat cornerRadius;

/// 边缘装饰（顶边高光 + 内壁暗环 + 细描边）。这是"玻璃有厚度"的主要来源。
@property (nonatomic, assign) BOOL rimEnabled;

/// 触摸反馈。原生路径下由 UIGlassEffect.interactive 提供；降级路径下是近似效果。
@property (nonatomic, assign) BOOL pressFeedbackEnabled;

/// 当前是否真的用上了系统原生玻璃。iOS 26 以下恒为 NO。
@property (nonatomic, assign, readonly) BOOL usesNativeGlass;

- (instancetype)initWithMaterial:(DKGlassMaterial)material NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithEffect:(nullable UIVisualEffect *)effect NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

- (void)setMaterial:(DKGlassMaterial)material animated:(BOOL)animated;
- (void)setPolarity:(DKGlassPolarity)polarity animated:(BOOL)animated;

/// 系统是否提供 UIGlassEffect。进程内只算一次。
+ (BOOL)nativeGlassAvailable;

/// 能力与参数快照，用于调试日志与设置页展示。
+ (NSString *)capabilitySummary;

@end

NS_ASSUME_NONNULL_END

#endif /* DKGlassSurface_h */
