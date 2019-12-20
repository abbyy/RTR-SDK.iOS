// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

#import <Foundation/Foundation.h>
#import <AbbyyRtrSDK/AbbyyRtrSDK.h>

NS_ASSUME_NONNULL_BEGIN

/// Wrapper class to get access to RTR SDK API
@interface RecognizerEngine : NSObject

/// Provide path to ABBYY license file to initialize RTR engine
+ (void)setLicensePath:(NSString*)path;
/// Returns RTR Engine
+ (RTREngine*)rtrEngine;
/// SDK Version
+ (NSString*)version;

@end

NS_ASSUME_NONNULL_END
