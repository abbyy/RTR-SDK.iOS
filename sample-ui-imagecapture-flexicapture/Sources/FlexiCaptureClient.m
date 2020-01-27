/// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
/// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

#import "FlexiCaptureClient.h"

#import <CommonCrypto/CommonDigest.h>

static NSString* const FlexiCaptureUrlTemplate = @"%@/flexicapture12/Server/MobileApp/v1";

static NSString* const MultipartRequestBoundary = @"AbbyyUIMultipageCaptureToFlexiCaptureSample";
static NSString* const MultipartRequestContentDispositionNameTemplate = @"Content-Disposition: form-data; name=\"%@\"\r\n\r\n%@";
static NSString* const MultipartRequestContentDispositionFileTemplate = @"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\nContent-MD5: %@\r\n\r\n";

static NSString* const FlexiCaptureClientErrorDomain = @"com.abbyy.rtr.ui.sample.imagecapture.flexicapture";

@interface FlexiCaptureClient ()

@property (nonatomic, weak) NSURLSessionDataTask* currentTask;

@end

@implementation FlexiCaptureClient

+ (FlexiCaptureClient*)shared
{
	static FlexiCaptureClient* shared = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		shared = [self new];
	});
	return shared;
}

+ (void)requestProjectsListWithUrl:(NSString*)url tenant:(NSString*)tenant username:(NSString*)username password:(NSString*)password success:(void (^)(NSString*, NSArray*))success fail:(void (^)(NSError*))fail;
{
	[self requestProjectsListWithUrl:url Tenant:tenant authorization:[self authWithUsername:username password:password] success:success fail:fail];
}

+ (void)requestProjectsListWithUrl:(NSString*)url tenant:(NSString*)tenant authTicket:(NSString*)authTicket success:(void (^)(NSString*, NSArray*))success fail:(void (^)(NSError*))fail;
{
	[self requestProjectsListWithUrl:url Tenant:tenant authorization:[self authWithToken:authTicket] success:success fail:fail];
}

+ (void)requestProjectsListWithUrl:(NSString*)url Tenant:(NSString*)tenant authorization:(void (^)(NSMutableURLRequest*))auth success:(void (^)(NSString*, NSArray*))success fail:(void (^)(NSError*))fail
{
	NSString* urlTemplate = FlexiCaptureUrlTemplate;
	if(tenant.length > 0) {
		urlTemplate = [urlTemplate stringByAppendingString:@"?tenant=%@"];
	}
	NSURL* fullUrl = [NSURL URLWithString:[NSString stringWithFormat:urlTemplate, url, [self urlEncodeUsingEncoding:tenant]]];

	NSMutableURLRequest* request = [[NSMutableURLRequest alloc] init];
	[request setHTTPShouldHandleCookies:NO];
	[request setHTTPMethod:@"GET"];
	[request setURL:fullUrl];

	auth(request);

	NSURLSession* session = [NSURLSession sharedSession];
	NSURLSessionDataTask* task = [session dataTaskWithRequest:request
		completionHandler:^(NSData* _Nullable data, NSURLResponse* _Nullable response, NSError* _Nullable error) {
		if(error == nil) {
			NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
			if(httpResponse.statusCode != 200) {
				switch(httpResponse.statusCode) {
					case 401:
						fail([self errorWithCode:httpResponse.statusCode descriptionLocalizedStringKey:@"WrongUsernameOrPassword"]);
						break;
					default:
						fail([self errorWithCode:httpResponse.statusCode descriptionLocalizedStringKey:@"UnknownError"]);
						break;
				}

				return;
			}

			NSString* token = @"";
			if([response respondsToSelector:@selector(allHeaderFields)]) {
				NSDictionary* headerDictionary = [httpResponse allHeaderFields];
				token = [headerDictionary objectForKey:@"AuthTicket"];
			}
			if(token == nil || token.length == 0) {
				fail([self errorWithCode:httpResponse.statusCode descriptionLocalizedStringKey:@"UnknownError"]);
				return;
			}

			NSError* parsingError = nil;
			NSDictionary* responseDictionary = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&parsingError];
			if(responseDictionary == nil) {
				fail([self errorWithCode:httpResponse.statusCode descriptionLocalizedStringKey:@"UnknownError"]);
				return;
			}
			NSArray* projects = responseDictionary[@"projects"];
			if(projects == nil) {
				fail([self errorWithCode:httpResponse.statusCode descriptionLocalizedStringKey:@"UnknownError"]);
				return;
			}

			success(token, projects);
		} else {
			fail(error);
		}
	}];

	[self cancelAllRequests];
	[self shared].currentTask = task;

	[task resume];
}

+ (void)sendFiles:(NSArray*)files withProject:(NSString*)projectName withUrl:(NSString*)url tenant:(NSString*)tenant username:(NSString*)username password:(NSString*)password success:(void (^)(NSString*))success fail:(void (^)(NSError*))fail
{
	[self sendFiles:files withProject:projectName withUrl:url tenant:tenant authorization:[self authWithUsername:username password:password] success:success fail:fail];
}

+ (void)sendFiles:(NSArray*)files withProject:(NSString*)projectName withUrl:(NSString*)url tenant:(NSString*)tenant authTicket:(NSString*)authTicket success:(void (^)(NSString*))success fail:(void (^)(NSError*))fail
{
	[self sendFiles:files withProject:projectName withUrl:url tenant:tenant authorization:[self authWithToken:authTicket] success:success fail:fail];
}

