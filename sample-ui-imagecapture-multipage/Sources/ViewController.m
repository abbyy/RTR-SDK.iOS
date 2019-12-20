// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

#import "ViewController.h"
#import "DocumentManager.h"

////////////////////////////////////////////////////
/// Captured document thumbnails
@interface CollectionViewCell : UICollectionViewCell

@property (nonatomic, weak) IBOutlet UIImageView* imageView;
@property (nonatomic, copy) void (^thumbnailLoader)(void);

@end

@implementation CollectionViewCell

- (void)prepareForReuse
{
	[super prepareForReuse];
	self.imageView.image = nil;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
@interface ViewController () <UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, AUIMultiPageImageCaptureScenarioDelegate, AUIMultiPageCaptureSettings>

/// Camera controller
@property (nonatomic, strong) AUICaptureController* captureController;
/// Document handler
@property (nonatomic, strong) DocumentManager* documentManager;

/// Thumbnails collection
@property (nonatomic, weak) IBOutlet UICollectionView* collectionView;

/// Add more pages button
@property (nonatomic, weak) IBOutlet UIButton* addButton;
/// Share PDF button
@property (nonatomic, weak) IBOutlet UIButton* shareButton;
/// App build version text
@property (nonatomic, weak) IBOutlet UILabel* versionLabel;

@property (nonatomic, strong) IBOutlet UISegmentedControl* profilesSegmentedControl;

@property (nonatomic, strong, nullable) AUIMultiPageImageCaptureScenario* captureScenario;
@property (nonatomic, readonly) id<AUIMultiPageImageCaptureResult> capturedImages;
@property (nonatomic, strong, null_resettable) NSArray<NSString*>* resultImageIdentifiers;

@end

//////////////////////////////
@implementation ViewController

- (UIViewController*)topController
{
	UIViewController* topController = [UIApplication sharedApplication].keyWindow.rootViewController;
	if(topController == nil) {
		topController = self;
	}
	while(topController.presentedViewController != nil) {
		topController = topController.presentedViewController;
	}
	return topController;
}

- (void)showError:(NSError*)error withCompletion:(nullable void(^)(void))completion
{
	__block NSError* theError = error;
	dispatch_async(dispatch_get_main_queue(), ^{
		if(error == nil) {
			NSDictionary* userInfo = @{NSLocalizedDescriptionKey : NSLocalizedString(@"Unexpected error occured", nil)};
			theError = [NSError errorWithDomain:@"Develop" code:0 userInfo:userInfo];
		}
		UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"SomethingWentWrong", nil)
			message:theError.localizedDescription
			preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Ok", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction* _Nonnull action) {
			theError = nil;
			if(completion != nil) {
				completion();
			}
		}]];
		[[self topController] presentViewController:alert animated:YES completion:nil];
	});
}

- (void)viewDidLoad
{
	[super viewDidLoad];

	[self setupSegmentedControl];

	NSError* error;
	if(![self createCaptureScenarioWithError:&error]) {
		[self showError:error withCompletion:nil];
	}

	[self updateButtons];
	self.versionLabel.text = [NSString stringWithFormat:@"Build Number: %@", [RecognizerEngine version]];

	self.profilesSegmentedControl.apportionsSegmentWidthsByContent = YES;
}

- (void)setupSegmentedControl
{
	UISegmentedControl* sc = self.profilesSegmentedControl;
	[sc removeAllSegments];
	for(Profile* profile in DocumentManager.sharedManager.profiles) {
		[sc insertSegmentWithTitle:profile.name atIndex:sc.numberOfSegments animated:NO];
	}
	sc.selectedSegmentIndex = 0;
}

