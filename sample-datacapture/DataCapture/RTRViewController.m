// ABBYY® Real-Time Recognition SDK 1 © 2016 ABBYY Production LLC.
// ABBYY is either a registered trademark or a trademark of ABBYY Software Ltd.

#import "RTRViewController.h"

#import <AVFoundation/AVFoundation.h>
#import <AbbyyRtrSDK/AbbyyRtrSDK.h>

#import "RTRSelectedAreaView.h"
#import "RTRProgressView.h"

/// Cell ID for languagesTableView.
static NSString* const RTRTableCellID = @"RTRTableCellID";
/// Name for text region layers.
static NSString* const RTRTextRegionLayerName = @"RTRTextRegionLayerName";

@interface RTRViewController () <AVCaptureVideoDataOutputSampleBufferDelegate,
	RTRDataCaptureServiceDelegate, UITableViewDelegate, UITableViewDataSource>

/// Table with settings.
@property (nonatomic, weak) IBOutlet UITableView* settingsTableView;
/// Button to show / hide table with settings.
@property (nonatomic, weak) IBOutlet UIBarButtonItem* showSettingsButton;

/// View with camera preview layer.
@property (nonatomic, weak) IBOutlet UIView* previewView;
/// Stop / Start capture button
@property (nonatomic, weak) IBOutlet UIButton* captureButton;

/// View for displaying current area of interest.
@property (nonatomic, weak) IBOutlet RTRSelectedAreaView* overlayView;
/// White view to highlight recognition results.
@property (nonatomic, weak) IBOutlet UIView* whiteBackgroundView;
/// Label for current scenario description.
@property (nonatomic, weak) IBOutlet UILabel* descriptionLabel;
/// Label for error or warning info.
@property (nonatomic, weak) IBOutlet UILabel* infoLabel;
/// Progress indicator view.
@property (nonatomic, weak) IBOutlet RTRProgressView* progressIndicatorView;

@end

#pragma mark -

@implementation RTRViewController {
	/// Camera session.
	AVCaptureSession* _session;
	/// Video preview layer.
	AVCaptureVideoPreviewLayer* _previewLayer;
	/// Session Preset.
	NSString* _sessionPreset;
	/// Image size.
	CGSize _imageBufferSize;

	/// Engine for AbbyyRtrSDK.
	RTREngine* _engine;
	/// Service for runtime recognition.
	id<RTRDataCaptureService> _dataCaptureService;

	/// Selected data capture scenario.
	NSDictionary* _selectedScenario;
	/// Simple data capture scenarios with regular expressions.
	NSArray* _dataCaptureScenarioSamples;

	/// Area of interest in view coordinates.
	CGRect _selectedArea;
}

