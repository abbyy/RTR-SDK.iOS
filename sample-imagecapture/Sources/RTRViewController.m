/// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
/// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

#import "RTRViewController.h"

#import <AVFoundation/AVFoundation.h>
#import <AbbyyRtrSDK/AbbyyRtrSDK.h>

#import "RTRDrawResultsView.h"

/// Info about a document to be captured.
@interface RTRCapturedDocument : NSObject

/// Display name.
@property (nonatomic, copy) NSString* name;
/// Physical size, mm.
@property (nonatomic, assign) CGSize size;
/// Minimum aspect ratio of a capturing document.
@property (nonatomic, assign) CGFloat minAspectRatio;
/// Description.
@property (nonatomic, copy) NSString* documentDescription;
/// Are boundaries required, wait while a boundaries will be found.
@property (nonatomic, assign, readonly) BOOL areBoundariesRequired;
/// If size is known we can specify it in crop operation.
@property (nonatomic, assign, readonly) BOOL isDocumentSizeKnown;

@end

@implementation RTRCapturedDocument

- (BOOL)areBoundariesRequired
{
	return self.minAspectRatio != 0.f || !CGSizeEqualToSize(self.size, CGSizeZero);
}

- (BOOL)isDocumentSizeKnown
{
	return !CGSizeEqualToSize(self.size, CGSizeZero);
}

@end

#pragma mark -

@interface RTRViewController () <AVCaptureVideoDataOutputSampleBufferDelegate,
	RTRImageCaptureServiceDelegate, UITableViewDelegate, UITableViewDataSource>

/// Settings table.
@property (nonatomic, weak) IBOutlet UITableView* tableView;
/// Button for show / hide table with settings.
@property (nonatomic, weak) IBOutlet UIBarButtonItem* showSettingsButton;

/// View with camera preview layer.
@property (nonatomic, weak) IBOutlet UIView* previewView;
/// Stop/Start capture button
@property (nonatomic, weak) IBOutlet UIButton* captureButton;

/// View for displaying current capture status.
@property (nonatomic, weak) IBOutlet RTRDrawResultsView* overlayView;
/// Black view for highlight captured results.
@property (nonatomic, weak) IBOutlet UIView* blackBackgroundView;
/// View with selected document description.
@property (nonatomic, weak) IBOutlet UILabel* descriptionLabel;

/// Label for error or warning info.
@property (nonatomic, weak) IBOutlet UILabel* infoLabel;

/// Image captured from video stream.
@property (nonatomic, weak) IBOutlet UIImageView* capturedImageView;

/// Is service running.
@property (atomic, assign, getter=isRunning) BOOL running;

/// External information about a document to be captured.
@property (nonatomic, strong) RTRCapturedDocument* selectedDocument;

/// Image size.
@property (atomic, assign) CGSize imageBufferSize;

@end

#pragma mark -

@implementation RTRViewController {
	/// Camera session.
	AVCaptureSession* _session;
	/// Video preview layer.
	AVCaptureVideoPreviewLayer* _previewLayer;
	/// Session Preset.
	NSString* _sessionPreset;

	/// Engine for AbbyyRtrSDK.
	RTREngine* _engine;
	/// Service for runtime image capturing.
	id<RTRImageCaptureService> _imageCaptureService;

	/// Area of interest in view coordinates.
	CGRect _selectedArea;
}

#pragma mark - UIView LifeCycle

