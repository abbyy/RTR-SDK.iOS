/// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
/// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

#import "ViewController.h"

#import "SignInViewController.h"
#import "NSUserDefaults+FCSignInData.h"
#import "NSUserDefaults+FCUserData.h"
#import "FlexiCaptureClient.h"
#import "RecognizerEngine.h"

#import <AbbyyUI/AbbyyUI.h>

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

typedef NS_ENUM(NSUInteger, StartScreenState) {
	/// no project bar, no buttons
	StartScreenStateStart,
	/// no project bar, 'log in' and 'delete' buttons
	StartScreenStateWithDocumentsWithoutConnection,
	/// project bar, no buttons
	StartScreenStateWithoutDocumentsWithConnection,
	/// project bar, 'export' and 'delete' buttons
	StartScreenStateWithDocumentsWithConnection,
	/// project bar, documents preview blocked, buttons blocked, loading indicator
	StartScreenStateExportInProgress,
	/// project bar, documents preview blocked, 'export' button blocked, delete button
	StartScreenStateSuccessfullyExported,
};

@interface ViewController () <UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, AUIMultiPageImageCaptureScenarioDelegate>

@property (nonatomic, weak) IBOutlet UIView* projectBarView;
@property (nonatomic, weak) IBOutlet UIImageView* chainIconImageView;
@property (nonatomic, weak) IBOutlet UILabel* currentProjectLabel;
@property (nonatomic, weak) IBOutlet UIActivityIndicatorView* exportInProgressIndicator;
@property (nonatomic, weak) IBOutlet UIImageView* exportStatusImageView;

@property (nonatomic, weak) IBOutlet UIView* topActionBarView;
@property (nonatomic, weak) IBOutlet UILabel* pagesCountLabel;
@property (nonatomic, weak) IBOutlet UIButton* actionButton;

@property (nonatomic, weak) IBOutlet UIButton* deleteButton;

/// for ability to hide projectBarView
@property (nonatomic, weak) IBOutlet NSLayoutConstraint* separatorTopSpaceConstraint;

@property (nonatomic, weak) IBOutlet UICollectionView* previewCollectionView;
@property (nonatomic, weak) IBOutlet UIImageView* pagesPlaceholder;
@property (nonatomic, weak) IBOutlet UIView* pagesFadeEffectView;

@property (nonatomic, weak) IBOutlet UIView* scanNewDocButtonView;
@property (nonatomic, weak) IBOutlet UIButton* scanNewDocButton;

@property (nonatomic, weak) IBOutlet UIView* scanNewDocMiniButtonView;
@property (nonatomic, weak) IBOutlet UIButton* scanNewDocMiniButton;

@property (nonatomic, assign) StartScreenState currentScreenState;

@property (nonatomic, strong, nullable) AUIMultiPageImageCaptureScenario* captureScenario;
@property (nonatomic, strong) NSArray<NSString*>* resultImageIdentifiers;

@end

@implementation ViewController

- (void)viewDidLoad
{
	[super viewDidLoad];

	self.previewCollectionView.delegate = self;
	self.previewCollectionView.dataSource = self;

	[self.previewCollectionView registerNib:[UINib nibWithNibName:@"CollectionViewCell" bundle:nil] forCellWithReuseIdentifier:@"CollectionViewCell"];

	[[NSNotificationCenter defaultCenter] addObserver:self
		selector:@selector(orientationChanged)
		name:UIDeviceOrientationDidChangeNotification object:nil];

}

- (void)dealloc
{
	[NSNotificationCenter.defaultCenter removeObserver:self name:UIDeviceOrientationDidChangeNotification object:nil];
}

- (void)viewDidLayoutSubviews
{
	[super viewDidLayoutSubviews];

	self.scanNewDocButton.layer.cornerRadius = self.scanNewDocButton.frame.size.height / 2;
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	NSError* error = nil;
	self.resultImageIdentifiers = [self.captureScenario.result pagesWithError:&error];
	if(self.resultImageIdentifiers == nil) {
		[self showError:error withCompletion:nil];
	}

	[self clearState];

	self.navigationController.navigationBarHidden = YES;
}

