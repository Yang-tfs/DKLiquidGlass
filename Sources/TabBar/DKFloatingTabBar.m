//
//  DKFloatingTabBar.m
//

#import "DKFloatingTabBar.h"
#import "DKGlassTuning.h"

static const CGFloat kDKTabItemWidth   = 44.0;
static const CGFloat kDKTabCapsulePad  = 14.0;
static const CGFloat kDKTabIconSide    = 24.0;

@implementation DKFloatingTabItem

+ (instancetype)itemWithImage:(UIImage *)image
                selectedImage:(UIImage *)selectedImage
                        title:(NSString *)title {
    DKFloatingTabItem *item = [[self alloc] init];
    item.image = image;
    item.selectedImage = selectedImage;
    item.title = title;
    return item;
}

@end

@implementation DKFloatingTabBar {
    DKGlassSurface *_capsule;
    DKGlassSurface *_plusSurface;
    UIStackView *_stack;
    UIButton *_plusButton;
    NSMutableArray<UIButton *> *_buttons;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.backgroundColor = UIColor.clearColor;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;

    _selectedIndex = 0;
    _showsPlusKey = YES;
    _material = DKGlassMaterialRegular;
    _polarity = DKGlassPolarityDark;
    _buttons = [NSMutableArray array];

    _capsule = [[DKGlassSurface alloc] initWithMaterial:_material];
    _capsule.rimEnabled = YES;
    _capsule.pressFeedbackEnabled = YES;
    [self addSubview:_capsule];

    _stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    _stack.axis = UILayoutConstraintAxisHorizontal;
    _stack.alignment = UIStackViewAlignmentCenter;
    _stack.distribution = UIStackViewDistributionFillEqually;
    _stack.spacing = 0;
    [_capsule addSubview:_stack];

    _plusSurface = [[DKGlassSurface alloc] initWithMaterial:_material];
    _plusSurface.rimEnabled = YES;
    _plusSurface.pressFeedbackEnabled = YES;
    [self addSubview:_plusSurface];

    _plusButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _plusButton.tintColor = UIColor.whiteColor;
    UIImage *plus = [UIImage systemImageNamed:@"plus"];
    [_plusButton setImage:plus forState:UIControlStateNormal];
    _plusButton.preferredSymbolConfiguration =
        [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightMedium];
    [_plusButton addTarget:self action:@selector(dk_handlePlus) forControlEvents:UIControlEventTouchUpInside];
    [_plusSurface addSubview:_plusButton];

    return self;
}

#pragma mark - 属性

- (void)setItems:(NSArray<DKFloatingTabItem *> *)items {
    _items = [items copy];

    for (UIButton *button in _buttons) {
        [button removeFromSuperview];
    }
    [_buttons removeAllObjects];

    [items enumerateObjectsUsingBlock:^(DKFloatingTabItem *item, NSUInteger index, BOOL *stop) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = (NSInteger)index;
        UIImage *image = item.image ?: item.selectedImage;
        if (image) {
            [button setImage:[image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                    forState:UIControlStateNormal];
        }
        button.preferredSymbolConfiguration =
            [UIImageSymbolConfiguration configurationWithPointSize:19 weight:UIImageSymbolWeightRegular];
        if (item.title.length) {
            [button setTitle:item.title forState:UIControlStateNormal];
            button.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
            button.titleEdgeInsets = UIEdgeInsetsMake(kDKTabIconSide, -kDKTabIconSide, 0, 0);
            button.imageEdgeInsets = UIEdgeInsetsMake(-12, 0, 0, 0);
        }
        [button addTarget:self action:@selector(dk_handleTab:) forControlEvents:UIControlEventTouchUpInside];
        [self->_stack addArrangedSubview:button];
        [self->_buttons addObject:button];
    }];

    [self dk_applySelectionAnimated:NO];
    [self setNeedsLayout];
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    if (selectedIndex < 0 || selectedIndex >= (NSInteger)_items.count) return;
    if (_selectedIndex == selectedIndex) return;
    _selectedIndex = selectedIndex;
    [self dk_applySelectionAnimated:YES];
}

- (void)setShowsPlusKey:(BOOL)showsPlusKey {
    _showsPlusKey = showsPlusKey;
    _plusSurface.hidden = !showsPlusKey;
    [self setNeedsLayout];
}

- (void)setMaterial:(DKGlassMaterial)material {
    _material = material;
    [_capsule setMaterial:material animated:YES];
    [_plusSurface setMaterial:material animated:YES];
}

- (void)setPolarity:(DKGlassPolarity)polarity {
    _polarity = polarity;
    [self applyPolarity:polarity];
}

- (void)applyPolarity:(DKGlassPolarity)polarity {
    _polarity = polarity;
    [_capsule setPolarity:polarity animated:YES];
    [_plusSurface setPolarity:polarity animated:YES];
    [self dk_applySelectionAnimated:NO];
}

- (BOOL)usesNativeGlass {
    return _capsule.usesNativeGlass;
}

#pragma mark - 选中态