/// Shortcut. Perform block asynchronously on main thread.
static void performBlockOnMainThread(NSInteger delay, void(^block)())
{
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

#pragma mark - Keys for scenario settings

static NSString* const RTRScenarioKey = @"RTRScenarioKey";
static NSString* const RTRDescriptionKey = @"RTRDescriptionKey";
static NSString* const RTRRegExKey = @"RTRRegExKey";
static NSString* const RTRLanguageKey = @"RTRLanguageKey";

#pragma mark - UIView LifeCycle

- (void)viewDidLoad
{
	[super viewDidLoad];

	// Recommended session preset.
	_sessionPreset = AVCaptureSessionPreset1280x720;
	_imageBufferSize = CGSizeMake(720.f, 1280.f);

	_dataCaptureScenarioSamples = @[
		// Number. A group of at least 2 digits (12, 345, 6789, 071570184356).
		@{
			RTRScenarioKey : @"Number",
			RTRDescriptionKey : @"Integer number:  12  345  6789",
			RTRRegExKey : @"[0-9]{2,}",
			RTRLanguageKey : @"English"
		},

		// Code. A group of digits mixed with letters of mixed capitalization.
		// Requires at least one digit and at least one letter (X6YZ64, 32VPA, zyy777, 67xR5dYz).
		@{
			RTRScenarioKey : @"Code",
			RTRDescriptionKey : @"Mix of digits with letters:  X6YZ64  32VPA  zyy777",
			RTRRegExKey : @"([a-zA-Z]+[0-9]+|[0-9]+[a-zA-Z]+)[0-9a-zA-Z]*",
			RTRLanguageKey : @"English"
		},

		// PartID. Groups of digits and capital letters separated by dots or hyphens
		// (002A-X345-D3-BBCD, AZ-553453-A34RRR.B, 003551.126663.AX).
		@{
			RTRScenarioKey : @"PartID",
			RTRDescriptionKey : @"Part or product id:  002A-X345-D3-BBCD  AZ-5-A34.B  001.123.AX",
			RTRRegExKey : @"[0-9a-zA-Z]+((\\.|-)[0-9a-zA-Z]+)+",
			RTRLanguageKey : @"English"
		},

		// Area Code. A group of digits in round brackets (01), (23), (4567), (1349857157).
		@{
			RTRScenarioKey : @"AreaCode",
			RTRDescriptionKey : @"Digits in round brackets as found in phone numbers:  (01)  (23)  (4567)",
			RTRRegExKey : @"\\([0-9]+\\)",
			RTRLanguageKey : @"English"
		},

		// Date. Chinese or Japanese date in traditional form (2017年1月19日, 925年12月31日, 1900年07月29日, 2008年8月8日).
		@{
			RTRScenarioKey : @"ChineseJapaneseDate",
			RTRDescriptionKey : @"2008年8月8日",
			RTRRegExKey : @"[12][0-9]{3}年\\w*((0?[1-9])|(1[0-2]))月\\w*(([01]?[0-9])|(3[01]))日",
			RTRLanguageKey : @"ChineseSimplified"
		},

#pragma mark - Some built-in data capture scenarios (the list is incomplete).

		// International Bank Account Number (DE, ES, FR, GB).
		@{
			RTRScenarioKey : @"IBAN",
			RTRDescriptionKey : @"International Bank Account Number (DE, ES, FR, GB)",
		},

		// Machine Readable Zone in identity documents. Requires MRZ.rom to be present in patterns.
		@{
			RTRScenarioKey : @"MRZ",
			RTRDescriptionKey : @"Machine Readable Zone in identity documents",
		}
	];

	_selectedScenario = _dataCaptureScenarioSamples.firstObject;

	NSString* licensePath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"AbbyyRtrSdk.license"];
	_engine = [RTREngine sharedEngineWithLicenseData:[NSData dataWithContentsOfFile:licensePath]];
	NSAssert(_engine != nil, nil);

	_dataCaptureService = [self createConfigureDataCaptureService:_selectedScenario];

	[self.settingsTableView registerClass:[UITableViewCell class] forCellReuseIdentifier:RTRTableCellID];
	self.settingsTableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];

	[self prepareUIForRecognition];

	self.captureButton.selected = NO;
	[self.captureButton setTitle:@"Stop" forState:UIControlStateSelected];
	[self.captureButton setTitle:@"Start" forState:UIControlStateNormal];

	self.settingsTableView.hidden = YES;
	[self.showSettingsButton setTitle:[self buttonTitle]];
	self.descriptionLabel.text = _selectedScenario[RTRDescriptionKey];
	__weak RTRViewController* weakSelf = self;
	void (^completion)(BOOL) = ^(BOOL accessGranted) {
		performBlockOnMainThread(0, ^{
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

/// Create and configure data capture service.
- (id<RTRDataCaptureService>)createConfigureDataCaptureService:(NSDictionary*)scenario
{
	id<RTRDataCaptureService> result;
	if([scenario[RTRRegExKey] length] == 0) {
		// No additional configuration required.
		result = [_engine createDataCaptureServiceWithDelegate:self profile:scenario[RTRScenarioKey]];

	} else {
		result = [_engine createDataCaptureServiceWithDelegate:self profile:nil];
		id<RTRDataCaptureProfileBuilder> builder = [result configureDataCaptureProfile];
		[builder setRecognitionLanguages:[NSSet setWithObject:scenario[RTRLanguageKey]]];
		[[[builder addScheme:scenario[RTRScenarioKey]] addField:scenario[RTRScenarioKey]] setRegEx:scenario[RTRRegExKey]];
		[builder checkAndApply];
	}

	return result;
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

	[self configureAVCaptureSession];
	[self configurePreviewLayer];
	[_session startRunning];

	[[NSNotificationCenter defaultCenter] addObserver:self selector: @selector(avSessionFailed:)
		name: AVCaptureSessionRuntimeErrorNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector: @selector(applicationDidEnterBackground)
		name: UIApplicationDidEnterBackgroundNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector: @selector(applicationWillEnterForeground)
		name: UIApplicationWillEnterForegroundNotification object:nil];

	[self capturePressed];
}

- (void)updateAreaOfInterest
{
	// Scale area of interest from view coordinate system to image coordinates.
	CGRect selectedRect = CGRectApplyAffineTransform(_selectedArea,
		CGAffineTransformMakeScale(_imageBufferSize.width * 1.f / CGRectGetWidth(_overlayView.frame),
		_imageBufferSize.height * 1.f / CGRectGetHeight(_overlayView.frame)));

	[_dataCaptureService setAreaOfInterest:selectedRect];
}

- (void)viewWillDisappear:(BOOL)animated
{
	[_session stopRunning];
	self.captureButton.selected = NO;
	[_dataCaptureService stopTasks];

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

	self.selectedArea = CGRectInset(viewBounds, CGRectGetWidth(viewBounds) / 8, CGRectGetHeight(viewBounds) / 3);

	[self updateAreaOfInterest];
}

- (void)setSelectedArea:(CGRect)selectedArea
{
	_selectedArea = selectedArea;
	_overlayView.selectedArea = _selectedArea;
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
	[_dataCaptureService stopTasks];
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

	if(self.captureButton.selected) {
		[self prepareUIForRecognition];

	} else {
		[_dataCaptureService stopTasks];
	}
}

- (void)prepareUIForRecognition
{
	[self clearScreenFromRegions];
	self.whiteBackgroundView.hidden = YES;
	[self.progressIndicatorView setProgress:0 color:[self progressColor:0]];
}

- (IBAction)onReconitionLanguages
{
	[self changeSettingsTableVisibilty];
}

- (void)changeSettingsTableVisibilty
{
	if(self.settingsTableView.hidden) {
		self.captureButton.selected = NO;
		[self.settingsTableView reloadData];
		[self showSettingsTable:YES];

	} else {
		_dataCaptureService = [self createConfigureDataCaptureService:_selectedScenario];
		[self capturePressed];
		[self showSettingsTable:NO];
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
		[self updateLogMessage:[error localizedDescription]];
	}
	NSAssert([_session canAddInput:input], @"impossible to add AVCaptureDeviceInput");
	[_session addInput:input];

	AVCaptureVideoDataOutput* videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
	dispatch_queue_t videoDataOutputQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	[videoDataOutput setSampleBufferDelegate:self queue:videoDataOutputQueue];
	[videoDataOutput alwaysDiscardsLateVideoFrames];
	videoDataOutput.videoSettings = [NSDictionary dictionaryWithObject:
		[NSNumber numberWithInt:kCVPixelFormatType_32BGRA]
		forKey:(id)kCVPixelBufferPixelFormatTypeKey];
	NSAssert([_session canAddOutput:videoDataOutput], @"impossible to add AVCaptureVideoDataOutput");
	[_session addOutput:videoDataOutput];

	[[videoDataOutput connectionWithMediaType:AVMediaTypeVideo] setEnabled:YES];
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
	UIAlertView* alertView = [[UIAlertView alloc] initWithTitle:@"AVSession Failed!"
		message:nil delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];

	[alertView show];
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput*)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
	fromConnection:(AVCaptureConnection*)connection
{
	if(!self.captureButton.selected) {
		return;
	}

	AVCaptureVideoOrientation videoOrientation = [self videoOrientationFromInterfaceOrientation:
		[UIApplication sharedApplication].statusBarOrientation];
	if(connection.videoOrientation != videoOrientation) {
		[connection setVideoOrientation:videoOrientation];
		return;
	}

	[_dataCaptureService addSampleBuffer:sampleBuffer];
}

#pragma mark -

- (NSString*)buttonTitle
{
	return _selectedScenario[RTRScenarioKey];
}

#pragma mark -

- (void)updateLogMessage:(NSString*)message
{
	performBlockOnMainThread(0, ^{
		self.infoLabel.text = message;
	});
}

#pragma mark - Drawing results

/// Drawing data fields.
- (void)drawTextRegionsFromDataFields:(NSArray*)dataFields  progress:(RTRResultStabilityStatus)progress
{
	[self clearScreenFromRegions];

	CALayer* textRegionsLayer = [[CALayer alloc] init];
	textRegionsLayer.frame = _previewLayer.frame;
	textRegionsLayer.name = RTRTextRegionLayerName;

	for(RTRDataField* dataField in dataFields) {
		for(RTRTextLine* textLine in dataField.components) {
			[self drawTextLine:textLine inLayer:textRegionsLayer progress:progress];
		}
	}

	[self.previewView.layer addSublayer:textRegionsLayer];
}

/// Remove all previously visible regions.
- (void)clearScreenFromRegions
{
	// Get all visible regions.
	NSArray* sublayers = [NSArray arrayWithArray:[self.previewView.layer sublayers]];
	
	// Remove all layers with the name RTRTextRegionLayerName.
	for(CALayer* layer in sublayers) {
		if([[layer name] isEqualToString:RTRTextRegionLayerName]) {
			[layer removeFromSuperlayer];
		}
	}
}

/// Drawing the quadrangle specified by the RTRTextLine object 
/// and a separate recognized text layer, if there is any recognized text.
- (void)drawTextLine:(RTRTextLine*)textLine inLayer:(CALayer*)layer progress:(RTRResultStabilityStatus)progress
{
	[self drawQuadrangle:textLine.quadrangle inLayer:layer progress:progress];

	NSString* recognizedString = textLine.text;
	if(recognizedString == nil) {
		return;
	}
	
	CATextLayer* textLayer = [CATextLayer layer];

	// Creating the text layer rectangle: it should be close to the quadrangle drawn before.
	CGPoint topLeft = [self scaledPointFromImagePoint:textLine.quadrangle[0]];
	CGPoint bottomLeft = [self scaledPointFromImagePoint:textLine.quadrangle[1]];
	CGPoint bottomRight = [self scaledPointFromImagePoint:textLine.quadrangle[2]];
	CGPoint topRight = [self scaledPointFromImagePoint:textLine.quadrangle[3]];
	CGRect rectForTextLayer = CGRectMake(bottomLeft.x, bottomLeft.y,
		[self distanceBetweenPoint:topLeft andPoint:topRight],
		[self distanceBetweenPoint:topLeft andPoint:bottomLeft]);

	// Selecting the initial font size to suit the rectangle size.
	UIFont* textFont = [self fontForString:recognizedString inRect:rectForTextLayer];
	textLayer.font = (__bridge CFTypeRef)textFont;
	textLayer.fontSize = textFont.pointSize;
	textLayer.foregroundColor = [[self progressColor:progress] CGColor];
	textLayer.alignmentMode = kCAAlignmentCenter;
	textLayer.string = recognizedString;
	textLayer.frame = rectForTextLayer;
	
	// Rotating the text layer.
	CGFloat angle = asin((bottomRight.y - bottomLeft.y) / [self distanceBetweenPoint:bottomLeft andPoint:bottomRight]);
	textLayer.anchorPoint = CGPointMake(0.f, 0.f);
	textLayer.position = bottomLeft;
	CATransform3D t = CATransform3DIdentity;
	t = CATransform3DRotate(t, angle, 0.f, 0.f, 1.f);
	textLayer.transform = t;
	
	[layer addSublayer:textLayer];
}

/// Drawing a UIBezierPath using the quadrangle vertices.
- (void)drawQuadrangle:(NSArray<NSValue*>*)quadrangle inLayer:(CALayer*)layer progress:(RTRResultStabilityStatus)progress
{
	if(quadrangle.count == 0) {
		return;
	}

	CAShapeLayer* area = [CAShapeLayer layer];
	UIBezierPath* recognizedAreaPath = [UIBezierPath bezierPath];
	[quadrangle enumerateObjectsUsingBlock:^(NSValue* point, NSUInteger idx, BOOL* stop) {
		CGPoint scaledPoint = [self scaledPointFromImagePoint:point];
		if(idx == 0) {
			[recognizedAreaPath moveToPoint:scaledPoint];
		} else {
			[recognizedAreaPath addLineToPoint:scaledPoint];
		}
	}];

	[recognizedAreaPath closePath];
	area.path = recognizedAreaPath.CGPath;
	area.strokeColor = [[self progressColor:progress] CGColor];
	area.fillColor = [UIColor clearColor].CGColor;
	[layer addSublayer:area];
}

/// Scale the point coordinates.
- (CGPoint)scaledPointFromImagePoint:(NSValue*)pointValue
{
	CGFloat layerWidth = _previewLayer.bounds.size.width;
	CGFloat layerHeight = _previewLayer.bounds.size.height;

	CGFloat widthScale = layerWidth / _imageBufferSize.width;
	CGFloat heightScale = layerHeight / _imageBufferSize.height;

	CGPoint point = [pointValue CGPointValue];
	point.x *= widthScale;
	point.y *= heightScale;

	return point;
}

- (UIFont*)fontForString:(NSString*)string inRect:(CGRect)rect
{
	// Selecting the font size by height and then fine-tuning by width.

	CGFloat minFontSize = 0.1f; // initial font size
	CGFloat maxFontSize = 72.f;
	CGFloat fontSize = minFontSize;

	CGSize rectSize = rect.size;
	for(;;) {
		CGSize labelSize = [string sizeWithAttributes:@{NSFontAttributeName:[UIFont boldSystemFontOfSize:fontSize]}];
		if(rectSize.height - labelSize.height > 0) {
			minFontSize = fontSize;

			if(0.99f * rectSize.height - labelSize.height < 0) {
				break;
			}
		} else {
			maxFontSize = fontSize;
		}

		if(ABS(minFontSize - maxFontSize) < 0.01) {
			break;
		}

		fontSize = (minFontSize + maxFontSize) / 2;
	}

	return [UIFont boldSystemFontOfSize:fontSize];
}

/// Calculate the distance between points.
- (CGFloat)distanceBetweenPoint:(CGPoint)p1 andPoint:(CGPoint)p2
{
	CGVector vector = CGVectorMake(p2.x - p1.x, p2.y - p1.y);
	return sqrt(vector.dx * vector.dx + vector.dy * vector.dy);
}

#pragma mark - RTRDataCaptureServiceDelegate

- (void)onBufferProcessedWithDataScheme:(RTRDataScheme*)dataScheme dataFields:(NSArray<RTRDataField*>*)dataFields
	resultStatus:(RTRResultStabilityStatus)resultStatus
{
	performBlockOnMainThread(0, ^{
		if(!self.captureButton.selected) {
			return;
		}

		[self.progressIndicatorView setProgress:resultStatus color:[self progressColor:resultStatus]];

		if(dataScheme != nil && resultStatus == RTRResultStabilityStable) {
			self.captureButton.selected = NO;
			self.whiteBackgroundView.hidden = NO;
			[_dataCaptureService stopTasks];
		}

		[self drawTextRegionsFromDataFields:dataFields progress:resultStatus];
	});
}

- (void)onWarning:(RTRCallbackWarningCode)warningCode
{
	NSString* message = [self stringFromWarningCode:warningCode];
	if(message.length > 0) {
		if(!self.captureButton.selected) {
			return;
		}

		[self updateLogMessage:message];

		// Clear message after 2 seconds.
		performBlockOnMainThread(2, ^{
			[self updateLogMessage:nil];
		});
	}
}

- (void)onError:(NSError*)error
{
	NSLog(@"Error: %@", error);

	performBlockOnMainThread(0, ^{
		if(!self.captureButton.selected) {
			return;
		}

		NSString* description = error.localizedDescription;
		if([error.localizedDescription containsString:@"MRZ.rom"]) {
			description = @"MRZ is available in EXTENDED version only. Contact us for more information.";
		} else if([error.localizedDescription containsString:@"ChineseJapanese.rom"]) {
			description = @"Chineze, Japanese and Korean are available in EXTENDED version only. Contact us for more information.";
		}
		[self updateLogMessage:description];
		self.captureButton.selected = NO;
	});
}

/// Human-readable descriptions for the RTRCallbackWarningCode constants.
- (NSString*)stringFromWarningCode:(RTRCallbackWarningCode)warningCode
{
	NSString* warningString;
	switch(warningCode) {
		case RTRCallbackWarningTextTooSmall:
			warningString = @"Text is too small";
			break;

		default:
			break;
	}

	return warningString;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
	_selectedScenario = _dataCaptureScenarioSamples[indexPath.row];
	_dataCaptureService = [self createConfigureDataCaptureService:_selectedScenario];

	[tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
	[self.showSettingsButton setTitle:[self buttonTitle]];
	self.descriptionLabel.text = _selectedScenario[RTRDescriptionKey];
	[self showSettingsTable:NO];
	[self prepareUIForRecognition];
	self.captureButton.selected = YES;
}

#pragma mark - UITableViewDatasource

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
	return _dataCaptureScenarioSamples.count;
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
	UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	cell.textLabel.text = _dataCaptureScenarioSamples[indexPath.row][RTRScenarioKey];
	cell.detailTextLabel.text = _dataCaptureScenarioSamples[indexPath.row][RTRDescriptionKey];
	cell.accessoryType = [_selectedScenario isEqual:_dataCaptureScenarioSamples[indexPath.row]]
		? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;

	cell.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.4f];
	cell.textLabel.textColor = [UIColor whiteColor];
	cell.detailTextLabel.textColor = [UIColor lightGrayColor];
	cell.detailTextLabel.adjustsFontSizeToFitWidth = YES;

	cell.tintColor = [UIColor whiteColor];

	return cell;
}

- (NSString*)presetTitle:(NSString*)preset
{
	NSRange fstRange = [preset rangeOfCharacterFromSet:[NSCharacterSet decimalDigitCharacterSet]];
	if(fstRange.location == NSNotFound) {
		return preset;
	}

	return [preset substringFromIndex:fstRange.location];
}

#pragma mark - Utils

- (void)showSettingsTable:(BOOL)show
{
	self.settingsTableView.hidden = !show;
	self.descriptionLabel.hidden = show;
	[self updateLogMessage:nil];
}

#define RTRUIColorFromRGB(rgbValue) [UIColor \
	colorWithRed:((float)((rgbValue & 0xFF0000) >> 16))/255.0 \
	green:((float)((rgbValue & 0xFF00) >> 8))/255.0 \
	blue:((float)(rgbValue & 0xFF))/255.0 alpha:1.0]

- (UIColor*)progressColor:(RTRResultStabilityStatus)progress
{
	switch(progress) {
		case RTRResultStabilityNotReady:
		case RTRResultStabilityTentative:
			return RTRUIColorFromRGB(0xFF6500);
		case RTRResultStabilityVerified:
			return RTRUIColorFromRGB(0xC96500);
		case RTRResultStabilityAvailable:
			return RTRUIColorFromRGB(0x886500);
		case RTRResultStabilityTentativelyStable:
			return RTRUIColorFromRGB(0x4B6500);
		case RTRResultStabilityStable:
			return RTRUIColorFromRGB(0x006500);

		default:
			return [UIColor redColor];
			break;
	}
}

@end