- (void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];

	if(self.currentScreenState == StartScreenStateStart
		|| self.currentScreenState == StartScreenStateWithDocumentsWithoutConnection)
	{
		[self hideProjectBarView];
	}
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
	[self.previewCollectionView.collectionViewLayout invalidateLayout];
}

- (IBAction)onSettings:(id)sender
{
	[self showSettings];
}

- (IBAction)onScanNewDoc:(id)sender
{
	if(self.currentScreenState == StartScreenStateSuccessfullyExported) {
		[self clearResults];
	}

	[self showCameraWithPageId:nil];
}

- (IBAction)onDelete:(id)sender
{
	if(self.currentScreenState == StartScreenStateSuccessfullyExported) {
		[self clearResults];
		[self clearState];
	} else {
		UIAlertController* alert = [UIAlertController
			alertControllerWithTitle:NSLocalizedString(@"DeleteAll", nil)
			message:NSLocalizedString(@"AreYouSure", nil)
			preferredStyle:UIAlertControllerStyleAlert];

		[alert addAction:[UIAlertAction
			actionWithTitle:NSLocalizedString(@"Cancel", nil)
			style:UIAlertActionStyleCancel
			handler:nil]];

		__weak typeof(self) wSelf = self;
		[alert addAction:[UIAlertAction
			actionWithTitle:NSLocalizedString(@"Ok", nil)
			style:UIAlertActionStyleDestructive
			handler:^(UIAlertAction* _Nonnull action)
		{
			wSelf.resultImageIdentifiers = nil;
			[wSelf.captureScenario.result clearWithError:nil];

			if(wSelf.currentScreenState == StartScreenStateWithDocumentsWithConnection) {
				wSelf.currentScreenState = StartScreenStateWithoutDocumentsWithConnection;
			} else if(wSelf.currentScreenState == StartScreenStateWithDocumentsWithoutConnection) {
				wSelf.currentScreenState = StartScreenStateStart;
			}
		}]];

		[self presentViewController:alert animated:YES completion:nil];
	}
}

- (IBAction)onActionButtonClicked:(id)sender
{
	NSUserDefaults* userDefaults = NSUserDefaults.standardUserDefaults;
	if(!userDefaults.authorized) {
		[self showSettings];
	} else {
		[self sendFiles];
	}
}

#pragma mark - utilities

- (void)orientationChanged
{
	if(self.currentScreenState == StartScreenStateStart
		|| self.currentScreenState == StartScreenStateWithDocumentsWithoutConnection)
	{
		[self hideProjectBarView];
	}
}

- (void)clearState
{
	NSUserDefaults* userDefaults = NSUserDefaults.standardUserDefaults;
	if(userDefaults.currentDocumensAreSuccessfullyExported) {
		self.currentScreenState = StartScreenStateSuccessfullyExported;
	} else if(self.resultImageIdentifiers.count > 0) {
		if(userDefaults.authorized) {
			self.currentScreenState = StartScreenStateWithDocumentsWithConnection;
		} else {
			self.currentScreenState = StartScreenStateWithDocumentsWithoutConnection;
		}
	} else {
		if(userDefaults.authorized) {
			self.currentScreenState = StartScreenStateWithoutDocumentsWithConnection;
		} else {
			self.currentScreenState = StartScreenStateStart;
		}
	}
}

- (void)setCurrentScreenState:(StartScreenState)currentScreenState
{
	_currentScreenState = currentScreenState;

	switch(self.currentScreenState) {
		case StartScreenStateStart:
			[self startState];
			break;
		case StartScreenStateWithDocumentsWithoutConnection:
			[self withDocumentsWithoutConnection];
			break;
		case StartScreenStateWithoutDocumentsWithConnection:
			[self withoutDocumentsWithConnection];
			break;
		case StartScreenStateWithDocumentsWithConnection:
			[self withDocumentsWithConnection];
			break;
		case StartScreenStateExportInProgress:
			[self exportInProgress];
			break;
		case StartScreenStateSuccessfullyExported:
			[self successfullyExported];
			break;
		default:
			NSAssert(NO, @"Unexpected");
			break;
	}
}