- (void)dk_applySelectionAnimated:(BOOL)animated {
    void (^apply)(void) = ^{
        [self->_buttons enumerateObjectsUsingBlock:^(UIButton *button, NSUInteger index, BOOL *stop) {
            BOOL selected = ((NSInteger)index == self->_selectedIndex);
            DKFloatingTabItem *item = index < self->_items.count ? self->_items[index] : nil;

            // 未选中用 62% 而不是 50%：50% 在 Clear 档上只有约 3.9:1 的对比度，不达 WCAG AA。
            UIColor *base = (self->_polarity == DKGlassPolarityDark)
                ? UIColor.whiteColor : UIColor.blackColor;
            button.tintColor = selected ? base : [base colorWithAlphaComponent:0.62];

            if (item.title.length) {
                [button setTitleColor:selected ? base : [base colorWithAlphaComponent:0.62]
                             forState:UIControlStateNormal];
                button.titleLabel.font = [UIFont systemFontOfSize:10
                                                         weight:selected ? UIFontWeightSemibold
                                                                         : UIFontWeightMedium];
            }

            UIImage *selectedImage = item.selectedImage;
            if (selectedImage && item.image) {
                UIImage *target = selected ? selectedImage : item.image;
                [button setImage:[target imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                        forState:UIControlStateNormal];
            }

            button.transform = selected ? CGAffineTransformMakeTranslation(0, -1)
                                        : CGAffineTransformIdentity;
        }];

        UIColor *plusColor = (self->_polarity == DKGlassPolarityDark) ? UIColor.whiteColor : UIColor.blackColor;
        self->_plusButton.tintColor = plusColor;
    };

    if (!animated || UIAccessibilityIsReduceMotionEnabled()) {
        [UIView performWithoutAnimation:apply];
        return;
    }
    [UIView animateWithDuration:0.2
                          delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:apply
                     completion:nil];
}

#pragma mark - 事件

- (void)dk_handleTab:(UIButton *)sender {
    NSInteger index = sender.tag;
    if (index < 0 || index >= (NSInteger)_items.count) return;
    if (index == _selectedIndex) {
        [self.delegate floatingTabBar:self didSelectIndex:index];
        return;
    }
    _selectedIndex = index;
    [self dk_applySelectionAnimated:YES];
    [self.delegate floatingTabBar:self didSelectIndex:index];
}

- (void)dk_handlePlus {
    if ([self.delegate respondsToSelector:@selector(floatingTabBarDidTapPlusKey:)]) {
        [self.delegate floatingTabBarDidTapPlusKey:self];
    }
}

#pragma mark - 布局

- (CGSize)preferredSizeForWidth:(CGFloat)availableWidth {
    CGFloat usable = MAX(0, availableWidth - DKGlassBarInset * 2);
    CGFloat capsule = [self dk_capsuleWidthForUsable:usable];
    CGFloat height = DKGlassBarHeight;
    CGFloat total = capsule;
    if (_showsPlusKey) total += DKGlassPlusGap + height;
    return CGSizeMake(MIN(total, usable), height);
}

- (CGFloat)dk_capsuleWidthForUsable:(CGFloat)usable {
    if (_items.count == 0) return 0;

    CGFloat natural = _items.count * kDKTabItemWidth + kDKTabCapsulePad * 2;
    CGFloat reserved = _showsPlusKey ? (DKGlassBarHeight + DKGlassPlusGap) : 0;
    CGFloat ceiling = MAX(0, usable - reserved);
    return MIN(natural, ceiling);
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat available = CGRectGetWidth(self.bounds);
    if (available <= 0) return;

    CGFloat height = DKGlassBarHeight;
    if (fabs(CGRectGetHeight(self.bounds) - height) > 0.5) {
        CGRect frame = self.frame;
        frame.size.height = height;
        self.frame = frame;
    }

    CGFloat capsuleWidth = [self dk_capsuleWidthForUsable:available];
    CGFloat total = capsuleWidth + (_showsPlusKey ? DKGlassPlusGap + height : 0);
    CGFloat originX = (available - total) / 2.0;
    if (originX < DKGlassBarInset) originX = DKGlassBarInset;

    CGRect capsuleRect = CGRectMake(originX, 0, capsuleWidth, height);
    if (!CGRectEqualToRect(_capsule.frame, capsuleRect)) {
        _capsule.frame = capsuleRect;
    }
    _capsule.cornerRadius = DKGlassCapsuleRadius(height);

    // 胶囊内边距：图标区不贴到圆弧上
    CGFloat stackInset = kDKTabCapsulePad;
    CGRect stackRect = CGRectInset(capsuleRect, stackInset, 0);
    stackRect.origin = CGPointMake(stackInset, 0);
    if (!CGRectEqualToRect(_stack.frame, stackRect)) {
        _stack.frame = stackRect;
    }

    if (_showsPlusKey) {
        CGRect plusRect = CGRectMake(CGRectGetMaxX(capsuleRect) + DKGlassPlusGap, 0, height, height);
        if (!CGRectEqualToRect(_plusSurface.frame, plusRect)) {
            _plusSurface.frame = plusRect;
        }
        _plusSurface.cornerRadius = height / 2.0;

        CGRect buttonRect = CGRectInset(_plusSurface.bounds, 6, 6);
        if (!CGRectEqualToRect(_plusButton.frame, buttonRect)) {
            _plusButton.frame = buttonRect;
        }
    }

}

- (CGSize)intrinsicContentSize {
    return [self preferredSizeForWidth:DKGlassBarInset * 2 + _items.count * kDKTabItemWidth
                                      + kDKTabCapsulePad * 2
                                      + (_showsPlusKey ? DKGlassPlusGap + DKGlassBarHeight : 0)];
}

@end
