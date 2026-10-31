//
//  DKGlassSurface.m
//

#import "DKGlassSurface.h"

#import <math.h>
#import "DKGlassTuning.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
#define DK_HAS_GLASS_SDK 1
#else
#define DK_HAS_GLASS_SDK 0
#endif

#pragma mark - 系统原生玻璃（iOS 26+）

static BOOL DKGlassNativeAvailable(void) {
    static BOOL available;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = NSClassFromString(@"UIGlassEffect");
        available = cls && [cls respondsToSelector:NSSelectorFromString(@"effectWithStyle:")];
    });
    return available;
}

/// 建原生玻璃 effect。失败返回 nil，调用方自动走降级。
static UIVisualEffect *DKMakeNativeGlass(DKGlassMaterial material, UIColor *_Nullable tint, BOOL interactive) {
    if (!DKGlassNativeAvailable()) return nil;

#if DK_HAS_GLASS_SDK
    // 有 iOS 26 SDK 时优先走强类型 API。@available 守卫是必需的：
    // 光靠 #if 只解决"能不能编译"，不满足可用性检查。
    if (@available(iOS 26.0, *)) {
        UIGlassEffectStyle style = (material == DKGlassMaterialClear)
            ? UIGlassEffectStyleClear : UIGlassEffectStyleRegular;
        UIGlassEffect *effect = [UIGlassEffect effectWithStyle:style];
        if (!effect) return nil;
        effect.interactive = interactive;
        effect.tintColor = tint;
        return effect;
    }
#endif

    // 没有 26 SDK、或运行时低于 26：反射调用。
    // UIGlassEffectStyleRegular 与 Clear 的取值若在某些版本上对调，改这两个常量即可。
    static const NSInteger kStyleRegular = 0;
    static const NSInteger kStyleClear   = 1;
    NSInteger style = (material == DKGlassMaterialClear) ? kStyleClear : kStyleRegular;

    Class cls = NSClassFromString(@"UIGlassEffect");
    id effect = ((id (*)(id, SEL, NSInteger))objc_msgSend)(cls, NSSelectorFromString(@"effectWithStyle:"), style);
    if (!effect) return nil;

    @try { [effect setValue:@(interactive) forKey:@"interactive"]; } @catch (__unused NSException *e) {}
    if (tint) { @try { [effect setValue:tint forKey:@"tintColor"]; } @catch (__unused NSException *e) {} }
    return (UIVisualEffect *)effect;
}

#pragma mark - 降级路径的私有滤镜（可选，默认关闭）

// 背景模糊由 WindowServer 在合成阶段完成，视图里没有背景像素可读，
// 因此这里只能改系统材质自带的 filter 链，做不了位移采样（折射）。
// 私有 API 在新系统上可能整条不存在，探测失败就静默跳过——观感退半步，功能不受影响。

static CALayer *_Nullable DKFindBackdropLayer(UIView *view, NSUInteger depth) {
    if (depth > 6) return nil;
    for (CALayer *layer in view.layer.sublayers) {
        if ([NSStringFromClass(layer.class) containsString:@"Backdrop"]) return layer;
    }
    for (CALayer *layer in view.layer.sublayers) {
        id delegate = layer.delegate;
        if ([delegate isKindOfClass:UIView.class]) {
            CALayer *found = DKFindBackdropLayer((UIView *)delegate, depth + 1);
            if (found) return found;
        }
    }
    return nil;
}

static id _Nullable DKMakeFilter(NSString *name, NSDictionary<NSString *, id> *params) {
    Class filterClass = NSClassFromString(@"CAFilter");
    if (!filterClass) return nil;
    SEL sel = NSSelectorFromString(@"filterWithName:");
    if (![filterClass respondsToSelector:sel]) return nil;

    id filter = ((id (*)(id, SEL, id))objc_msgSend)(filterClass, sel, name);
    if (!filter) return nil;
    for (NSString *key in params) {
        @try { [filter setValue:params[key] forKey:key]; } @catch (__unused NSException *e) {}
    }
    return filter;
}

