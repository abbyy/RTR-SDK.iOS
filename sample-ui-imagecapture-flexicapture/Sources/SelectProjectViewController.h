/// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
/// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SelectProjectViewControllerDelegate <NSObject>

- (void)selectedProject:(NSString*)projectName;

@end

@interface SelectProjectViewController : UIViewController

@property (nonatomic, weak, nullable) id<SelectProjectViewControllerDelegate> delegate;

@property (nonatomic, copy) NSArray<NSString*>* projectsNames;
@property (nonatomic, strong) NSString* selectedProjectName;

@end

NS_ASSUME_NONNULL_END
