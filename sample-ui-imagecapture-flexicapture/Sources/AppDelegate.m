/// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
/// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

#import "AppDelegate.h"

#import "FlexiCaptureClient.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
	return YES;
}

- (void)applicationDidEnterBackground:(UIApplication*)application
{
	[FlexiCaptureClient cancelAllRequests];
}

@end
