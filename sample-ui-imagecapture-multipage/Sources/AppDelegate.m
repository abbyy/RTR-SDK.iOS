/// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
/// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

#import "AppDelegate.h"
#import "RecognizerEngine.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
	// Initialize ABBYY Engine one time at app launch with available license file
	NSString* licensePath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"license"];
	[RecognizerEngine setLicensePath:licensePath];
	return YES;
}

@end
