/// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
/// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSUserDefaults (FCSignInData)

@property (nonatomic, strong) NSString* url;
@property (nonatomic, strong) NSString* tenant;
@property (nonatomic, strong) NSString* username;
@property (nonatomic, strong) NSString* authTicket;

@end

NS_ASSUME_NONNULL_END
