//
//  DKHostAttach.m
//  宿主无关的挂载入口。
//
//  为什么需要它：
//  巨魔（TrollStore）环境下没有 MobileSubstrate，deb 根本不会被加载；
//  可行做法是用 TrollFools 把本插件编译出的 .dylib 注入进目标 App。
//  但注入进去以后，原来的 DKPreviewHook.xm 只 hook SpringBoard，在别的进程里什么都不做。
//
//  这个文件解决的就是这件事：不 hook 任何宿主类，只用公开 API ——
//  dylib 加载后等 App 激活，找到 key window，把底栏挂上去。
//  因此它对宿主版本完全免疫，抖音怎么改类名都不影响。
//
//  代价：拿不到宿主的 tab 切换能力（那需要 hook 宿主自己的控制器）。
//  这一版只用来验证材质观感与几何，底部圆键与 tab 点击只打日志。
//

#import <UIKit/UIKit.h>

#import "DKFloatingTabBar.h"
#import "DKGlassSurface.h"
#import "DKGlassTuning.h"

static const CGFloat kDKHostBottomInset = 92.0;

static DKFloatingTabBar *gDKHostBar;
static BOOL gDKHostAttaching;
static id gDKHostObservers;
static id gDKHostDelegate;
static id gDKHostDrag;

#pragma mark - 事件

@interface DKHostDelegate : NSObject <DKFloatingTabBarDelegate>
@end

@implementation DKHostDelegate
- (void)floatingTabBar:(DKFloatingTabBar *)bar didSelectIndex:(NSInteger)index {
    NSLog(@"[DKLiquidGlass] tab -> %ld（本版只验证材质，切页需接宿主控制器）", (long)index);
}
- (void)floatingTabBarDidTapPlusKey:(DKFloatingTabBar *)bar {
    NSLog(@"[DKLiquidGlass] plus key");
}
@end

#pragma mark - 拖动

/// 底栏可拖动。调试期必须能挪位置——否则它会和宿主自己的底栏叠在一起，看不清楚。
@interface DKHostDrag : NSObject
@end

@implementation DKHostDrag
- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *view = pan.view;
    UIView *host = view.superview;
    if (!view || !host) return;

    CGPoint translation = [pan translationInView:host];
    CGPoint center = view.center;
    center.x += translation.x;
    center.y += translation.y;
    view.center = center;
    [pan setTranslation:CGPointZero inView:host];
}
@end

#pragma mark - 挂载

static BOOL DKHostIsSpringBoard(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"];
}

static UIWindow *DKHostKeyWindow(void) {
    UIWindow *fallback = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (!window.isHidden && window.alpha > 0.01) {
                if (window.isKeyWindow) return window;
                if (!fallback) fallback = window;
            }
        }
    }
    return fallback;
}

static NSArray<DKFloatingTabItem *> *DKHostDefaultItems(void) {
    NSArray<NSString *> *symbols = @[@"house.fill", @"person.2.fill", @"bell.fill", @"person.crop.circle.fill"];
    NSMutableArray<DKFloatingTabItem *> *items = [NSMutableArray array];
    for (NSString *name in symbols) {
        UIImage *image = [UIImage systemImageNamed:name];
        [items addObject:[DKFloatingTabItem itemWithImage:image selectedImage:image title:nil]];
    }
    return items;
}

static void DKHostAttach(void) {
    if (gDKHostBar || gDKHostAttaching) return;
    if (DKHostIsSpringBoard()) return;   // 走 DKPreviewHook.xm 那条路

    UIWindow *window = DKHostKeyWindow();
    if (!window) return;

    gDKHostAttaching = YES;

    if (!gDKHostDelegate) gDKHostDelegate = [[DKHostDelegate alloc] init];
    if (!gDKHostDrag) gDKHostDrag = [[DKHostDrag alloc] init];

    CGFloat width = CGRectGetWidth(window.bounds);
    DKFloatingTabBar *bar = [[DKFloatingTabBar alloc] initWithFrame:CGRectZero];
    bar.items = DKHostDefaultItems();
    bar.delegate = gDKHostDelegate;
    bar.showsPlusKey = YES;
    bar.material = DKGlassMaterialRegular;
    bar.polarity = DKGlassPolarityDark;

    CGSize size = [bar preferredSizeForWidth:width];
    bar.frame = CGRectMake((width - size.width) / 2.0,
                           CGRectGetHeight(window.bounds) - size.height - kDKHostBottomInset,
                           size.width,
                           size.height);
    bar.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
                         | UIViewAutoresizingFlexibleRightMargin
                         | UIViewAutoresizingFlexibleTopMargin;

    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:gDKHostDrag action:@selector(handlePan:)];
    [bar addGestureRecognizer:pan];

    [window addSubview:bar];
    gDKHostBar = bar;
    gDKHostAttaching = NO;

    NSLog(@"[DKLiquidGlass] 已挂载 · %@ · %@",
          NSBundle.mainBundle.bundleIdentifier,
          [DKGlassSurface capabilitySummary]);
}

static void DKHostDetach(void) {
    [gDKHostBar removeFromSuperview];
    gDKHostBar = nil;
}

#pragma mark - 入口

__attribute__((constructor))
static void DKHostAttachCtor(void) {
    // 构造期 UIApplication 可能还没建好，延迟到主队列注册。
    dispatch_async(dispatch_get_main_queue(), ^{
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        id active = [center addObserverForName:UIApplicationDidBecomeActiveNotification
                                        object:nil
                                         queue:NSOperationQueue.mainQueue
                                    usingBlock:^(__unused NSNotification *note) {
            // 宿主可能重建窗口，稍等一下再挂，避免挂到一个正在被替换的窗口上。
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                DKHostAttach();
            });
        }];
        id background = [center addObserverForName:UIApplicationDidEnterBackgroundNotification
                                            object:nil
                                             queue:NSOperationQueue.mainQueue
                                        usingBlock:^(__unused NSNotification *note) {
            DKHostDetach();
        }];
        gDKHostObservers = @[active, background];
    });
}