- (BOOL)createCaptureScenarioWithError:(NSError**)error
{
	self.resultImageIdentifiers = nil;
	RTREngine* rtrEngine = [RecognizerEngine rtrEngine];
	if(rtrEngine == nil) {
		if(error != nil) {
			NSDictionary* userInfo = @{NSLocalizedDescriptionKey : NSLocalizedString(@"InvalidLicenseMessage", nil)};
			*error = [NSError errorWithDomain:@"Custom" code:0 userInfo:userInfo];
		}
		return NO;
	}

	Profile* profile = DocumentManager.sharedManager.profiles[self.profilesSegmentedControl.selectedSegmentIndex];

	// Scenario contains documents capture settings. Set it up before presenting camera view.
	AUIMultiPageImageCaptureScenario* scenario = [[AUIMultiPageImageCaptureScenario alloc]
		initWithEngine:rtrEngine
		storagePath:profile.storagePath
		error:error];
	if(scenario == nil) {
		return NO;
	}
	scenario.delegate = self;
	scenario.captureSettings = self;

	scenario.requiredPageCount = profile.requiredPageCount;

	self.captureScenario = scenario;

	return YES;
}

- (void)updateButtons
{
	// hide buttons if nothing to add or share
	self.addButton.hidden = self.self.resultImageIdentifiers.count == 0;
	self.shareButton.hidden = self.resultImageIdentifiers.count == 0;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
	return UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone ? UIInterfaceOrientationMaskPortrait : UIInterfaceOrientationMaskAll;
}

- (DocumentManager*)documentManager
{
	if(_documentManager == nil) {
		_documentManager = DocumentManager.sharedManager;
	}
	return _documentManager;
}

- (id<AUIMultiPageImageCaptureResult>)capturedImages
{
	id<AUIMultiPageImageCaptureResult> result = self.captureScenario.result;
	return result;
}

- (NSArray<NSString*>*)resultImageIdentifiers
 {
	if(_resultImageIdentifiers == nil) {
		if(self.captureScenario == nil) {
			_resultImageIdentifiers = @[];
		} else {
			NSError* error;
			_resultImageIdentifiers = [self.capturedImages pagesWithError:&error];
			if(_resultImageIdentifiers == nil) {
				[self showError:error withCompletion:nil];
				_resultImageIdentifiers = @[];
			}
		}
 	}
	return _resultImageIdentifiers;
 }

- (void)showCaptureController
{
	if(self.captureScenario == nil) {
		return;
	}
	AUICaptureController* captureController = [AUICaptureController new];
	captureController.captureScenario = self.captureScenario;
	captureController.flashButton.hidden = ![UIImagePickerController isFlashAvailableForCameraDevice:UIImagePickerControllerCameraDeviceRear];
	captureController.modalPresentationStyle = UIModalPresentationFullScreen;
	[self presentViewController:captureController animated:YES completion:nil];
	self.captureController = captureController;
}

- (void)hideCaptureController
{
	[self.collectionView reloadData];
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)didPressStartButton:(UIButton*)sender
{
	// For new document create new scenario.
	NSError* error;
	if(![self createCaptureScenarioWithError:&error]) {
		[self showError:error withCompletion:nil];
		return;
	}
	if([self.capturedImages clearWithError:&error]) {
		[self showCaptureController];
	} else {
		[self showError:error withCompletion:nil];
	}
}

- (IBAction)didPressAddButton:(UIButton*)sender
{
	[self showCaptureController];
}

- (IBAction)didPressExportButton:(UIButton*)sender
{
	UIAlertController* progress = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"ExportInProgress", nil) message:nil preferredStyle:UIAlertControllerStyleAlert];
	[self presentViewController:progress animated:YES completion:nil];
	// Share PDF file from captured images
	[self.documentManager generatePdfForCaptureResult:self.capturedImages withCompletion:^(NSString* path, NSError* error) {
		[self dismissViewControllerAnimated:YES completion:^{
			if(path == nil) {
				[self showError:error withCompletion:nil];
			} else {
				NSAssert(path != nil, @"Unexpected");
				UIActivityViewController* viewController = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
				viewController.popoverPresentationController.sourceView = self.shareButton;
				[self presentViewController:viewController animated:YES completion:nil];
			}
		}];
	}];
}

- (IBAction)onProfileChanged:(UISegmentedControl*)sender
{
	NSError* error;
	if(![self createCaptureScenarioWithError:&error]) {
		[self showError:error withCompletion:nil];
	} else {
		[self.collectionView reloadData];
		[self updateButtons];
	}
}

