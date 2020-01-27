/// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
/// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSUserDefaults (FCUserData)

@property (nonatomic, strong) NSString* projectName;
@property (nonatomic, assign) BOOL currentDocumensAreSuccessfullyExported;

@property (nonatomic, assign, readonly) BOOL authorized;

@end

NS_ASSUME_NONNULL_END