- (void)clearResults
{
	if(self.resultImageIdentifiers != nil) {
		self.resultImageIdentifiers = nil;
		[self.captureScenario.result clearWithError:nil];

		NSUserDefaults* userDefaults = NSUserDefaults.standardUserDefaults;
		userDefaults.currentDocumensAreSuccessfullyExported = NO;
	}
}

- (void)showError:(NSError*)error withCompletion:(nullable void (^)(void))completion
{
	__block NSError* theError = error;
	dispatch_async(dispatch_get_main_queue(), ^{
		if(error == nil) {
			NSDictionary* userInfo = @{NSLocalizedDescriptionKey : NSLocalizedString(@"UnexpectedErrorOccurred", nil)};
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
		[self.navigationController presentViewController:alert animated:YES completion:nil];
	});
}

#pragma mark - network

- (void)sendFiles
{
	[self sendFilesWithPassword:nil];
}

- (void)sendFilesWithPassword:(NSString*)password
{
	NSUserDefaults* userDefaults = NSUserDefaults.standardUserDefaults;
	if(!userDefaults.authorized) {
		[self showError:nil withCompletion:nil];
		return;
	}

	[self cancelSendingFilesRequest];
	self.currentScreenState = StartScreenStateExportInProgress;

	__weak typeof(self) wSelf = self;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		typeof(wSelf) sSelf = wSelf;
		NSString* tmpDir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
		tmpDir = [tmpDir stringByAppendingPathComponent:@"tmp"];

		// clear tmp directory (delete if exists and create again)
		NSFileManager* fileManager = [NSFileManager defaultManager];
		if([fileManager fileExistsAtPath:tmpDir isDirectory:nil]) {
			[[NSFileManager defaultManager] removeItemAtPath:tmpDir error:nil];
		}
		if(![fileManager createDirectoryAtPath:tmpDir withIntermediateDirectories:YES attributes:nil error:NULL]) {
			[sSelf showError:nil withCompletion:nil];
			return;
		}

		// save all images to files
		NSError* error = nil;
		NSMutableArray* fileNames = [NSMutableArray arrayWithCapacity:sSelf.resultImageIdentifiers.count];
		NSInteger fileNumber = 0;
		for(NSString* page in sSelf.resultImageIdentifiers) {
			UIImage* img = [sSelf.captureScenario.result loadImageWithId:page error:&error];
			if(img == nil) {
				[sSelf showError:error withCompletion:nil];
				[[NSFileManager defaultManager] removeItemAtPath:tmpDir error:nil];
				return;
			}

			NSString* filename = [NSString stringWithFormat:@"file_%03ld.jpg", fileNumber];
			NSString* filepath = [tmpDir stringByAppendingPathComponent:filename];

			RTRFileOutputStream* exportOptions = [[RTRFileOutputStream alloc] initWithFilePath:filepath];
			id<RTRCoreAPIExportToJpgOperation> op = [[RecognizerEngine coreAPIWithError:&error] createExportToJpgOperation:exportOptions];
			if(op == nil) {
				[sSelf showError:error withCompletion:nil];
				return;
			}
			op.compression = RTRCoreAPIExportCompressionLowLevel;

			[op addPageWithImage:img];
			[op close];

			[fileNames addObject:filepath];

			fileNumber++;
		}

		void (^success)(NSString*) = ^(NSString* authTicket) {
			dispatch_async(dispatch_get_main_queue(), ^{
				wSelf.currentScreenState = StartScreenStateSuccessfullyExported;
				[wSelf projectBarStyleExportSuccessful];
			});
			NSUserDefaults* userDefaults = NSUserDefaults.standardUserDefaults;
			userDefaults.authTicket = authTicket;
			userDefaults.currentDocumensAreSuccessfullyExported = YES;
		};
		void (^fail)(NSError*) = ^(NSError* error) {
			dispatch_async(dispatch_get_main_queue(), ^{
				if(error.code == 401) {
					// 401 - unauthorized
					// try to ask password and send files again
					[wSelf projectBarStyleExportWarning];
					[wSelf askPasswordAndSendFiles];
				} else {
					[wSelf clearState];
					if(error.code != NSURLErrorCancelled) {
						[wSelf projectBarStyleExportFailed];
						[wSelf showError:error withCompletion:nil];
					}
				}
			});
		};

		if(password.length == 0) {
			[FlexiCaptureClient sendFiles:fileNames withProject:userDefaults.projectName withUrl:userDefaults.url tenant:userDefaults.tenant authTicket:userDefaults.authTicket success:success fail:fail];
		} else {
			[FlexiCaptureClient sendFiles:fileNames withProject:userDefaults.projectName withUrl:userDefaults.url tenant:userDefaults.tenant username:userDefaults.username password:password success:success fail:fail];
		}

		// remove files because [FlexiCaptureClient sendFiles] guarantees sending request before return
		[[NSFileManager defaultManager] removeItemAtPath:tmpDir error:nil];
	});
}