static void DKInjectBackdropFilters(UIView *view) {
    if (!DKGlassInjectFilters) return;

    CALayer *backdrop = DKFindBackdropLayer(view, 0);
    if (!backdrop) return;

    NSMutableArray *filters = [NSMutableArray array];
    @try {
        id existing = [backdrop valueForKey:@"filters"];
        if ([existing isKindOfClass:NSArray.class]) [filters addObjectsFromArray:existing];
    } @catch (__unused NSException *e) {}

    id blur = DKMakeFilter(@"gaussianBlur", @{ @"inputRadius": @(DKGlassExtraBlurRadius) });
    id saturate = DKMakeFilter(@"colorSaturate", @{ @"inputAmount": @(DKGlassSaturationBoost) });
    id bright = DKMakeFilter(@"colorBrightness", @{ @"inputAmount": @(DKGlassBrightnessLift) });

    for (id filter in @[blur ?: NSNull.null, saturate ?: NSNull.null, bright ?: NSNull.null]) {
        if (filter != NSNull.null) [filters addObject:filter];
    }

    @try { [backdrop setValue:filters forKey:@"filters"]; } @catch (__unused NSException *e) {}
}

#pragma mark - 边缘装饰层

/// 顶边高光 + 内壁暗环 + 细描边。全部用公开 API 绘制。
@interface DKGlassRimView : UIView
@property (nonatomic, assign) CGFloat rimRadius;
@property (nonatomic, assign) BOOL rimEnabled;
@end

@implementation DKGlassRimView {
    CAGradientLayer *_topRim;
    CAShapeLayer *_topRimMask;
    CAGradientLayer *_innerShade;
    CAShapeLayer *_innerShadeMask;
    CAShapeLayer *_hairline;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.userInteractionEnabled = NO;
    self.backgroundColor = UIColor.clearColor;
    [self dk_buildLayers];
    return self;
}

- (void)dk_buildLayers {
    _topRim = [CAGradientLayer layer];
    _topRim.colors = @[(id)[UIColor colorWithWhite:1.0 alpha:DKGlassRimTopAlpha].CGColor,
                       (id)[UIColor colorWithWhite:1.0 alpha:DKGlassRimBottomAlpha].CGColor];
    _topRim.startPoint = CGPointMake(0.5, 0.0);
    _topRim.endPoint = CGPointMake(0.5, 1.0);
    _topRimMask = [CAShapeLayer layer];
    _topRimMask.fillColor = UIColor.clearColor.CGColor;
    _topRimMask.strokeColor = UIColor.whiteColor.CGColor;   // 只借 stroke 做遮罩，颜色不参与显示
    _topRimMask.lineWidth = DKGlassRimLineWidth;
    _topRim.mask = _topRimMask;
    [self.layer addSublayer:_topRim];

    _innerShade = [CAGradientLayer layer];
    _innerShade.colors = @[(id)[UIColor colorWithWhite:0.0 alpha:0.0].CGColor,
                           (id)[UIColor colorWithWhite:0.0 alpha:DKGlassInnerShadowAlpha].CGColor];
    _innerShade.startPoint = CGPointMake(0.5, 0.0);
    _innerShade.endPoint = CGPointMake(0.5, 1.0);
    _innerShadeMask = [CAShapeLayer layer];
    _innerShadeMask.fillColor = UIColor.clearColor.CGColor;
    _innerShadeMask.strokeColor = UIColor.whiteColor.CGColor;
    _innerShadeMask.lineWidth = DKGlassInnerShadowWidth;
    _innerShade.mask = _innerShadeMask;
    [self.layer addSublayer:_innerShade];

    _hairline = [CAShapeLayer layer];
    _hairline.fillColor = UIColor.clearColor.CGColor;
    _hairline.strokeColor = [UIColor colorWithWhite:1.0 alpha:DKGlassHairlineAlpha].CGColor;
    _hairline.lineWidth = DKGlassHairlineWidth;
    [self.layer addSublayer:_hairline];
}

- (void)setRimRadius:(CGFloat)rimRadius {
    _rimRadius = rimRadius;
    [self setNeedsLayout];
}

- (void)setRimEnabled:(BOOL)rimEnabled {
    _rimEnabled = rimEnabled;
    _topRim.hidden = !rimEnabled;
    _innerShade.hidden = !rimEnabled;
    _hairline.hidden = !rimEnabled;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGRect bounds = self.bounds;
    if (CGRectIsEmpty(bounds)) return;

    // 描边要落在 0.5pt 上才不糊：内缩半个线宽。
    CGFloat inset = DKGlassHairlineWidth / 2.0;
    CGRect strokeRect = CGRectInset(bounds, inset, inset);
    CGPathRef path = [UIBezierPath bezierPathWithRoundedRect:strokeRect
                                                cornerRadius:MAX(0.0, _rimRadius - inset)].CGPath;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    _topRim.frame = bounds;
    _topRimMask.frame = bounds;
    _topRimMask.path = path;

    _innerShade.frame = bounds;
    _innerShadeMask.frame = bounds;
    _innerShadeMask.path = path;

    _hairline.frame = bounds;
    _hairline.path = path;

    [CATransaction commit];
}

