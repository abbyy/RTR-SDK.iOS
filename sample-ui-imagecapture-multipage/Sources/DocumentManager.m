// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

#import "DocumentManager.h"

@implementation Profile

+ (Profile*)profileWithName:(NSString*)name requiredPageCount:(NSUInteger)requiredPagesCount documentSize:(AUIDocumentSize)documentSize minAspectRatio:(CGFloat)minAspectRatio maxAspectRatio:(CGFloat)maxAspectRatio storagePath:(NSString*)storagePath
{
	Profile* profile = [Profile new];
	profile.name = name;
	profile.requiredPageCount = requiredPagesCount;
	profile.minAspectRatio = minAspectRatio;
	profile.maxAspectRatio = maxAspectRatio;
	profile.storagePath = [storagePath stringByAppendingPathComponent:name];
	return profile;
}

/// BusinessCard.
+ (Profile*)oneBusinessCardAtStoragePath:(NSString*)path;
{
	return [self profileWithName:@"One Business Card" requiredPageCount:1 documentSize:AUIDocumentSizeBusinessCard minAspectRatio:1.38 maxAspectRatio:2.09 storagePath:path];
}

/// A4 document.
+ (Profile*)a4DocumentsAtStoragePath:(NSString*)path;
{
	return [self profileWithName:@"A4 Document" requiredPageCount:0 documentSize:AUIDocumentSizeA4 minAspectRatio:0 maxAspectRatio:0 storagePath:path];
}

/// Unknown document set.
+ (Profile*)unknownDocumentsAtStoragePath:(NSString*)path
{
	return [self profileWithName:@"Unknown Set" requiredPageCount:0 documentSize:AUIDocumentSizeAny minAspectRatio:1 maxAspectRatio:CGFLOAT_MAX storagePath:path];
}

@end

/// Base functionality for files' containers with various types
@interface FileContainer : NSObject

/// Returns root directory path
@property (nonatomic, strong) NSString* directory;
/// File Name of controlled files
@property (nonatomic, readonly) NSString* filename;
/// Creates container with custom storage path
- (instancetype)initWithDirectory:(NSString*)directory;
/// Process images from imageSource. If imageSource returns nil then stop.
- (NSString*)processImages:(UIImage*(^)(void))imageSource;
/// Remove all files from container
- (void)clear;

@end

@implementation FileContainer

- (instancetype)initWithDirectory:(NSString*)directory
{
	self = [super init];
	if(self != nil) {
		self.directory = directory;
	}
	return self;
}

- (NSString*)processImages:(UIImage*(^)(void))imageSource
{
	// Generate container filename from current time
	NSString* path = [self.directory stringByAppendingPathComponent:self.filename];
	// Create export operation instance with file output stream
	RTRFileOutputStream* stream = [[RTRFileOutputStream alloc] initWithFilePath:path];
	id<RTRCoreAPIExportOperation> operation = [self exportOperation:stream];
	// Add image to container
	for (UIImage* nextImage = imageSource(); nextImage != nil; nextImage = imageSource()) {
		[operation addPageWithImage:nextImage];
	}
	// operation has to be closed
	return [operation close] ? path : nil;
}

- (void)clear
{
	// Remove all files from root directory
	[[NSFileManager defaultManager] removeItemAtPath:self.directory error:nil];
}

- (NSString*)directory
{
	if(_directory != nil) {
		return _directory;
	}
	// Temp folder
	return NSTemporaryDirectory();
}

- (NSString*)filename
{
	// override
	return nil;
}

- (id<RTRCoreAPIExportOperation>)exportOperation:(RTRFileOutputStream*)stream
{
	// override
	return nil;
}

- (id<RTRCoreAPI>)coreApi
{
	return [[RecognizerEngine rtrEngine] createCoreAPI];
}

@end

//----------------------------------------------------------

@interface PdfContainer : FileContainer

@end

@implementation PdfContainer

- (id<RTRCoreAPIExportOperation>)exportOperation:(RTRFileOutputStream*)stream
{
	return [self.coreApi createExportToPdfOperation:stream];
}

- (NSString*)filename
{
	NSDateFormatter* formatter = [NSDateFormatter new];
	formatter.dateStyle = NSDateFormatterMediumStyle;
	formatter.timeStyle = NSDateFormatterMediumStyle;
	NSString* dateString = [formatter stringFromDate:[NSDate date]];
	return [NSString stringWithFormat:@"ImageCapture - %@.pdf", dateString];
}

@end

//----------------------------------------------------------

@interface DocumentManager ()

/// Document folder
@property (nonatomic, strong) NSString* storagePath;
@property (nonatomic, strong) PdfContainer* pdfContainer;

@end

@implementation DocumentManager

@synthesize profiles = _profiles;

+ (instancetype)sharedManager
{
	static dispatch_once_t onceToken;
	static DocumentManager* sharedManager;
	dispatch_once(&onceToken, ^{
		sharedManager = [[self class] new];
	});
	return sharedManager;
}

- (instancetype)init
{
	self = [super init];
	if(self) {
		self.storagePath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
	}
	return self;
}

- (PdfContainer*)pdfContainer
{
	if(_pdfContainer == nil) {
		_pdfContainer = [PdfContainer new];
	}
	return _pdfContainer;
}

- (void)generatePdfForCaptureResult:(id<AUIMultiPageImageCaptureResult>)captureResult withCompletion:(PdfCompletion)completion;
{
	// remove old files
	[self.pdfContainer clear];
	// generate new
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		__block NSError* error;
		NSArray* identifiers = [captureResult pagesWithError:&error];
		NSString* path;
		if(identifiers != nil) {
			__block NSUInteger i = 0;
			NSUInteger count = identifiers.count;
			path = [self.pdfContainer processImages:^UIImage*{
				if(i >= count) {
					return nil;
				}
				UIImage* image = [captureResult loadImageWithId:identifiers[i] error:&error];
				i++;
				return image;
			}];
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			if(completion != nil) {
				completion(path, error);
				error = nil;
			}
		});
	});
}

- (NSArray<Profile*>*) profiles
{
	if(_profiles == nil) {
		_profiles = @[[Profile unknownDocumentsAtStoragePath:self.storagePath],
					  [Profile a4DocumentsAtStoragePath:self.storagePath],
					  [Profile oneBusinessCardAtStoragePath:self.storagePath]];
	}
	return _profiles;
}

@end