- (void)askPasswordAndSendFiles
{
	__weak typeof(self) wSelf = self;
	UIAlertController* alertController = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"LogIn", nil) message:NSLocalizedString(@"EnterPasswordToExportPages", nil) preferredStyle:UIAlertControllerStyleAlert];
	[alertController addTextFieldWithConfigurationHandler:^(UITextField* textField) {
		textField.placeholder = @"password";
		textField.secureTextEntry = YES;
	}];
	[alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
		[wSelf clearState];
		[wSelf projectBarStyleExportWarning];
	}]];
	[alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Done", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
		UITextField* passwordTextField = alertController.textFields[0];
		[wSelf sendFilesWithPassword:passwordTextField.text];
	}]];
	[self presentViewController:alertController animated:YES completion:nil];
}

- (void)cancelSendingFilesRequest
{
	[FlexiCaptureClient cancelAllRequests];
}

#pragma mark - UI states

- (void)startState
{
	self.topActionBarView.hidden = YES;
	self.actionButton.hidden = YES;
	self.pagesPlaceholder.hidden = NO;
	self.previewCollectionView.hidden = YES;
	self.scanNewDocButtonView.hidden = NO;
	self.scanNewDocMiniButtonView.hidden = YES;

	[self hideProjectBarView];

	self.pagesFadeEffectView.hidden = YES;
}

- (void)withDocumentsWithoutConnection
{
	self.topActionBarView.hidden = NO;
	self.actionButton.hidden = NO;
	[self.actionButton setTitle:NSLocalizedString(@"LogIn", nil) forState:UIControlStateNormal];
	self.pagesPlaceholder.hidden = YES;
	self.previewCollectionView.hidden = NO;
	self.scanNewDocButtonView.hidden = YES;
	self.scanNewDocMiniButtonView.hidden = NO;

	self.pagesCountLabel.text = [NSString stringWithFormat:NSLocalizedString(@"PagesCount", nil), self.resultImageIdentifiers.count];

	[self.previewCollectionView reloadData];

	[self hideProjectBarView];
	self.actionButton.enabled = YES;

	self.previewCollectionView.userInteractionEnabled = YES;
	self.pagesFadeEffectView.hidden = YES;
}

