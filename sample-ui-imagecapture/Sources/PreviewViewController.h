// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class PreviewViewController;

@protocol PreviewViewControllerDelegate <NSObject>

/// Called when user completes documents capture
- (void)previewController:(PreviewViewController*)viewController didCompleteWithImage:(UIImage*)image;
/// Called when user cancels documents capture
- (void)previewControllerDidCancel:(PreviewViewController*)viewController;

@end

/// Captured document preview controller
@interface PreviewViewController : UIViewController

/// Captured document
@property (nonatomic, strong) UIImage* image;
@property (nonatomic, weak) id<PreviewViewControllerDelegate> delegate;

@end

NS_ASSUME_NONNULL_END
