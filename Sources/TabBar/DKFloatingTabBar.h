//
//  DKFloatingTabBar.h
//  悬浮胶囊底栏：4 个 tab 的玻璃胶囊 + 右侧独立玻璃圆键。
//
//  与宿主的耦合为零——不依赖任何 App 的类。接入宿主时只需要提供 items 和
//  一个 selectedIndex 的读写回调，点击怎么切页由宿主决定。
//
//  几何全部自己算，不需要像 iOS 26 那样去反解系统私有 platter 视图的尺寸。
//

#ifndef DKFloatingTabBar_h
#define DKFloatingTabBar_h

#import <UIKit/UIKit.h>
#import "DKGlassSurface.h"

NS_ASSUME_NONNULL_BEGIN

@interface DKFloatingTabItem : NSObject
@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, strong, nullable) UIImage *image;
@property (nonatomic, strong, nullable) UIImage *selectedImage;
+ (instancetype)itemWithImage:(nullable UIImage *)image
                selectedImage:(nullable UIImage *)selectedImage
                        title:(nullable NSString *)title;
@end

@class DKFloatingTabBar;

@protocol DKFloatingTabBarDelegate <NSObject>
/// 点了某个 tab。宿主在这里切页。
- (void)floatingTabBar:(DKFloatingTabBar *)bar didSelectIndex:(NSInteger)index;
@optional
/// 点了右侧圆键。
- (void)floatingTabBarDidTapPlusKey:(DKFloatingTabBar *)bar;
@end

@interface DKFloatingTabBar : UIView

@property (nonatomic, copy) NSArray<DKFloatingTabItem *> *items;
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, assign) BOOL showsPlusKey;
@property (nonatomic, assign) DKGlassMaterial material;
@property (nonatomic, assign) DKGlassPolarity polarity;
@property (nonatomic, weak, nullable) id<DKFloatingTabBarDelegate> delegate;

/// 给一个可用宽度，返回整个底栏（胶囊 + 圆键 + 间距）应占的尺寸。
- (CGSize)preferredSizeForWidth:(CGFloat)availableWidth;

/// 外观变化时调用。原生 Regular 档只改 overrideUserInterfaceStyle，不重建材质。
- (void)applyPolarity:(DKGlassPolarity)polarity;

/// 当前是否用上了系统原生玻璃，供设置页展示。
- (BOOL)usesNativeGlass;

@end

NS_ASSUME_NONNULL_END

#endif /* DKFloatingTabBar_h */
