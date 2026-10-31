//
//  main.m
//  DKLiquidGlassDemo
//
//  独立的材质验证 App。
//
//  存在的理由：巨魔环境下往抖音注入 dylib 要闯三关——FairPlay 加密、App 完整性校验、
//  TrollFools 自身的兼容性。任何一关没过，屏幕上就什么都没有，而且没有 Mac 就看不了日志。
//
//  这个 App 用 TrollStore 直接装 IPA，不注入、不越狱、不改任何别人的进程。
//  底部那条玻璃底栏就是 DKFloatingTabBar 本身，和将来接进抖音的是同一份代码。
//  顶部控件可以现场切材质与极性，用来定 DKGlassTuning.m 里的参数。
//

#import <UIKit/UIKit.h>

#import "DKFloatingTabBar.h"
#import "DKGlassSurface.h"
#import "DKGlassTuning.h"

static CAGradientLayer *DKMakeGradient(NSArray<UIColor *> *colors, CGRect frame) {
    CAGradientLayer *layer = [CAGradientLayer layer];
    NSMutableArray *cgColors = [NSMutableArray array];
    for (UIColor *color in colors) {
        [cgColors addObject:(id)color.CGColor];
    }
    layer.colors = cgColors;
    layer.startPoint = CGPointMake(0.0, 0.0);
    layer.endPoint = CGPointMake(1.0, 1.0);
    layer.frame = frame;
    return layer;
}

#pragma mark - 内容视图

/// 铺满彩色渐变的滚动内容。玻璃必须压在有色彩梯度的画面上才看得出差别，
/// 纯色背景上「模糊」和「真玻璃」几乎一样。
@interface DKDemoViewController : UIViewController <DKFloatingTabBarDelegate>

@property (nonatomic, strong) DKFloatingTabBar *bar;
@property (nonatomic, strong) UISegmentedControl *materialControl;
@property (nonatomic, strong) UISegmentedControl *polarityControl;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIScrollView *scrollView;

@end

@implementation DKDemoViewController {
    CAGradientLayer *_background;
    NSMutableArray<CAGradientLayer *> *_cardGradients;
    NSMutableArray<UIView *> *_cards;
}

static NSArray<NSArray<UIColor *> *> *DKCardPalette(void) {
    return @[
        @[[UIColor colorWithRed:0.36 green:0.20 blue:0.72 alpha:1.0],
          [UIColor colorWithRed:0.12 green:0.72 blue:0.66 alpha:1.0]],
        @[[UIColor colorWithRed:0.92 green:0.32 blue:0.28 alpha:1.0],
          [UIColor colorWithRed:0.96 green:0.66 blue:0.18 alpha:1.0]],
        @[[UIColor colorWithRed:0.10 green:0.42 blue:0.86 alpha:1.0],
          [UIColor colorWithRed:0.44 green:0.16 blue:0.78 alpha:1.0]],
        @[[UIColor colorWithRed:0.10 green:0.62 blue:0.42 alpha:1.0],
          [UIColor colorWithRed:0.62 green:0.82 blue:0.24 alpha:1.0]],
        @[[UIColor colorWithRed:0.86 green:0.18 blue:0.46 alpha:1.0],
          [UIColor colorWithRed:0.48 green:0.22 blue:0.86 alpha:1.0]],
        @[[UIColor colorWithRed:0.16 green:0.16 blue:0.20 alpha:1.0],
          [UIColor colorWithRed:0.42 green:0.44 blue:0.52 alpha:1.0]],
    ];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1.0];

    _cardGradients = [NSMutableArray array];
    _cards = [NSMutableArray array];

    _background = DKMakeGradient(@[[UIColor colorWithRed:0.10 green:0.09 blue:0.16 alpha:1.0],
                                   [UIColor colorWithRed:0.06 green:0.05 blue:0.10 alpha:1.0]],
                                 self.view.bounds);
    [self.view.layer addSublayer:_background];

    [self dk_buildContent];
    [self dk_buildPanel];
}

- (void)dk_buildContent {
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    scroll.alwaysBounceVertical = YES;
    scroll.showsVerticalScrollIndicator = NO;
    [self.view addSubview:scroll];
    self.scrollView = scroll;

    NSArray<NSArray<UIColor *> *> *palette = DKCardPalette();
    for (NSUInteger i = 0; i < palette.count; i++) {
        UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
        card.layer.cornerRadius = 22.0;
        card.layer.cornerCurve = kCACornerCurveContinuous;
        card.layer.masksToBounds = YES;
        [scroll addSubview:card];
        [_cards addObject:card];

        CAGradientLayer *gradient = DKMakeGradient(palette[i], CGRectZero);
        [card.layer addSublayer:gradient];
        [_cardGradients addObject:gradient];

        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.text = [NSString stringWithFormat:@"材质验证 %lu", (unsigned long)(i + 1)];
        label.font = [UIFont systemFontOfSize:26 weight:UIFontWeightSemibold];
        label.textColor = [UIColor colorWithWhite:1.0 alpha:0.92];
        label.tag = 900;
        [card addSubview:label];
    }
}