@end

#pragma mark - 触摸柔光斑

@interface DKGlassSpecularView : UIView
- (void)showAtPoint:(CGPoint)point;
- (void)hide;
@end

@implementation DKGlassSpecularView {
    CAGradientLayer *_glow;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.userInteractionEnabled = NO;
    self.alpha = 0.0;
    self.backgroundColor = UIColor.clearColor;

    _glow = [CAGradientLayer layer];
    _glow.type = kCAGradientLayerRadial;
    _glow.colors = @[(id)[UIColor colorWithWhite:1.0 alpha:DKGlassSpecularAlpha].CGColor,
                     (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor];
    _glow.startPoint = CGPointMake(0.5, 0.5);
    _glow.endPoint = CGPointMake(1.0, 1.0);
    _glow.frame = CGRectMake(0, 0, DKGlassSpecularDiameter, DKGlassSpecularDiameter);
    _glow.position = CGPointMake(DKGlassSpecularDiameter / 2.0, DKGlassSpecularDiameter / 2.0);
    [self.layer addSublayer:_glow];
    return self;
}

- (void)showAtPoint:(CGPoint)point {
    CGPoint center = point;
    CGSize size = self.bounds.size;
    // 柔光斑边缘不能出界，否则会被圆角裁成硬边。
    CGFloat radius = DKGlassSpecularDiameter / 2.0;
    center.x = MIN(MAX(center.x, radius * 0.4), size.width - radius * 0.4);
    center.y = MIN(MAX(center.y, radius * 0.4), size.height - radius * 0.4);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _glow.position = center;
    [CATransaction commit];

    [UIView animateWithDuration:0.18 animations:^{ self.alpha = 1.0; }];
}

- (void)hide {
    [UIView animateWithDuration:0.22 animations:^{ self.alpha = 0.0; }];
}

@end

#pragma mark - 玻璃本体

@implementation DKGlassSurface {
    UIView *_tintOverlay;
    DKGlassRimView *_rim;
    DKGlassSpecularView *_specular;
    UILongPressGestureRecognizer *_press;
    CGFloat _explicitCornerRadius;
    BOOL _usesNativeGlass;
    BOOL _materialReady;
    // rimEnabled 的 getter 与 setter 都手写了，编译器不会再合成实例变量，必须显式声明。
    BOOL _rimEnabled;
}

@synthesize material = _material;
@synthesize polarity = _polarity;

- (instancetype)initWithMaterial:(DKGlassMaterial)material {
    self = [super initWithEffect:nil];
    if (!self) return nil;

    _material = material;
    _polarity = DKGlassPolarityDark;
    _explicitCornerRadius = 0.0;
    _rimEnabled = YES;
    _pressFeedbackEnabled = YES;

    self.backgroundColor = UIColor.clearColor;
    self.userInteractionEnabled = YES;
    self.layer.masksToBounds = YES;
    self.layer.cornerCurve = DKGlassContinuousCorner ? kCACornerCurveContinuous : kCACornerCurveCircular;

    // 染色层必须独立成视图：UIVisualEffectView 自己的 backgroundColor 画在 effect 之下，
    // 直接改它会被模糊层吃掉，看不见任何效果。
    _tintOverlay = [[UIView alloc] initWithFrame:CGRectZero];
    _tintOverlay.userInteractionEnabled = NO;
    _tintOverlay.backgroundColor = UIColor.clearColor;
    [self addSubview:_tintOverlay];

    _rim = [[DKGlassRimView alloc] initWithFrame:CGRectZero];
    _rim.rimEnabled = _rimEnabled;
    [self addSubview:_rim];

    _specular = [[DKGlassSpecularView alloc] initWithFrame:CGRectZero];
    [self addSubview:_specular];

    _press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(dk_handlePress:)];
    _press.minimumPressDuration = 0.0;
    _press.allowableMovement = CGFLOAT_MAX;
    _press.cancelsTouchesInView = NO;
    [self addGestureRecognizer:_press];

    [self dk_rebuildMaterialAnimated:NO];
    return self;
}