#pragma mark - UIVollectionView

- (NSInteger)collectionView:(UICollectionView*)collectionView numberOfItemsInSection:(NSInteger)section
{
	return self.resultImageIdentifiers.count;
}

- (UICollectionViewCell*)collectionView:(UICollectionView*)collectionView cellForItemAtIndexPath:(NSIndexPath*)indexPath
{
	CollectionViewCell* cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"Cell" forIndexPath:indexPath];
	NSAssert([cell isKindOfClass:CollectionViewCell.class], @"Unexpected");
	return cell;
}

- (void)collectionView:(UICollectionView*)collectionView willDisplayCell:(CollectionViewCell*)cell forItemAtIndexPath:(NSIndexPath*)indexPath
{
	// Asynchronous loading of image thumbnails.
	NSString* identifier = self.resultImageIdentifiers[indexPath.row];
	__weak typeof(self) wSelf = self;
	__weak typeof(cell) wCell = cell;
	__block void(^thumbnailLoader)(void) = ^{
		NSError* error;
		UIImage* thumbnail = [self.capturedImages loadThumbnailWithId:identifier error:&error];
		dispatch_async(dispatch_get_main_queue(), ^{
			__strong typeof(wCell) sCell = wCell;
			if(sCell.thumbnailLoader == thumbnailLoader) {
				if(thumbnail != nil) {
					sCell.imageView.image = thumbnail;
				} else {
					[wSelf showError:error withCompletion:nil];
				}
			}
			thumbnailLoader = nil;
			sCell.thumbnailLoader = nil;
		});
	};
	cell.thumbnailLoader = thumbnailLoader;
	NSAssert(cell.thumbnailLoader == thumbnailLoader, @"Unexpected");
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), thumbnailLoader);
}

- (void)collectionView:(UICollectionView*)collectionView didEndDisplayingCell:(CollectionViewCell*)cell forItemAtIndexPath:(NSIndexPath*)indexPath
{
	cell.thumbnailLoader = nil;
}

- (CGSize)collectionView:(UICollectionView*)collectionView layout:(UICollectionViewFlowLayout*)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath*)indexPath
{
	// Calculate correct item size
	CGFloat viewWidth = collectionView.frame.size.width;
	CGFloat itemWidth = collectionViewLayout.itemSize.width;
	CGFloat space = collectionViewLayout.minimumInteritemSpacing;
	NSInteger count = viewWidth / itemWidth;
	if(count > 0) {
		itemWidth = (NSInteger)(viewWidth - space * (count - 1)) / count;
	}
	return CGSizeMake(itemWidth, itemWidth);
}

- (void)collectionView:(UICollectionView*)collectionView didSelectItemAtIndexPath:(NSIndexPath*)indexPath
{
	[collectionView deselectItemAtIndexPath:indexPath animated:YES];
	UIAlertController* alert = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];

	[alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Open Page", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
		[self openPageAtIndexPath:indexPath];
	}]];

	[alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Share Page", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
		[self sharePageAtIndexPath:indexPath];
	}]];

	[alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Delete Page", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
		[self deletePageAtIndexPath:indexPath];
	}]];

	[alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleDefault handler:nil]];

	if(alert.popoverPresentationController != nil) {
		alert.modalPresentationStyle = UIModalPresentationPopover;
		alert.popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirectionUp | UIPopoverArrowDirectionDown;
		alert.popoverPresentationController.sourceView = [self.collectionView cellForItemAtIndexPath:indexPath];
	}

	[[self topController] presentViewController:alert animated:YES completion:nil];
}

- (void)openPageAtIndexPath:(NSIndexPath*)indexPath
{
	self.captureScenario.startAsEditorAtPageId = [self resultImageIdentifiers][indexPath.row];
	[self showCaptureController];
}

