//
//  DKPreviewHook.xm
//  在 SpringBoard 桌面底部挂一条演示底栏。
//
//  这个文件存在的唯一目的：让「材质调参」这件事能脱离抖音单独验证。
//  装上 respring 就能看到玻璃，改 DKGlassTuning.m 里的数字重装就能对比——
//  不需要先打通任何宿主接入。
//
//  正式接入宿主（抖音或别的 App）时把这个目录整个从 Makefile 的 FILES 里去掉即可。
//

#import <UIKit/UIKit.h>
#import "DKGlassSurface.h"
#import "DKFloatingTabBar.h"
#import "DKGlassTuning.h"

static DKFloatingTabBar *gDKPreviewBar;
static const CGFloat kDKPreviewBottomInset = 34.0;

@interface DKPreviewDelegate : NSObject <DKFloatingTabBarDelegate>
@end

@implementation DKPreviewDelegate
- (void)floatingTabBar:(DKFloatingTabBar *)bar didSelectIndex:(NSInteger)index {
    NSLog(@"[DKLiquidGlass] preview tab -> %ld", (long)index);
}
- (void)floatingTabBarDidTapPlusKey:(DKFloatingTabBar *)bar {
    NSLog(@"[DKLiquidGlass] preview plus key");
}
@end

static DKPreviewDelegate *gDKPreviewDelegate;

static void DKPreviewInstall(void) {
    if (gDKPreviewBar) return;

    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
            if (candidate.isKeyWindow) { window = candidate; break; }
        }
        if (window) break;
    }
    if (!window) return;

    gDKPreviewDelegate = [[DKPreviewDelegate alloc] init];

    NSArray<NSString *> *symbols = @[@"house.fill", @"person.2.fill", @"bell.fill", @"person.crop.circle.fill"];
    NSMutableArray<DKFloatingTabItem *> *items = [NSMutableArray array];
    for (NSString *name in symbols) {
        UIImage *image = [UIImage systemImageNamed:name];
        [items addObject:[DKFloatingTabItem itemWithImage:image selectedImage:image title:nil]];
    }

    CGFloat width = CGRectGetWidth(window.bounds);
    DKFloatingTabBar *bar = [[DKFloatingTabBar alloc] initWithFrame:CGRectZero];
    bar.items = items;
    bar.delegate = gDKPreviewDelegate;
    bar.showsPlusKey = YES;
    bar.material = DKGlassMaterialRegular;
    bar.polarity = DKGlassPolarityDark;

    CGSize size = [bar preferredSizeForWidth:width];
    bar.frame = CGRectMake((width - size.width) / 2.0,
                           CGRectGetHeight(window.bounds) - size.height - kDKPreviewBottomInset,
                           size.width,
                           size.height);
    bar.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
                         | UIViewAutoresizingFlexibleRightMargin
                         | UIViewAutoresizingFlexibleTopMargin;

    [window addSubview:bar];
    gDKPreviewBar = bar;

    NSLog(@"[DKLiquidGlass] preview installed · %@", [DKGlassSurface capabilitySummary]);
}

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    // 等桌面视图树成型，避免把底栏挂到一个马上被替换的窗口上。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        DKPreviewInstall();
    });
}
%end
