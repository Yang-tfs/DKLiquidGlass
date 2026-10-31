//
//  DKHostAttach.m
//  宿主无关的挂载入口 + 自诊断。
//
//  为什么需要它：
//  巨魔（TrollStore）环境没有 MobileSubstrate，deb 不会被加载；
//  可行做法是用 TrollFools 把本插件编出的 .dylib 注入目标 App。
//  但 DKPreviewHook.xm 只 hook SpringBoard，在别的进程里什么都不做。
//
//  这里不 hook 任何宿主类，只用公开 API：等 App 起来，找 key window 挂底栏。
//  对宿主版本完全免疫，抖音怎么改类名都不影响。
//
//  自诊断（没有 Mac 也能查）：
//  全程写 <App容器>/Documents/DKLiquidGlass.log。用 Filza 打开目标 App 的
//  沙盒就能看。文件不存在 = dylib 根本没被加载；存在但有 attach 失败记录 =
//  加载了但没挂上。
//

#import <UIKit/UIKit.h>

#import "DKFloatingTabBar.h"
#import "DKGlassSurface.h"
#import "DKGlassTuning.h"

static const CGFloat kDKHostBottomInset = 92.0;
static const NSUInteger kDKHostMaxAttempts = 40;
static const NSTimeInterval kDKHostRetryInterval = 0.8;

static DKFloatingTabBar *gDKHostBar;
static dispatch_source_t gDKHostTimer;
static NSUInteger gDKHostAttempts;
static id gDKHostDelegate;
static id gDKHostDrag;
static BOOL gDKHostLoggedOnce;
static NSString *gDKHostLogPath;

#pragma mark - 自诊断日志

static void DKDiagLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSLog(@"[DKLiquidGlass] %@", message);

    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm:ss.SSS";
    });

    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [formatter stringFromDate:NSDate.date], message];

    if (!gDKHostLogPath) {
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        if (!docs) return;
        gDKHostLogPath = [docs stringByAppendingPathComponent:@"DKLiquidGlass.log"];
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:gDKHostLogPath];
    if (!handle) {
        [[NSFileManager defaultManager] createFileAtPath:gDKHostLogPath contents:nil attributes:nil];
        handle = [NSFileHandle fileHandleForWritingAtPath:gDKHostLogPath];
    }
    if (!handle) return;
    @try {
        [handle seekToEndOfFile];
        [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    } @catch (__unused NSException *e) {}
}

/// 日志文件路径，供外部提示用户去哪里找。
NSString *DKHostDiagnosticsPath(void) {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return docs ? [docs stringByAppendingPathComponent:@"DKLiquidGlass.log"] : nil;
}

#pragma mark - 事件

@interface DKHostDelegate : NSObject <DKFloatingTabBarDelegate>
@end

@implementation DKHostDelegate
- (void)floatingTabBar:(DKFloatingTabBar *)bar didSelectIndex:(NSInteger)index {
    DKDiagLog(@"点击 tab -> %ld（本版只验证材质，切页需接宿主控制器）", (long)index);
}
- (void)floatingTabBarDidTapPlusKey:(DKFloatingTabBar *)bar {
    DKDiagLog(@"点击拍摄键");
}
@end

#pragma mark - 拖动

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
    UIWindow *best = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isHidden || window.alpha < 0.01) continue;
            if (window.isKeyWindow) return window;
            if (!best) best = window;
        }
    }
    // 场景 API 拿不到时退回旧的 windows 数组（TrollFools 注入的宿主可能没有场景委托）
    if (!best) {
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            if (!window.isHidden && window.alpha > 0.01) best = window;
        }
    }
    return best;
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

static BOOL DKHostAttach(void) {
    if (DKHostIsSpringBoard()) return YES;   // 走 DKPreviewHook.xm 那条路
    if (gDKHostBar.superview) return YES;    // 已经挂上了

    UIWindow *window = DKHostKeyWindow();
    if (!window) return NO;

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

    DKDiagLog(@"已挂载到 %@ · window=%@ frame=%@",
              NSBundle.mainBundle.bundleIdentifier,
              NSStringFromClass(window.class),
              NSStringFromCGRect(bar.frame));
    return YES;
}

static void DKHostStopTimer(void) {
    if (gDKHostTimer) {
        dispatch_source_cancel(gDKHostTimer);
        gDKHostTimer = nil;
    }
}

/// 轮询直到挂上。为什么不只用通知：
/// dylib 在进程启动早期加载，注册通知又是异步的，如果 App 已经处于激活态，
/// UIApplicationDidBecomeActiveNotification 早就发过了，只等通知会永远等不到。
static void DKHostStartRetryLoop(void) {
    if (gDKHostTimer) return;
    if (DKHostAttach()) return;

    gDKHostAttempts = 0;
    gDKHostTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(gDKHostTimer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDKHostRetryInterval * NSEC_PER_SEC)),
                              (uint64_t)(kDKHostRetryInterval * NSEC_PER_SEC),
                              (uint64_t)(0.1 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(gDKHostTimer, ^{
        gDKHostAttempts++;
        if (DKHostAttach()) {
            DKHostStopTimer();
            return;
        }
        if (gDKHostAttempts >= kDKHostMaxAttempts) {
            DKDiagLog(@"放弃挂载：%lu 次都没找到可用 window", (unsigned long)gDKHostMaxAttempts);
            DKHostStopTimer();
        }
    });
    dispatch_resume(gDKHostTimer);
}

__attribute__((constructor))
static void DKHostAttachCtor(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gDKHostLoggedOnce) return;
        gDKHostLoggedOnce = YES;

        DKDiagLog(@"dylib 已加载 · bundle=%@ · %@",
                  NSBundle.mainBundle.bundleIdentifier ?: @"(nil)",
                  [DKGlassSurface capabilitySummary]);

        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        for (NSString *name in @[UIApplicationDidFinishLaunchingNotification,
                                 UIApplicationDidBecomeActiveNotification,
                                 UIApplicationWillEnterForegroundNotification]) {
            [center addObserverForName:name
                                object:nil
                                 queue:NSOperationQueue.mainQueue
                            usingBlock:^(__unused NSNotification *note) {
                DKHostStartRetryLoop();
            }];
        }
        [center addObserverForName:UIApplicationDidEnterBackgroundNotification
                            object:nil
                             queue:NSOperationQueue.mainQueue
                        usingBlock:^(__unused NSNotification *note) {
        }];

        // 不等通知，立刻试一次：App 可能已经在前台了。
        DKHostStartRetryLoop();
    });
}
