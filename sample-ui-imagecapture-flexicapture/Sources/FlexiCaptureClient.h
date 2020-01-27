/// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
/// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FlexiCaptureClient : NSObject

+ (void)requestProjectsListWithUrl:(NSString*)url tenant:(NSString*)tenant username:(NSString*)username password:(NSString*)password success:(void (^)(NSString*, NSArray*))success fail:(void (^)(NSError*))fail;

+ (void)requestProjectsListWithUrl:(NSString*)url tenant:(NSString*)tenant authTicket:(NSString*)authTicket success:(void (^)(NSString*, NSArray*))success fail:(void (^)(NSError*))fail;

+ (void)sendFiles:(NSArray*)files withProject:(NSString*)projectName withUrl:(NSString*)url tenant:(NSString*)tenant username:(NSString*)username password:(NSString*)password success:(void (^)(NSString*))success fail:(void (^)(NSError*))fail;

+ (void)sendFiles:(NSArray*)files withProject:(NSString*)projectName withUrl:(NSString*)url tenant:(NSString*)tenant authTicket:(NSString*)authTicket success:(void (^)(NSString*))success fail:(void (^)(NSError*))fail;

+ (void)cancelAllRequests;

@end

NS_ASSUME_NONNULL_END
