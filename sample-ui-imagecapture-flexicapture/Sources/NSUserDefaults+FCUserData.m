/// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
/// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

#import "NSUserDefaults+FCUserData.h"

#import "NSUserDefaults+FCSignInData.h"

static NSString* ProjectNameKey = @"ProjectNameKey";
static NSString* CurrentDocumensAreSuccessfullyExportedKey = @"CurrentDocumensAreSuccessfullyExportedKey";


@implementation NSUserDefaults (FCUserData)

- (NSString*)projectName
{
	return [self stringForKey:ProjectNameKey];
}

- (void)setProjectName:(NSString*)projectName
{
	[self setObject:projectName forKey:ProjectNameKey];
}

- (BOOL)currentDocumensAreSuccessfullyExported
{
	return [self boolForKey:CurrentDocumensAreSuccessfullyExportedKey];
}

- (void)setCurrentDocumensAreSuccessfullyExported:(BOOL)currentDocumensAreSuccessfullyExported
{
	[self setBool:currentDocumensAreSuccessfullyExported forKey:CurrentDocumensAreSuccessfullyExportedKey];
}

- (BOOL)authorized
{
	return self.projectName.length > 0 && self.authTicket.length > 0;
}

@end