- (void)dk_buildPanel {
    _materialControl = [[UISegmentedControl alloc] initWithItems:@[@"磨砂 Regular", @"清透 Clear"]];
    _materialControl.selectedSegmentIndex = 0;
    [_materialControl addTarget:self action:@selector(dk_materialChanged)
               forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_materialControl];

    _polarityControl = [[UISegmentedControl alloc] initWithItems:@[@"深底", @"浅底"]];
    _polarityControl.selectedSegmentIndex = 0;
    [_polarityControl addTarget:self action:@selector(dk_polarityChanged)
               forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_polarityControl];

    _statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _statusLabel.numberOfLines = 0;
    _statusLabel.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    _statusLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.62];
    [self.view addSubview:_statusLabel];

    for (UISegmentedControl *control in @[_materialControl, _polarityControl]) {
        if (@available(iOS 13.0, *)) {
            control.selectedSegmentTintColor = [UIColor colorWithWhite:1.0 alpha:0.18];
        }
        [control setTitleTextAttributes:@{ NSForegroundColorAttributeName: UIColor.whiteColor }
                               forState:UIControlStateNormal];
    }
}

#pragma mark - 布局

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGRect bounds = self.view.bounds;
    _background.frame = bounds;

    CGFloat top = self.view.safeAreaInsets.top + 8.0;
    CGFloat panelWidth = bounds.size.width - 32.0;

    _materialControl.frame = CGRectMake(16.0, top, panelWidth, 32.0);
    _polarityControl.frame = CGRectMake(16.0, top + 40.0, panelWidth, 32.0);
    _statusLabel.frame = CGRectMake(16.0, top + 80.0, panelWidth, 44.0);

    CGFloat contentTop = top + 132.0;
    CGFloat cardHeight = 190.0;
    CGFloat gap = 14.0;
    CGFloat y = 0.0;

    _scrollView.frame = CGRectMake(0, contentTop, bounds.size.width,
                                   bounds.size.height - contentTop);

    for (NSUInteger i = 0; i < _cards.count; i++) {
        UIView *card = _cards[i];
        card.frame = CGRectMake(16.0, y, bounds.size.width - 32.0, cardHeight);
        _cardGradients[i].frame = card.bounds;

        UILabel *label = [card viewWithTag:900];
        label.frame = CGRectMake(20.0, cardHeight - 56.0, card.bounds.size.width - 40.0, 36.0);

        y += cardHeight + gap;
    }
    _scrollView.contentSize = CGSizeMake(bounds.size.width, y + 140.0);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self dk_installBarIfNeeded];
}

- (void)dk_installBarIfNeeded {
    if (self.bar) return;

    NSArray<NSString *> *symbols = @[@"house.fill", @"person.2.fill", @"bell.fill",
                                     @"person.crop.circle.fill"];
    NSMutableArray<DKFloatingTabItem *> *items = [NSMutableArray array];
    for (NSString *name in symbols) {
        UIImage *image = [UIImage systemImageNamed:name];
        [items addObject:[DKFloatingTabItem itemWithImage:image selectedImage:image title:nil]];
    }

    DKFloatingTabBar *bar = [[DKFloatingTabBar alloc] initWithFrame:CGRectZero];
    bar.items = items;
    bar.delegate = self;
    bar.showsPlusKey = YES;
    bar.material = DKGlassMaterialRegular;
    bar.polarity = DKGlassPolarityDark;
    [self.view addSubview:bar];
    self.bar = bar;

    [self dk_relayoutBar];
    [self dk_refreshStatus];
}

- (void)dk_relayoutBar {
    if (!self.bar) return;
    CGSize size = [self.bar preferredSizeForWidth:self.view.bounds.size.width];
    self.bar.frame = CGRectMake((self.view.bounds.size.width - size.width) / 2.0,
                                self.view.bounds.size.height - size.height - 34.0,
                                size.width, size.height);
}

- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:^(__unused id<UIViewControllerTransitionCoordinatorContext> context) {
        [self dk_relayoutBar];
    } completion:nil];
}

#pragma mark - 交互

- (void)dk_materialChanged {
    self.bar.material = (self.materialControl.selectedSegmentIndex == 1)
        ? DKGlassMaterialClear : DKGlassMaterialRegular;
    [self dk_refreshStatus];
}

- (void)dk_polarityChanged {
    self.bar.polarity = (self.polarityControl.selectedSegmentIndex == 0)
        ? DKGlassPolarityDark : DKGlassPolarityLight;
    [self dk_refreshStatus];
}

- (void)dk_refreshStatus {
    self.statusLabel.text = [NSString stringWithFormat:@"%@\n%@",
                             [DKGlassSurface capabilitySummary],
                             DKGlassTuningSummary()];
}

#pragma mark - DKFloatingTabBarDelegate

- (void)floatingTabBar:(DKFloatingTabBar *)bar didSelectIndex:(NSInteger)index {
    NSLog(@"[DKLiquidGlassDemo] tab -> %ld", (long)index);
}

- (void)floatingTabBarDidTapPlusKey:(DKFloatingTabBar *)bar {
    NSLog(@"[DKLiquidGlassDemo] plus key");
}

@end

#pragma mark - 应用入口

@interface DKDemoAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation DKDemoAppDelegate

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary<UIApplicationLaunchOptionsKey, id> *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.backgroundColor = UIColor.blackColor;
    self.window.rootViewController = [[DKDemoViewController alloc] init];
    [self.window makeKeyAndVisible];

    NSLog(@"[DKLiquidGlassDemo] 启动 · %@", [DKGlassSurface capabilitySummary]);
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(DKDemoAppDelegate.class));
    }
}
