// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

#import "ViewController.h"
#import "PreviewViewController.h"
#import "RecognizerEngine.h"
#import <AbbyyUI/AbbyyUI.h>

@interface ViewController () <AUIImageCaptureScenarioDelegate, PreviewViewControllerDelegate>

/// Camera controller
@property (nonatomic, strong) AUICaptureController* captureController;

/// Captured image
@property (nonatomic, strong) UIImage* capturedImage;

/// Captured image view
@property (nonatomic, weak) IBOutlet UIImageView* capturedImagePlaceholder;

/// Share  button
@property (nonatomic, weak) IBOutlet UIButton* shareButton;
/// App build version text
@property (nonatomic, weak) IBOutlet UILabel* versionLabel;

@end

@implementation ViewController

- (void)viewDidLoad
{
	[super viewDidLoad];
	self.versionLabel.text = [NSString stringWithFormat:@"Build Number: %@", [RecognizerEngine version]];
	[self updateState];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
	return UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone ? UIInterfaceOrientationMaskPortrait : UIInterfaceOrientationMaskAll;
}

- (void)setCapturedImage:(UIImage*)capturedImage
{
	if(_capturedImage == capturedImage) {
		return;
	}
	_capturedImage = capturedImage;
	[self updateState];
}

- (void)updateState
{
	// disable buttons if nothing to share
	self.shareButton.hidden = self.capturedImage == nil;
	self.capturedImagePlaceholder.image = self.capturedImage ?: [UIImage imageNamed:@"emptyCollection"];
}

- (void)completeCaptureSessionWithImage:(UIImage*)image
{
	self.capturedImage = image;
	[self hideCaptureController];
}

- (void)showCaptureController
{
	if(RecognizerEngine.rtrEngine == nil) {
		[self showInvalidEngineMessage];
		return;
	}
	AUICaptureController* captureController = [[AUICaptureController alloc] init];

	// Scenario contains documents capture settings. Set it up before camera view presenting
	AUIImageCaptureScenario* scenario = [[AUIImageCaptureScenario alloc] initWithEngine:[RecognizerEngine rtrEngine]];
	scenario.delegate = self;
	// To get UIImage in results
	scenario.cropEnabled = YES;
	captureController.captureScenario = scenario;
	captureController.flashButton.hidden = ![UIImagePickerController isFlashAvailableForCameraDevice:UIImagePickerControllerCameraDeviceRear];
	captureController.modalPresentationStyle = UIModalPresentationFullScreen;
	[self presentViewController:captureController animated:YES completion:nil];
	self.captureController = captureController;
}

- (void)showInvalidEngineMessage
{
	UIAlertController* alert = [UIAlertController
		alertControllerWithTitle: NSLocalizedString(@"SomethingWentWrong", nil)
		message: NSLocalizedString(@"InvalidLicenseMessage", nil)
		preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)hideCaptureController
{
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)didPressStartButton:(UIButton*)sender
{
	// Remove previous results
	self.capturedImage = nil;
	[self showCaptureController];
}

- (IBAction)didPressExportButton:(UIButton*)sender
{
	UIActivityViewController* viewController = [[UIActivityViewController alloc] initWithActivityItems:@[self.capturedImage] applicationActivities:nil];
	viewController.popoverPresentationController.sourceView = self.shareButton;
	viewController.popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirectionUp | UIPopoverArrowDirectionDown;
	[self presentViewController:viewController animated:YES completion:nil];
}

#pragma mark - Abbyy Mobile UI

- (void)captureScenarioDidCancel:(AUICaptureScenario*)scenario
{
	[self hideCaptureController];
}

- (void)captureScenario:(AUIImageCaptureScenario*)scenario didFailWithError:(nonnull NSError*)error
{
	NSLog(@"Capture controller error: %@", error);
	UIAlertController* alert = [UIAlertController
		alertControllerWithTitle:NSLocalizedString(@"SomethingWentWrong", nil)
		message:error.localizedDescription
		preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction
		actionWithTitle:NSLocalizedString(@"OK", nil)
		style:UIAlertActionStyleCancel
		handler:nil]];
	[self.captureController presentViewController:alert animated:YES completion:^{
		[self.captureController setPaused:YES];
	}];
}

- (void)captureScenario:(AUIImageCaptureScenario*)captureScenario didCaptureImageWithResult:(AUIImageCaptureResult*)result
{
	NSLog(@"did capture result %@", result);
	PreviewViewController* viewController = [self.storyboard instantiateViewControllerWithIdentifier:@"Preview"];
	viewController.image = result.image;
	viewController.delegate = self;
	[self.captureController pushViewController:viewController animated:YES];
}

#pragma mark - Preview Controller

- (void)previewController:(PreviewViewController*)viewController didCompleteWithImage:(UIImage*)image
{
	[self completeCaptureSessionWithImage:image];
}

- (void)previewControllerDidCancel:(PreviewViewController*)viewController
{
	[self.captureController popViewControllerAnimated:YES];
}

@end
