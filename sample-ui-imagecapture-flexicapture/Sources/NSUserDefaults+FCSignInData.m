/// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
/// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

#import "NSUserDefaults+FCSignInData.h"

static NSString* URLKey = @"URLKey";
static NSString* TenantKey = @"TenantKey";
static NSString* UsernameKey = @"UsernameKey";
static NSString* AuthTicketKey = @"AuthTicketKey";

@implementation NSUserDefaults (FCSignInData)

- (NSString*)url
{
	return [self stringForKey:URLKey];
}

- (void)setUrl:(NSString*)url
{
	[self setObject:url forKey:URLKey];
}

- (NSString*)tenant
{
	return [self stringForKey:TenantKey];
}

- (void)setTenant:(NSString*)tenant
{
	[self setObject:tenant forKey:TenantKey];
}

- (NSString*)username
{
	return [self stringForKey:UsernameKey];
}

- (void)setUsername:(NSString*)username
{
	[self setObject:username forKey:UsernameKey];
}

- (NSString*)authTicket
{
	return [self stringForKey:AuthTicketKey];
}

- (void)setAuthTicket:(NSString*)authTicket
{
	[self setObject:authTicket forKey:AuthTicketKey];
}

@end