- (void)dealloc {
    [self removeGestureRecognizer:_press];
}

+ (BOOL)nativeGlassAvailable {
    return DKGlassNativeAvailable();
}

+ (NSString *)capabilitySummary {
    BOOL native = DKGlassNativeAvailable();
    NSMutableString *text = [NSMutableString string];
    [text appendFormat:@"glass=%@", native ? @"native(iOS26)" : @"fallback"];
    [text appendFormat:@" · rim=%.2f/%.2f hairline=%.2f shadow=%.2f",
        DKGlassRimTopAlpha, DKGlassRimBottomAlpha, DKGlassHairlineAlpha, DKGlassInnerShadowAlpha];
    [text appendFormat:@" · filters=%@", DKGlassInjectFilters ? @"on" : @"off"];
    if (!native) {
        [text appendFormat:@" · blur=+%.0f sat=%.2f lift=%+.2f",
            DKGlassExtraBlurRadius, DKGlassSaturationBoost, DKGlassBrightnessLift];
    }
    return text;
}

#pragma mark - 材质构建

- (void)dk_rebuildMaterialAnimated:(BOOL)animated {
    UIColor *tint = (_material == DKGlassMaterialClear) ? DKGlassClearTint(_polarity) : nil;

    UIVisualEffect *effect = DKMakeNativeGlass(_material, tint, _pressFeedbackEnabled);
    BOOL usedNative = effect != nil;

    if (!usedNative) {
        // 降级：系统模糊底盘。亮度与染色靠叠加层，不依赖私有滤镜。
        effect = [UIBlurEffect effectWithStyle:
                  (_material == DKGlassMaterialClear)
                      ? UIBlurEffectStyleSystemUltraThinMaterialDark
                      : UIBlurEffectStyleSystemChromeMaterialDark];
    }

    void (^apply)(void) = ^{
        self.effect = effect;
        self->_usesNativeGlass = usedNative;
        // 原生路径由 UIGlassEffect 自己处理亮度与染色，不再叠一层，否则会压暗两次。
        self->_tintOverlay.backgroundColor = usedNative ? UIColor.clearColor
                                                       : [self dk_fallbackOverlayColor];
        self->_specular.hidden = usedNative;   // 原生路径自带 flex，不再叠假柔光
        [self setNeedsLayout];
    };

    if (!animated || UIAccessibilityIsReduceMotionEnabled()) {
        [UIView performWithoutAnimation:apply];
    } else {
        [UIView transitionWithView:self
                          duration:0.22
                           options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                        animations:apply
                        completion:nil];
    }

    // 降级路径的私有滤镜增强（默认关闭，探测失败即跳过）
    if (!usedNative) {
        dispatch_async(dispatch_get_main_queue(), ^{
            DKInjectBackdropFilters(self);
        });
    }

    _materialReady = YES;
}

/// 降级路径的叠加层：用一层极淡的白/黑做亮度与染色，公开 API，零风险。
- (UIColor *)dk_fallbackOverlayColor {
    switch (_material) {
        case DKGlassMaterialClear:
            return DKGlassClearTint(_polarity);
        case DKGlassMaterialRegular:
        default:
            return (_polarity == DKGlassPolarityDark)
                ? [UIColor colorWithWhite:1.0 alpha:DKGlassBrightnessLift]
                : [UIColor colorWithWhite:0.0 alpha:DKGlassBrightnessLift * 0.4];
    }
}

#pragma mark - 属性

- (BOOL)usesNativeGlass {
    return _usesNativeGlass;
}

- (void)setMaterial:(DKGlassMaterial)material animated:(BOOL)animated {
    if (_materialReady && _material == material) return;
    _material = material;
    [self dk_rebuildMaterialAnimated:animated];
}

- (void)setPolarity:(DKGlassPolarity)polarity animated:(BOOL)animated {
    if (_materialReady && _polarity == polarity) return;
    _polarity = polarity;

    // 原生 Regular 档：外观只走 overrideUserInterfaceStyle，不重建材质。
    // 重建会把活着的材质换掉，没有收益。
    if (_usesNativeGlass && _material == DKGlassMaterialRegular) {
        self.overrideUserInterfaceStyle = (polarity == DKGlassPolarityDark)
            ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
        return;
    }
    [self dk_rebuildMaterialAnimated:animated];
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _explicitCornerRadius = cornerRadius;
    [self setNeedsLayout];
}