- (void)viewDidLoad
{
	[super viewDidLoad];
	// Recommended session preset.
	_sessionPreset = AVCaptureSessionPreset1920x1080;
	_imageBufferSize = CGSizeMake(1080.f, 1920.f);
	if(UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation)) {
		_imageBufferSize = CGSizeMake(_imageBufferSize.height, _imageBufferSize.width);
	}
	self.overlayView.imageBufferSize = _imageBufferSize;
	self.selectedDocument = [self documentPresets].firstObject;

	self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];

	[self prepareUIForStart];

	self.captureButton.selected = NO;
	[self.captureButton setTitle:@"Stop" forState:UIControlStateSelected];
	[self.captureButton setTitle:@"Start" forState:UIControlStateNormal];

	self.tableView.hidden = YES;
	[self.showSettingsButton setTitle:[self settingsButtonTitle]];
	self.descriptionLabel.text = self.selectedDocument.documentDescription;
	__weak typeof(self) weakSelf = self;
	void (^completion)(BOOL) = ^(BOOL accessGranted) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[weakSelf configureCompletionAccessGranted:accessGranted];
		});
	};

	AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
	switch(status) {
		case AVAuthorizationStatusAuthorized:
			completion(YES);
			break;

		case AVAuthorizationStatusNotDetermined:
		{
			[AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
				completion(granted);
			}];
			break;
		}

		case AVAuthorizationStatusRestricted:
		case AVAuthorizationStatusDenied:
			completion(NO);
			break;

		default:
			break;
	}
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
	[super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];

	BOOL wasRunning = self.isRunning;
	self.running = NO;
	[_imageCaptureService stopTasks];
	[self.overlayView clear];

	__weak typeof(self) weakSelf = self;
	[coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context)
		{
			CGSize oldSize = weakSelf.imageBufferSize;
			CGSize newSize = CGSizeMake(MIN(oldSize.width, oldSize.height), MAX(oldSize.width, oldSize.height));
			if(UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation)) {
				newSize = CGSizeMake(newSize.height, newSize.width);
			}
			weakSelf.imageBufferSize = newSize;
			weakSelf.running = wasRunning;
			weakSelf.overlayView.imageBufferSize = newSize;
		}];
}

- (void)configureCompletionAccessGranted:(BOOL)accessGranted
{
	if(![UIImagePickerController isCameraDeviceAvailable:UIImagePickerControllerCameraDeviceRear]) {
		self.captureButton.enabled = NO;
		[self updateLogMessage:@"Device has no camera"];
		return;
	}

	if(!accessGranted) {
		self.captureButton.enabled = NO;
		[self updateLogMessage:@"Camera access denied"];
		return;
	}

	NSString* licensePath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"license"];
	_engine = [RTREngine sharedEngineWithLicenseData:[NSData dataWithContentsOfFile:licensePath]];
	if(_engine == nil) {
		self.captureButton.enabled = NO;
		[self updateLogMessage:@"Invalid License"];
		return;
	}

	self.showSettingsButton.enabled = YES;
	_imageCaptureService = [_engine createImageCaptureServiceWithDelegate:self];
	[_imageCaptureService setDocumentSize:self.selectedDocument.size];
	[_imageCaptureService setAspectRatioMin:self.selectedDocument.minAspectRatio];

	[self configureAVCaptureSession];
	[self configurePreviewLayer];
	[_session startRunning];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(avSessionFailed:)
		name:AVCaptureSessionRuntimeErrorNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidEnterBackground)
		name:UIApplicationDidEnterBackgroundNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillEnterForeground)
		name:UIApplicationWillEnterForegroundNotification object:nil];

	[self capturePressed];
}

- (void)viewWillDisappear:(BOOL)animated
{
	[_session stopRunning];
	self.running = NO;
	self.captureButton.selected = NO;
	[_imageCaptureService stopTasks];

	[super viewWillDisappear:animated];
}

- (BOOL)prefersStatusBarHidden
{
	return YES;
}

- (void)viewDidLayoutSubviews
{
	[super viewDidLayoutSubviews];

	[self updatePreviewLayerFrame];
}

- (void)updatePreviewLayerFrame
{
	UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
	[_previewLayer.connection setVideoOrientation:[self videoOrientationFromInterfaceOrientation:orientation]];

	CGRect viewBounds = self.view.bounds;

	_previewLayer.frame = viewBounds;
}

