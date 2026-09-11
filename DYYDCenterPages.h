// DYYDCenterPages.h — DYAll 5.0.2 中心页：模式 / 性能 / 缓存 / 隐私
//
// 5.0.2 重大修正：不再用裸 UITableViewController。
// 抖音的自定义导航容器对裸 VC 的 push 处理不好（转场冻结、前一页透出、页面只占部分宽度），
// 老页面（系统与性能等）全部走 AWESettingBaseViewController 容器，
// 所以这四个中心页也统一改走 DYYYSettingsHelper createSubSettingsViewController，
// 与老界面 100% 同规格，根治「透明框」bug。
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DYYDCenterPages : NSObject
+ (UIViewController *)modeCenterPage;
+ (UIViewController *)perfCenterPage;
+ (UIViewController *)cacheCenterPage;
+ (UIViewController *)privacyCenterPage;
@end

NS_ASSUME_NONNULL_END
