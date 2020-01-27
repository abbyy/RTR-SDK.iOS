/// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
/// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

#import <Foundation/Foundation.h>
#import <AbbyyRtrSDK/AbbyyRtrSDK.h>

NS_ASSUME_NONNULL_BEGIN

/// Wrapper class to get access to RTR SDK API
@interface RecognizerEngine : NSObject

/// Returns RTR Engine
+ (RTREngine*)rtrEngineWithError:(NSError**)error;;
/// Returns RTR CoreAPI
+ (id<RTRCoreAPI>)coreAPIWithError:(NSError**)error;;

@end

NS_ASSUME_NONNULL_END