- (void)setSelectedArea:(CGRect)selectedArea
{
	_selectedArea = selectedArea;
	_overlayView.imageBufferSize = _imageBufferSize;
}

- (AVCaptureVideoOrientation)videoOrientationFromInterfaceOrientation:(UIInterfaceOrientation)orientation
{
	AVCaptureVideoOrientation result = AVCaptureVideoOrientationPortrait;
	switch(orientation) {
		case UIInterfaceOrientationPortrait:
			result = AVCaptureVideoOrientationPortrait;
			break;
		case UIInterfaceOrientationPortraitUpsideDown:
			result = AVCaptureVideoOrientationPortraitUpsideDown;
			break;
		case UIInterfaceOrientationLandscapeLeft:
			result = AVCaptureVideoOrientationLandscapeLeft;
			break;
		case UIInterfaceOrientationLandscapeRight:
			result = AVCaptureVideoOrientationLandscapeRight;
			break;
		default:
			break;
	}

	return result;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Notifications

- (void)applicationDidEnterBackground
{
	[_session stopRunning];
	[_imageCaptureService stopTasks];
}

- (void)applicationWillEnterForeground
{
	[_session startRunning];
}

#pragma mark - Actions

- (IBAction)capturePressed
{
	if(!self.captureButton.enabled) {
		return;
	}

	self.captureButton.selected = !self.captureButton.selected;
	self.running = self.captureButton.selected;

	if(self.isRunning) {
		[_imageCaptureService setDocumentSize:self.selectedDocument.size];
		[_imageCaptureService setAspectRatioMin:self.selectedDocument.minAspectRatio];
		[self prepareUIForStart];
	} else {
		[_imageCaptureService stopTasks];
	}
}

- (void)prepareUIForStart
{
	[self.overlayView clear];
	self.overlayView.hidden = NO;

	self.blackBackgroundView.hidden = YES;
	self.capturedImageView.hidden = YES;
	self.infoLabel.text = @"";
}

- (IBAction)onSettingsButtonPressed
{
	[self changeSettingsTableVisibilty];
}

- (void)changeSettingsTableVisibilty
{
	if(self.tableView.hidden) {
		self.running = NO;
		self.captureButton.selected = NO;
		[self.tableView reloadData];
		[self showSettingsTable:YES];

	} else {
		[self capturePressed];
		[self showSettingsTable:NO];
		[self.showSettingsButton setTitle:[self settingsButtonTitle]];
		self.descriptionLabel.text = self.selectedDocument.documentDescription;
	}
}

#pragma mark - AVCapture configuration

- (void)configureAVCaptureSession
{
	NSError* error = nil;
	_session = [[AVCaptureSession alloc] init];
	[_session setSessionPreset:_sessionPreset];

	AVCaptureDevice* device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
	AVCaptureDeviceInput* input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
	if(error != nil) {
		NSLog(@"%@", [error localizedDescription]);
	}
	NSAssert([_session canAddInput:input], @"impossible to add AVCaptureDeviceInput");
	[_session addInput:input];

	AVCaptureInputPort* port = input.ports.firstObject;
	CMFormatDescriptionRef formatDescription = port.formatDescription;
	if(formatDescription != nil) {
		CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);
		_imageBufferSize = CGSizeMake(dimensions.width, dimensions.height);
		self.overlayView.imageBufferSize = _imageBufferSize;
	}

	AVCaptureVideoDataOutput* videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
	dispatch_queue_t videoDataOutputQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	[videoDataOutput setSampleBufferDelegate:self queue:videoDataOutputQueue];
	[videoDataOutput alwaysDiscardsLateVideoFrames];
	videoDataOutput.videoSettings = @{
		(id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
	};
	NSAssert([_session canAddOutput:videoDataOutput], @"impossible to add AVCaptureVideoDataOutput");
	[_session addOutput:videoDataOutput];

	[[videoDataOutput connectionWithMediaType:AVMediaTypeVideo] setEnabled:YES];
	AVCaptureVideoOrientation videoOrientation = [self videoOrientationFromInterfaceOrientation:
		[UIApplication sharedApplication].statusBarOrientation];
	[[videoDataOutput connectionWithMediaType:AVMediaTypeVideo] setVideoOrientation:videoOrientation];

	BOOL locked = [device lockForConfiguration:nil];
	if(locked) {
		if([device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
			[device setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
		}

		if([device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
			[device setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
		}

		[device unlockForConfiguration];
	}
}

- (void)configurePreviewLayer
{
	_previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:_session];
	_previewLayer.backgroundColor = [[UIColor blackColor] CGColor];
	_previewLayer.videoGravity = AVLayerVideoGravityResize;
	CALayer* rootLayer = [self.previewView layer];
	[rootLayer insertSublayer:_previewLayer atIndex:0];

	[self updatePreviewLayerFrame];
}

- (void)avSessionFailed:(NSNotification*)notification
{
	dispatch_async(dispatch_get_main_queue(), ^{
		self.infoLabel.text = [NSString stringWithFormat:@"AVSession Failed. %@", notification.userInfo[AVCaptureSessionErrorKey]];
	});
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput*)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
	fromConnection:(AVCaptureConnection*)connection
{
	if(!self.isRunning) {
		return;
	}

	__block BOOL invalidFrameOrientation = NO;
	dispatch_sync(dispatch_get_main_queue(), ^{
		AVCaptureVideoOrientation videoOrientation = [self videoOrientationFromInterfaceOrientation:
			[UIApplication sharedApplication].statusBarOrientation];
		if(connection.videoOrientation != videoOrientation) {
			[connection setVideoOrientation:videoOrientation];
			invalidFrameOrientation = YES;
		}
	});

	if(invalidFrameOrientation) {
		return;
	}

	[_imageCaptureService addSampleBuffer:sampleBuffer];
}

#pragma mark -

- (NSString*)settingsButtonTitle
{
	return self.selectedDocument.name;
}

#pragma mark -

- (void)updateLogMessage:(NSString*)message
{
	self.infoLabel.text = message;
}

#pragma mark - RTRImageCaptureServiceDelegate

- (void)onBufferProcessedWithStatus:(RTRImageCaptureStatus*)status result:(RTRImageCaptureResult*)result
{
	UIImage* capturedImage = result.image;
	NSArray<NSValue*>* documentBoundary = result.documentBoundary;
	BOOL isReadyForCapturing = capturedImage != nil;
	if(isReadyForCapturing) {
		if(self.selectedDocument.areBoundariesRequired) {
			isReadyForCapturing = documentBoundary.count != 0;
		}
	}
	BOOL isSizeKnown = self.selectedDocument.isDocumentSizeKnown;

	if(isReadyForCapturing) {
		self.running = NO;
		self.captureButton.selected = NO;
		[_imageCaptureService stopTasks];

		[self.overlayView clear];
		self.overlayView.hidden = YES;
		self.blackBackgroundView.hidden = NO;

		RTREngine* engine = _engine;
		UIImageView* capturedImageView = self.capturedImageView;
		__weak typeof(self) weakSelf = self;

		// 'Peek' feedback
		 AudioServicesPlaySystemSound((SystemSoundID)1519);

		dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
			NSError* error;
			UIImage* resultImage;
			if(documentBoundary.count != 0) {
				id<RTRCoreAPI> coreAPI = [engine createCoreAPI];
				id<RTRCoreAPIImage> image = [coreAPI loadImage:capturedImage error:&error];
				if(image != nil) {
					id<RTRCoreAPICropOperation> cropOperation = [coreAPI createCropOperation];
					cropOperation.documentBoundary = documentBoundary;
					if(isSizeKnown) {
						cropOperation.documentSize = result.documentSize;
					}
					BOOL ok = [cropOperation applyToImage:image];
					if(ok) {
						resultImage = [image UIImage];
					} else {
						error = cropOperation.error;
					}
				}
			} else {
				resultImage = capturedImage;
			}
			dispatch_async(dispatch_get_main_queue(), ^{
				if(resultImage == nil) {
					[weakSelf onError:error];
				} else {
					capturedImageView.image = resultImage;
					capturedImageView.hidden = NO;
				}
			});
		});
	} else {
		NSArray<RTRQualityAssessmentForOCRBlock*>* blocks = status.qualityAssessmentForOCRBlocks;
		if(blocks != nil) {
			self.overlayView.documentBoundary = status.documentBoundary;
			self.overlayView.blocks = blocks;
			[self.overlayView setNeedsDisplay];
		}
	}
}

- (void)onError:(NSError*)error
{
	NSLog(@"Error: %@", error);

	if(!self.isRunning) {
		return;
	}

	[self updateLogMessage:error.localizedDescription];
	self.running = NO;
	self.captureButton.selected = NO;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
	self.selectedDocument = [self documentPresets][indexPath.row];
	[self changeSettingsTableVisibilty];

	[tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
}

#pragma mark - UITableViewDatasource

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
	return [self documentPresets].count;
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
	static NSString* const tableCellID = @"table cell id";
	UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:tableCellID];
	if(cell == nil) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:tableCellID];
	}
	RTRCapturedDocument* documentSettings = [self documentPresets][indexPath.row];
	cell.textLabel.text = documentSettings.name;
	cell.accessoryType = self.selectedDocument == documentSettings ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	cell.detailTextLabel.text = documentSettings.documentDescription;
	cell.detailTextLabel.textColor = [UIColor whiteColor];
	cell.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.4f];
	cell.textLabel.textColor = [UIColor whiteColor];
	cell.tintColor = [UIColor whiteColor];

	return cell;
}

