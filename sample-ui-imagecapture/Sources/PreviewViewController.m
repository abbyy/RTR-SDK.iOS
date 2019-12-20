// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

#import "PreviewViewController.h"

@interface PreviewViewController ()

@property (nonatomic, weak) IBOutlet UIImageView* imageView;

@end

@implementation PreviewViewController

- (void)viewDidLoad
{
	[super viewDidLoad];

	self.imageView.image = self.image;
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	[self setupNavigationBar];
}

- (void)setImage:(UIImage*)image
{
	_image = image;
	self.imageView.image = image;
}

- (void)setupNavigationBar
{
	[self.navigationController setNavigationBarHidden:NO animated:YES];
	self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
	UIBarButtonItem* cancelButton = [[UIBarButtonItem alloc]
		initWithTitle:NSLocalizedString(@"Delete", nil)
		style:UIBarButtonItemStylePlain
		target:self
		action:@selector(didPressCancel:)];
	cancelButton.tintColor = UIColor.whiteColor;
	self.navigationItem.title = NSLocalizedString(@"SinglePagePreviewTitle", nil);
	self.navigationItem.leftBarButtonItem = cancelButton;
}

- (void)didPressCancel:(id)sender
{
	if([self.delegate respondsToSelector:@selector(previewControllerDidCancel:)]) {
		[self.delegate previewControllerDidCancel:self];
	}
}

- (IBAction)didPressCloseButton:(UIButton*)sender
{
	if([self.delegate respondsToSelector:@selector(previewController:didCompleteWithImage:)]) {
		[self.delegate previewController:self didCompleteWithImage:self.image];
	}
}

@end
