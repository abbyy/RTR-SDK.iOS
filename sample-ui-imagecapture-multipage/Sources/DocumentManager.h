// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

#import <UIKit/UIKit.h>
#import <AbbyyUI/AbbyyUI.h>
#import "RecognizerEngine.h"

NS_ASSUME_NONNULL_BEGIN

/// ConfigurationProfile
@interface Profile: NSObject

@property (nonatomic, copy) NSString* name;
@property (nonatomic, assign) NSUInteger requiredPageCount;
@property (nonatomic, assign) AUIDocumentSize documentSize;
@property (nonatomic, assign) CGFloat minAspectRatio;
@property (nonatomic, assign) CGFloat maxAspectRatio;
@property (nonatomic, copy) NSString* storagePath;

@end

typedef void (^PdfCompletion)(NSString* path, NSError* error);

/// Utility class for working with captured documents
@interface DocumentManager : NSObject

/// Get shared manager
@property (class, nonatomic, readonly) DocumentManager* sharedManager;

@property (nonatomic, readonly) NSString* storagePath;

@property (nonatomic, readonly) NSArray<Profile*>* profiles;

/// Create PDF document from saved images
- (void)generatePdfForCaptureResult:(id<AUIMultiPageImageCaptureResult>)captureResult withCompletion:(PdfCompletion)completion;

@end

NS_ASSUME_NONNULL_END