- (void)withoutDocumentsWithConnection
{
	NSUserDefaults* userDefaults = NSUserDefaults.standardUserDefaults;
	self.currentProjectLabel.text = userDefaults.projectName;

	self.topActionBarView.hidden = YES;
	self.actionButton.hidden = YES;
	self.pagesPlaceholder.hidden = NO;
	self.previewCollectionView.hidden = YES;
	self.scanNewDocButtonView.hidden = NO;
	self.scanNewDocMiniButtonView.hidden = YES;

	[self showProjectBarView];
	[self projectBarStyleNone];

	self.pagesFadeEffectView.hidden = YES;
}

- (void)withDocumentsWithConnection
{
	NSUserDefaults* userDefaults = NSUserDefaults.standardUserDefaults;
	self.currentProjectLabel.text = userDefaults.projectName;

	self.topActionBarView.hidden = NO;
	self.actionButton.hidden = NO;
	[self.actionButton setTitle:NSLocalizedString(@"Export", nil) forState:UIControlStateNormal];
	self.pagesPlaceholder.hidden = YES;
	self.previewCollectionView.hidden = NO;
	self.scanNewDocButtonView.hidden = YES;
	self.scanNewDocMiniButtonView.hidden = NO;

	self.pagesCountLabel.text = [NSString stringWithFormat:NSLocalizedString(@"PagesCount", nil), self.resultImageIdentifiers.count];

	[self.previewCollectionView reloadData];

	[self showProjectBarView];
	[self projectBarStyleNone];

	self.previewCollectionView.userInteractionEnabled = YES;
	self.pagesFadeEffectView.hidden = YES;
}

- (void)exportInProgress
{
	NSUserDefaults* userDefaults = NSUserDefaults.standardUserDefaults;
	self.currentProjectLabel.text = userDefaults.projectName;

	self.topActionBarView.hidden = NO;
	self.actionButton.hidden = NO;
	[self.actionButton setTitle:NSLocalizedString(@"Export", nil) forState:UIControlStateNormal];
	self.pagesPlaceholder.hidden = YES;
	self.previewCollectionView.hidden = NO;
	self.scanNewDocButtonView.hidden = YES;
	self.scanNewDocMiniButtonView.hidden = YES;

	self.pagesCountLabel.text = [NSString stringWithFormat:NSLocalizedString(@"PagesCount", nil), self.resultImageIdentifiers.count];

	[self showProjectBarView];
	[self projectBarStyleExportInProgress];

	self.previewCollectionView.userInteractionEnabled = NO;
	self.pagesFadeEffectView.hidden = NO;
}

- (void)successfullyExported
{
	self.topActionBarView.hidden = NO;
	self.actionButton.hidden = NO;
	self.pagesPlaceholder.hidden = YES;
	self.previewCollectionView.hidden = NO;
	self.scanNewDocButtonView.hidden = NO;
	self.scanNewDocMiniButtonView.hidden = YES;

	self.pagesCountLabel.text = [NSString stringWithFormat:NSLocalizedString(@"PagesCount", nil), self.resultImageIdentifiers.count];

	NSUserDefaults* userDefaults = NSUserDefaults.standardUserDefaults;
	if(userDefaults.authorized) {
		self.currentProjectLabel.text = userDefaults.projectName;
		[self showProjectBarView];
		[self.actionButton setTitle:NSLocalizedString(@"Export", nil) forState:UIControlStateNormal];
		[self projectBarStyleExportSuccessful];
	} else {
		[self hideProjectBarView];
		[self.actionButton setTitle:NSLocalizedString(@"LogIn", nil) forState:UIControlStateNormal];
		self.actionButton.enabled = YES;
	}

	self.previewCollectionView.userInteractionEnabled = NO;
	self.pagesFadeEffectView.hidden = NO;
}

#pragma mark - project bar

- (void)hideProjectBarView
{
	self.projectBarView.hidden = YES;
	if(self.traitCollection.verticalSizeClass != UIUserInterfaceSizeClassRegular
		|| self.traitCollection.horizontalSizeClass != UIUserInterfaceSizeClassRegular)
	{
		// not on iPad
		self.separatorTopSpaceConstraint.constant = 16;
		[self.view setNeedsLayout];
	}
}

