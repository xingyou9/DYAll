// DYYDDesign.h — DYAll 5.0 Design System 统一令牌
// Typography / Color / Spacing / CornerRadius 全局唯一来源，禁止各页面自写一套。
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark Typography

static inline UIFont *DYYDFontLargeTitle(void) { return [UIFont systemFontOfSize:24 weight:UIFontWeightBold]; }
static inline UIFont *DYYDFontTitle(void)      { return [UIFont systemFontOfSize:19 weight:UIFontWeightSemibold]; }
static inline UIFont *DYYDFontHeadline(void)   { return [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold]; }
static inline UIFont *DYYDFontBody(void)       { return [UIFont systemFontOfSize:14.5 weight:UIFontWeightRegular]; }
static inline UIFont *DYYDFontCaption(void)    { return [UIFont systemFontOfSize:12.5 weight:UIFontWeightRegular]; }
static inline UIFont *DYYDFontMetric(void)     { return [UIFont monospacedDigitSystemFontOfSize:14.5 weight:UIFontWeightMedium]; }

#pragma mark Color（动态色，自动深浅色）

static inline UIColor *DYYDColorPrimary(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.42 green:0.72 blue:1.0 alpha:1]
            : [UIColor colorWithRed:0.05 green:0.45 blue:0.95 alpha:1];
    }];
}
static inline UIColor *DYYDColorSuccess(void) {
    return [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1];
}
static inline UIColor *DYYDColorWarning(void) {
    return [UIColor colorWithRed:1.0 green:0.72 blue:0.20 alpha:1];
}
static inline UIColor *DYYDColorError(void) {
    return [UIColor colorWithRed:1.0 green:0.32 blue:0.28 alpha:1];
}
static inline UIColor *DYYDColorLabel(void) { return UIColor.labelColor; }
static inline UIColor *DYYDColorSecondaryLabel(void) { return UIColor.secondaryLabelColor; }
static inline UIColor *DYYDColorSeparator(void) { return UIColor.separatorColor; }
static inline UIColor *DYYDColorCardBackground(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1.0 alpha:0.08]
            : [UIColor colorWithWhite:0.0 alpha:0.05];
    }];
}

#pragma mark Spacing（唯一允许的间距档位）

static const CGFloat DYYDSpaceXS = 4;
static const CGFloat DYYDSpaceS  = 8;
static const CGFloat DYYDSpaceM  = 12;
static const CGFloat DYYDSpaceL  = 16;
static const CGFloat DYYDSpaceXL = 20;
static const CGFloat DYYDSpace2XL = 24;
static const CGFloat DYYDSpace3XL = 32;

#pragma mark Corner Radius（唯一允许的圆角档位）

static inline CGFloat DYYDRadiusSmall(void)  { return 8; }
static inline CGFloat DYYDRadiusMedium(void) { return 12; }
static inline CGFloat DYYDRadiusLarge(void)  { return 16; }
static inline CGFloat DYYDRadiusCard(void)   { return 20; }
static inline CGFloat DYYDRadiusHero(void)   { return 24; }

#pragma mark Motion

static inline BOOL DYYDMotionAllowed(void) {
    return !UIAccessibilityIsReduceMotionEnabled();
}
static inline void DYYDAnimate(UIViewAnimationOptions options, void (^animations)(void)) {
    NSTimeInterval duration = DYYDMotionAllowed() ? 0.28 : 0.0;
    [UIView animateWithDuration:duration delay:0 options:options animations:animations completion:nil];
}

NS_ASSUME_NONNULL_END
