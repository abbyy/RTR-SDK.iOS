/// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
/// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

#import "RecognizerEngine.h"

@interface RecognizerEngine ()

@property (nonatomic, strong) RTREngine* rtrEngine;

@end

@implementation RecognizerEngine

+ (RTREngine*)rtrEngine
{
	return [[self shared] rtrEngine];
}

+ (RecognizerEngine*)shared
{
	static RecognizerEngine* shared = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		shared = [self new];
	});
	return shared;
}

+ (RTREngine*)rtrEngineWithError:(NSError* __autoreleasing _Nullable*)error
{
	if([self shared].rtrEngine == nil) {
		// Initialize ABBYY Engine one time at app launch with available license file
		NSString* licensePath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"license"];

		NSData* data = [[NSData alloc] initWithContentsOfFile:licensePath options:0 error:error];
		[self shared].rtrEngine = [RTREngine sharedEngineWithLicenseData:data];
	}

	return [self shared].rtrEngine;
}

+ (id<RTRCoreAPI>)coreAPIWithError:(NSError* __autoreleasing _Nullable*)error
{
	return [[self rtrEngineWithError:error] createCoreAPI];
}

@end