- (void)showProjectBarView
{
	self.projectBarView.hidden = NO;
	if(self.traitCollection.verticalSizeClass != UIUserInterfaceSizeClassRegular
		|| self.traitCollection.horizontalSizeClass != UIUserInterfaceSizeClassRegular)
	{
		// not on iPad
		self.separatorTopSpaceConstraint.constant = 60;
		[self.view setNeedsLayout];
	}
}

- (void)hideChainIconOnIPad
{
	if(self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassRegular
		&& self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular)
	{
		self.chainIconImageView.hidden = YES;
	}
}

- (void)projectBarStyleNone
{
	self.exportStatusImageView.hidden = YES;
	self.exportInProgressIndicator.hidden = YES;
	self.actionButton.enabled = YES;
	self.deleteButton.enabled = YES;
	self.chainIconImageView.hidden = NO;
}

- (void)projectBarStyleExportInProgress
{
	self.exportStatusImageView.hidden = YES;
	self.exportInProgressIndicator.hidden = NO;
	self.actionButton.enabled = NO;
	[self hideChainIconOnIPad];
	self.deleteButton.enabled = NO;
}

- (void)projectBarStyleExportSuccessful
{
	self.exportStatusImageView.hidden = NO;
	self.exportInProgressIndicator.hidden = YES;
	self.actionButton.enabled = NO;
	self.deleteButton.enabled = YES;

	[self hideChainIconOnIPad];
	self.exportStatusImageView.image = [UIImage imageNamed:@"success"];
}

- (void)projectBarStyleExportFailed
{
	self.exportStatusImageView.hidden = NO;
	self.exportInProgressIndicator.hidden = YES;
	self.actionButton.enabled = YES;
	self.deleteButton.enabled = YES;

	[self hideChainIconOnIPad];
	self.exportStatusImageView.image = [UIImage imageNamed:@"error"];
}

- (void)projectBarStyleExportWarning
{
	self.exportStatusImageView.hidden = NO;
	self.exportInProgressIndicator.hidden = YES;
	self.actionButton.enabled = YES;
	self.deleteButton.enabled = YES;

	[self hideChainIconOnIPad];
	self.exportStatusImageView.image = [UIImage imageNamed:@"warning"];
}

#pragma mark - navigation

- (void)showCameraWithPageId:(AUIPageId)pageId
{
	[self cancelSendingFilesRequest];

	AUICaptureController* captureController = [AUICaptureController new];
	captureController.captureScenario = self.captureScenario;
	self.captureScenario.active = YES;
	self.captureScenario.startAsEditorAtPageId = pageId;
	captureController.theme = AUIThemeDark;
	captureController.flashButton.hidden = ![UIImagePickerController isFlashAvailableForCameraDevice:UIImagePickerControllerCameraDeviceRear];
	captureController.modalPresentationStyle = UIModalPresentationFullScreen;
	__weak typeof(self) wSelf = self;
	[self presentViewController:captureController animated:YES completion:^{
		[wSelf clearState];
	}];
}