+ (void)sendFiles:(NSArray*)files withProject:(NSString*)projectName withUrl:(NSString*)url tenant:(NSString*)tenant authorization:(void (^)(NSMutableURLRequest*))auth success:(void (^)(NSString*))success fail:(void (^)(NSError*))fail
{
	NSString* urlTemplate = FlexiCaptureUrlTemplate;
	if(tenant.length > 0) {
		urlTemplate = [urlTemplate stringByAppendingString:@"?tenant=%@"];
	}
	NSURL* fullUrl = [NSURL URLWithString:[NSString stringWithFormat:urlTemplate, url, [self urlEncodeUsingEncoding:tenant]]];

	NSMutableURLRequest* request = [[NSMutableURLRequest alloc] init];
	[request setHTTPShouldHandleCookies:NO];
	[request setHTTPMethod:@"POST"];
	[request setURL:fullUrl];

	[request addValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", MultipartRequestBoundary]
		forHTTPHeaderField:@"Content-Type"];

	auth(request);

	NSMutableData* postbody = [NSMutableData data];

	[postbody appendData:[[NSString stringWithFormat:@"\r\n--%@\r\n", MultipartRequestBoundary]
		dataUsingEncoding:NSUTF8StringEncoding]];

	[postbody appendData:[[NSString stringWithFormat:MultipartRequestContentDispositionNameTemplate, @"projectName", projectName]
		dataUsingEncoding:NSUTF8StringEncoding]];

	for(NSString* filePath in files) {
		[postbody appendData:[[NSString stringWithFormat:@"\r\n--%@\r\n", MultipartRequestBoundary]
			dataUsingEncoding:NSUTF8StringEncoding]];

		NSString* fileName = [filePath lastPathComponent];

		NSData* fileData = [NSData dataWithContentsOfFile:filePath];

		[postbody appendData:[[NSString stringWithFormat:MultipartRequestContentDispositionFileTemplate, fileName, fileName, [self calcMD5HashForData:fileData]]
			dataUsingEncoding:NSUTF8StringEncoding]];

		[postbody appendData:fileData];
	}

	[postbody appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", MultipartRequestBoundary]
		dataUsingEncoding:NSUTF8StringEncoding]];

	[request setHTTPBody:postbody];

	NSURLSession* session = [NSURLSession sharedSession];
	NSURLSessionDataTask* task = [session dataTaskWithRequest:request
		completionHandler:^(NSData* _Nullable data, NSURLResponse* _Nullable response, NSError* _Nullable error) {
		if(error == nil) {
			NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
			if(httpResponse.statusCode != 201) {
				switch(httpResponse.statusCode) {
					case 401:
						fail([self errorWithCode:httpResponse.statusCode descriptionLocalizedStringKey:@"WrongUsernameOrPassword"]);
						break;
					default:
						fail([self errorWithCode:httpResponse.statusCode descriptionLocalizedStringKey:@"UnknownError"]);
						break;
				}

				return;
			}

			NSString* token = @"";
			if([response respondsToSelector:@selector(allHeaderFields)]) {
				NSDictionary* headerDictionary = [httpResponse allHeaderFields];
				token = [headerDictionary objectForKey:@"AuthTicket"];
			}
			if(token == nil || token.length == 0) {
				fail([self errorWithCode:httpResponse.statusCode descriptionLocalizedStringKey:@"UnknownError"]);
				return;
			}

			success(token);
		} else {
			fail(error);
		}
	}];

	[self cancelAllRequests];
	[self shared].currentTask = task;

	[task resume];
}

+ (void)cancelAllRequests
{
	NSURLSessionDataTask* task = [self shared].currentTask;
	if(task != nil) {
		if(task.state == NSURLSessionTaskStateRunning) {
			[task cancel];
			[self shared].currentTask = nil;
		}
	}
}

+ (void (^)(NSMutableURLRequest*))authWithToken:(NSString*)authToken
{
	return ^(NSMutableURLRequest* request){
		NSString* authStr = [NSString stringWithFormat:@"Bearer %@", authToken];
		[request setValue:authStr forHTTPHeaderField:@"Authorization"];
	};
}

+ (void (^)(NSMutableURLRequest*))authWithUsername:(NSString*)username password:(NSString*)password
{
	return ^(NSMutableURLRequest* request){
		NSString* authStr = [NSString stringWithFormat:@"%@:%@", username, password];
		NSData* authData = [authStr dataUsingEncoding:NSUTF8StringEncoding];
		NSString* authValue = [NSString stringWithFormat:@"Basic %@", [authData base64EncodedStringWithOptions:0]];
		[request setValue:authValue forHTTPHeaderField:@"Authorization"];
	};
}

+ (NSError*)errorWithCode:(NSInteger)errorCode descriptionLocalizedStringKey:(NSString*)key
{
	return [self errorWithCode:errorCode description:NSLocalizedString(key, nil)];
}

+ (NSError*)errorWithCode:(NSInteger)errorCode description:(NSString*)description
{
	return [[NSError alloc] initWithDomain:FlexiCaptureClientErrorDomain code:errorCode userInfo:@{NSLocalizedDescriptionKey : description}];
}

+ (NSString*)urlEncodeUsingEncoding:(NSString*)str
{
	return [str stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet alphanumericCharacterSet]];
}

+ (NSString*)calcMD5HashForData:(NSData*)fileData
{
	const char* rawBytes = fileData.bytes;

	unsigned char result[CC_MD5_DIGEST_LENGTH];
	CC_MD5(rawBytes, (CC_LONG)fileData.length, result);

	NSData* resultData = [NSData dataWithBytes:result length:CC_MD5_DIGEST_LENGTH];
	NSString* md5 = [resultData base64EncodedStringWithOptions:0];
	return md5;
}

@end