- (void)sharePageAtIndexPath:(NSIndexPath*)indexPath
{
	UIAlertController* progress = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"ExportInProgress", nil) message:nil preferredStyle:UIAlertControllerStyleAlert];
	[self presentViewController:progress animated:YES completion:nil];

	dispatch_async(dispatch_get_main_queue(), ^{
		NSError* error;
		UIImage* image = [self.capturedImages loadImageWithId:self.resultImageIdentifiers[indexPath.row] error:&error];
		[progress.presentingViewController dismissViewControllerAnimated:YES completion:^{
			if(image == nil) {
				[self showError:error withCompletion:nil];
				return;
			}

			UIActivityViewController* viewController = [[UIActivityViewController alloc] initWithActivityItems:@[image] applicationActivities:nil];
			viewController.popoverPresentationController.sourceView = self.shareButton;
			[[self topController] presentViewController:viewController animated:YES completion:nil];
		}];
	});
}

- (void)deletePageAtIndexPath:(NSIndexPath*)indexPath
{
	[self.collectionView performBatchUpdates:^{
		NSError* error;
		if(![self.capturedImages deleteWithId:self.resultImageIdentifiers[indexPath.row] error:&error]) {
			[self showError:error withCompletion:nil];
			return;
		}
		[self.collectionView deleteItemsAtIndexPaths:@[indexPath]];
		self.resultImageIdentifiers = nil;
	} completion:nil];
}

#pragma mark - AUIMultiPageImageCaptureScenarioDelegate

- (void)captureScenario:(AUIImageCaptureScenario*)scenario didFailWithError:(nonnull NSError*)error result:(nonnull id<AUIMultiPageImageCaptureResult>)result
{
	[self showError:error withCompletion:^{
		[self dismissCaptureController];
	}];
}

- (void)captureScenario:(nonnull AUIMultiPageImageCaptureScenario*)captureScenario didFinishWithResult:(nonnull id<AUIMultiPageImageCaptureResult>)result
{
	[self dismissCaptureController];
}

- (void)dismissCaptureController
{
	self.resultImageIdentifiers = nil;
	[self dismissViewControllerAnimated:YES completion:nil];
	[self.collectionView reloadData];
	[self updateButtons];
}

- (void)captureScenario:(nonnull AUIMultiPageImageCaptureScenario*)captureScenario onCloseWithResult:(nonnull AUICaptureController*)captureController
{
	captureScenario.active = NO;
	NSError* error;
	NSArray* pages = [captureScenario.result pagesWithError:&error];
	if(pages == nil) {
		[self showError:error withCompletion:nil];
		return;
	}
	if(pages.count == 0) {
		[self dismissCaptureController];
		return;
	}

	UIAlertController* alert = [UIAlertController
		alertControllerWithTitle:nil
		message:NSLocalizedString(@"AllPagesOnCurrentSessionWillBeDeletedWarning?", nil)
		preferredStyle:UIAlertControllerStyleAlert];

	[alert addAction:[UIAlertAction
		actionWithTitle:NSLocalizedString(@"Cancel", nil)
		style:UIAlertActionStyleCancel
		handler:^(UIAlertAction* _Nonnull action)
		{
			captureScenario.active = YES;
		}]];

	[alert addAction:[UIAlertAction
		actionWithTitle:NSLocalizedString(@"Confirm", nil)
		style:UIAlertActionStyleDestructive
		handler:^(UIAlertAction* _Nonnull action)
		{
			NSError* error;
			if(![captureScenario.result clearWithError:&error]) {
				[self showError:error withCompletion:nil];
			}
			[self dismissCaptureController];
		}]];

	[self.presentedViewController presentViewController:alert animated:YES completion:nil];
}

#pragma mark - AUIMultiPageCaptureSettings

- (void)captureScenario:(nonnull AUIMultiPageImageCaptureScenario*)captureScenario
	onConfigureImageCaptureSettings:(nonnull id<AUIImageCaptureSettings>)settings
	forPageAtIndex:(NSUInteger)index
{
	Profile* profile = DocumentManager.sharedManager.profiles[self.profilesSegmentedControl.selectedSegmentIndex];
	settings.documentSize = profile.documentSize;
	settings.aspectRatioMin = profile.minAspectRatio;
	settings.aspectRatioMax = profile.maxAspectRatio;
}

@end
