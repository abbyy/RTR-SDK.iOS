// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

#import "RecognizerEngine.h"

@interface RecognizerEngine()

@property (nonatomic, strong) NSString* path;
@property (nonatomic, strong) RTREngine* rtrEngine;

@end

@implementation RecognizerEngine

+ (void)setLicensePath:(NSString*)path
{
	// Save license path
	[[self shared] setPath:path];
}

+ (RTREngine*)rtrEngine
{
	return [[self shared] rtrEngine];
}

+ (NSString*)version
{
	NSDictionary* info = [[NSBundle bundleForClass:[RTREngine class]] infoDictionary];
	return info[@"CFBundleVersion"];
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

- (RTREngine*)rtrEngine
{
	NSAssert(self.path.length > 0, @"Please specify license path");
	if(_rtrEngine == nil) {
		NSError* error = nil;
		NSData* data = [[NSData alloc] initWithContentsOfFile:self.path options:0 error:&error];
		_rtrEngine = [RTREngine sharedEngineWithLicenseData:data];
	}
	return _rtrEngine;
}

- (void)setPath:(NSString*)path
{
	NSAssert(self.path.length == 0, @"License is already specified");
	_path = path;
}

@end
