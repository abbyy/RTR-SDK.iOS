// ABBYY® Real-Time Recognition SDK 1 © 2016 ABBYY Production LLC.
// ABBYY is either a registered trademark or a trademark of ABBYY Software Ltd.

#import <UIKit/UIKit.h>

/// View for progress indication.
IB_DESIGNABLE
@interface RTRProgressView : UIView

/// Update progress.
- (void)setProgress:(NSInteger)progress color:(UIColor*)color;

@end