#pragma mark - Utils

- (NSArray<RTRCapturedDocument*>*)documentPresets
{
	static NSArray* result = nil;
	if(result == nil) {
		// Unknown size but require boundaries
		RTRCapturedDocument* documentWithBoundaries = [[RTRCapturedDocument alloc] init];
		documentWithBoundaries.name = @"DocumentWithBoundaries";
		documentWithBoundaries.size = CGSizeZero;
		documentWithBoundaries.minAspectRatio = 1.f;
		documentWithBoundaries.documentDescription = @"Unknown size / Require boundaries";

		// A4 paper size for office documents (ISO)
		RTRCapturedDocument* a4 = [[RTRCapturedDocument alloc] init];
		a4.name = @"A4";
		a4.size = CGSizeMake(210, 297);
		a4.documentDescription = @"210×297 mm (ISO A4)";

		// Letter paper size for office documents (US Letter)
		RTRCapturedDocument* letter = [[RTRCapturedDocument alloc] init];
		letter.name = @"Letter";
		letter.size = CGSizeMake(215.9, 279.4);
		letter.documentDescription = @"215.9×279.4 mm (US Letter)";

		// International Business Card
		RTRCapturedDocument* businessCard = [[RTRCapturedDocument alloc] init];
		businessCard.name = @"BusinessCard";
		businessCard.size = CGSizeMake(53.98, 85.6);
		businessCard.documentDescription = @"53.98×85.6 mm (International)";

		// Unknown size / Optional boundaries
		RTRCapturedDocument* any = [[RTRCapturedDocument alloc] init];
		any.name = @"Auto";
		any.size = CGSizeZero;
		any.documentDescription = @"Unknown size / Optional boundaries";

		result = @[documentWithBoundaries, a4, letter, businessCard, any];
	}
	return result;
}

- (void)showSettingsTable:(BOOL)show
{
	self.tableView.hidden = !show;
	self.descriptionLabel.hidden = show;
	[self updateLogMessage:nil];
}

@end