- (void)showSettings
{
	[self cancelSendingFilesRequest];

	UIStoryboard* storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
	SignInViewController* vc = [storyboard instantiateViewControllerWithIdentifier:@"SignInViewController"];
	NSParameterAssert([vc isKindOfClass:SignInViewController.class]);

	[self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - collectionView

- (CGSize)collectionView:(UICollectionView*)collectionView layout:(UICollectionViewLayout*)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath*)indexPath
{
	if(self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassRegular
		&& self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular)
	{
		if(UIDeviceOrientationIsLandscape([UIDevice currentDevice].orientation)) {
			CGFloat width = [self narrowSideOfDocumentCellWithCellCount:4 margin:16];
			return CGSizeMake(width, [self wideSideOfA4ProportionForNarrowSide:width]);
		} else {
			CGFloat width = [self narrowSideOfDocumentCellWithCellCount:3 margin:16];
			return CGSizeMake(width, [self wideSideOfA4ProportionForNarrowSide:width]);
		}
	} else {
		if(UIDeviceOrientationIsLandscape([UIDevice currentDevice].orientation)) {
			CGFloat width = [self narrowSideOfDocumentCellWithCellCount:5 margin:16];
			return CGSizeMake(width, [self wideSideOfA4ProportionForNarrowSide:width]);
		} else {
			CGFloat width = [self narrowSideOfDocumentCellWithCellCount:3 margin:16];
			return CGSizeMake(width, [self wideSideOfA4ProportionForNarrowSide:width]);
		}
	}
}

- (CGFloat)narrowSideOfDocumentCellWithCellCount:(NSInteger)count margin:(CGFloat)margin
{
	CGFloat width = [UIScreen mainScreen].bounds.size.width;
	return (width - (count + 1) * margin) / count;
}

- (CGFloat)wideSideOfA4ProportionForNarrowSide:(CGFloat)narrow
{
	return 297 / 210 * narrow;
}

- (NSInteger)collectionView:(nonnull UICollectionView*)collectionView numberOfItemsInSection:(NSInteger)section
{
	return self.resultImageIdentifiers.count;
}

- (nonnull __kindof UICollectionViewCell*)collectionView:(nonnull UICollectionView*)collectionView cellForItemAtIndexPath:(nonnull NSIndexPath*)indexPath
{
	CollectionViewCell* cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"CollectionViewCell" forIndexPath:indexPath];
	NSParameterAssert([cell isKindOfClass:CollectionViewCell.class]);

	return cell;
}

- (void)collectionView:(UICollectionView*)collectionView willDisplayCell:(CollectionViewCell*)cell forItemAtIndexPath:(NSIndexPath*)indexPath
{
	// Asynchronous loading image thumbnails.
	NSString* identifier = self.resultImageIdentifiers[indexPath.row];
	__weak typeof(self) wSelf = self;
	__weak typeof(cell) wCell = cell;
	__block void (^thumbnailLoader)(void) = ^{
		NSError* error;
		UIImage* thumbnail = [wSelf.captureScenario.result loadThumbnailWithId:identifier error:&error];
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

- (void)collectionView:(UICollectionView*)collectionView didSelectItemAtIndexPath:(NSIndexPath*)indexPath
{
	[self showCameraWithPageId:self.resultImageIdentifiers[indexPath.row]];
}


#pragma mark - Abbyy Mobile UI

- (AUIMultiPageImageCaptureScenario*)captureScenario
{
	if(_captureScenario == nil) {
		NSError* error = nil;
		RTREngine* rtrEngine = [RecognizerEngine rtrEngineWithError:&error];
		if(rtrEngine == nil) {
			[self showError:error withCompletion:nil];
			return nil;
		}

		_captureScenario = [[AUIMultiPageImageCaptureScenario alloc]
			initWithEngine:rtrEngine
			storagePath:NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject
			error:&error];

		if(_captureScenario == nil) {
			[self showError:error withCompletion:nil];
			return nil;
		}

		_captureScenario.delegate = self;
	}

	return _captureScenario;
}

- (void)captureScenario:(AUIImageCaptureScenario*)scenario didFailWithError:(nonnull NSError*)error result:(nonnull id<AUIMultiPageImageCaptureResult>)result
{
	[self showError:error withCompletion:^{
		[self dismissViewControllerAnimated:YES completion:nil];
	}];
}

- (void)captureScenario:(nonnull AUIMultiPageImageCaptureScenario*)captureScenario didFinishWithResult:(nonnull id<AUIMultiPageImageCaptureResult>)result
{
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)captureScenario:(nonnull AUIMultiPageImageCaptureScenario*)captureScenario onCloseWithResult:(nonnull AUICaptureController*)captureController
{
	[self dismissViewControllerAnimated:YES completion:nil];
}

@end