- (CGFloat)cornerRadius {
    return _explicitCornerRadius;
}

- (void)setRimEnabled:(BOOL)rimEnabled {
    _rimEnabled = rimEnabled;
    _rim.rimEnabled = rimEnabled;
}

- (BOOL)rimEnabled {
    return _rimEnabled;
}

- (void)setPressFeedbackEnabled:(BOOL)pressFeedbackEnabled {
    if (_pressFeedbackEnabled == pressFeedbackEnabled) return;
    _pressFeedbackEnabled = pressFeedbackEnabled;
    _press.enabled = pressFeedbackEnabled;
    if (!pressFeedbackEnabled) {
        self.transform = CGAffineTransformIdentity;
        [_specular hide];
    }
    // 原生路径的 interactive 是材质属性，改它要重建
    if (_usesNativeGlass) [self dk_rebuildMaterialAnimated:NO];
}

#pragma mark - 布局

- (void)layoutSubviews {
    [super layoutSubviews];

    CGRect bounds = self.bounds;
    if (CGRectIsEmpty(bounds)) return;

    CGFloat radius = (_explicitCornerRadius > 0.0)
        ? MIN(_explicitCornerRadius, MIN(bounds.size.width, bounds.size.height) / 2.0)
        : DKGlassCapsuleRadius(bounds.size.height);

    if (fabs(self.layer.cornerRadius - radius) > 0.01) {
        // 先比较再写：逐帧路径上无谓赋值会让 CoreAnimation 反复提交事务。
        self.layer.cornerRadius = radius;
    }

    if (!CGRectEqualToRect(_rim.frame, bounds)) {
        _rim.frame = bounds;
        _rim.rimRadius = radius;
    } else {
        _rim.rimRadius = radius;
    }

    if (!CGRectEqualToRect(_tintOverlay.frame, bounds)) {
        _tintOverlay.frame = bounds;
        // 叠加层本身也要跟随圆角，否则四角会露出一小片方角底色。
        _tintOverlay.layer.cornerRadius = radius;
        _tintOverlay.layer.cornerCurve = self.layer.cornerCurve;
        _tintOverlay.layer.masksToBounds = YES;
    }

    if (!CGRectEqualToRect(_specular.frame, bounds)) {
        _specular.frame = bounds;
    }
}

#pragma mark - 触摸反馈

- (void)dk_handlePress:(UILongPressGestureRecognizer *)gesture {
    if (!_pressFeedbackEnabled) return;

    switch (gesture.state) {
        case UIGestureRecognizerStateBegan: {
            CGPoint point = [gesture locationInView:self];
            [UIView animateWithDuration:DKGlassPressDuration
                                  delay:0
                                options:UIViewAnimationOptionBeginFromCurrentState
                                        | UIViewAnimationOptionAllowUserInteraction
                                        | UIViewAnimationOptionCurveEaseOut
                             animations:^{
                self.transform = CGAffineTransformMakeScale(DKGlassPressScale, DKGlassPressScale);
            } completion:nil];
            if (!_usesNativeGlass) [_specular showAtPoint:point];
            break;
        }
        case UIGestureRecognizerStateChanged: {
            if (_usesNativeGlass || _specular.alpha < 0.5) break;
            [_specular showAtPoint:[gesture locationInView:self]];
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed: {
            [UIView animateWithDuration:DKGlassPressDuration
                                  delay:0
                                options:UIViewAnimationOptionBeginFromCurrentState
                                        | UIViewAnimationOptionAllowUserInteraction
                                        | UIViewAnimationOptionCurveEaseOut
                             animations:^{ self.transform = CGAffineTransformIdentity; }
                             completion:nil];
            [_specular hide];
            break;
        }
        default:
            break;
    }
}

#pragma mark - 外观变化

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (!previous) return;
    if (previous.userInterfaceStyle == self.traitCollection.userInterfaceStyle) return;
    // 降级路径靠叠加层染色，外观变了要重算底色。
    if (!_usesNativeGlass) {
        _tintOverlay.backgroundColor = [self dk_fallbackOverlayColor];
    }
}

@end
