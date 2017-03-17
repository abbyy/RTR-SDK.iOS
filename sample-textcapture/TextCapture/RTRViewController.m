// ABBYY® Real-Time Recognition SDK 1 © 2016 ABBYY Production LLC.
// ABBYY is either a registered trademark or a trademark of ABBYY Software Ltd.

#import "RTRViewController.h"

#import <AVFoundation/AVFoundation.h>
#import <AbbyyRtrSDK/AbbyyRtrSDK.h>

#import "RTRSelectedAreaView.h"

/// Cell ID for languagesTableView.
static NSString* const RTRTableCellID = @"RTRTableCellID";
/// Name for text region layers.
static NSString* const RTRTextRegionLayerName = @"RTRTextRegionLayerName";

@interface RTRViewController () <AVCaptureVideoDataOutputSampleBufferDelegate,
	RTRRecognitionServiceDelegate, UITableViewDelegate, UITableViewDataSource>

/// Recognition languages table.
@property (nonatomic, weak) IBOutlet UITableView* languagesTableView;
/// Button for show / hide table with recognition languages.
@property (nonatomic, weak) IBOutlet UIBarButtonItem* recognizeLanguageButton;

/// View with camera preview layer.
@property (nonatomic, weak) IBOutlet UIView* previewView;
/// Stop/Start capture button
@property (nonatomic, weak) IBOutlet UIButton* captureButton;

/// View for displaying current area of interest.
@property (nonatomic, weak) IBOutlet RTRSelectedAreaView* overlayView;
/// White view for highlight recognition results.
@property (nonatomic, weak) IBOutlet UIView* whiteBackgroundView;

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
	id<RTRRecognitionService> _textCaptureService;

	/// Selected recognition languages.
	NSMutableSet* _selectedRecognitionLanguages;

	/// Area of interest in view coordinates.
	CGRect _selectedArea;
}

#pragma mark - UIView LifeCycle

- (void)viewDidLoad
{
	[super viewDidLoad];
	// Recommended session preset.
	_sessionPreset = AVCaptureSessionPreset1280x720;
	_imageBufferSize = CGSizeMake(720.f, 1280.f);

	// Default recognition language.
	_selectedRecognitionLanguages = [[NSSet setWithObject:@"English"] mutableCopy];

	NSString* licensePath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"AbbyyRtrSdk.license"];
	_engine = [RTREngine sharedEngineWithLicenseData:[NSData dataWithContentsOfFile:licensePath]];
	NSAssert(_engine != nil, nil);

	_textCaptureService = [_engine createTextCaptureServiceWithDelegate:self];
	[_textCaptureService setRecognitionLanguages:_selectedRecognitionLanguages];

	[self.languagesTableView registerClass:[UITableViewCell class] forCellReuseIdentifier:RTRTableCellID];

	self.languagesTableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];

	self.captureButton.selected = NO;
	[self.captureButton setTitle:@"Stop" forState:UIControlStateSelected];
	[self.captureButton setTitle:@"Start" forState:UIControlStateNormal];

	self.languagesTableView.hidden = YES;
	[self.recognizeLanguageButton setTitle:[self languagesButtonTitle]];
	__weak RTRViewController* weakSelf = self;
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

	[_textCaptureService setAreaOfInterest:selectedRect];
}

- (void)viewWillDisappear:(BOOL)animated
{
	[_session stopRunning];
	self.captureButton.selected = NO;
	[_textCaptureService stopTasks];

	[super viewWillDisappear:animated];
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
	[_textCaptureService stopTasks];
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
		[self clearScreenFromRegions];
		self.whiteBackgroundView.hidden = YES;
    } else {
        [_textCaptureService stopTasks];
    }
}

- (IBAction)onReconitionLanguages
{
	[self changeLanguagesTableVisibilty];
}

- (void)changeLanguagesTableVisibilty
{
	if(self.languagesTableView.hidden) {
		self.captureButton.selected = NO;
		[self.languagesTableView reloadData];
		[self showSettingsTable:YES];

	} else {
		[self tryToCloseLanguagesTable];
	}
}

- (void)tryToCloseLanguagesTable
{
	if(_selectedRecognitionLanguages.count != 0) {
		[_textCaptureService setRecognitionLanguages:_selectedRecognitionLanguages];
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
		NSLog(@"%@",[error localizedDescription]);
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

	[connection setVideoOrientation:[self videoOrientationFromInterfaceOrientation:
		[UIApplication sharedApplication].statusBarOrientation]];

	[_textCaptureService addSampleBuffer:sampleBuffer];
}


#pragma mark -

- (NSString*)languagesButtonTitle
{
	if(_selectedRecognitionLanguages.count == 1) {
		return _selectedRecognitionLanguages.anyObject;
	}

	NSMutableString* resultTitle = [@"" mutableCopy];
	for(NSString* language in _selectedRecognitionLanguages) {
		[resultTitle appendFormat:@"%@ ", [language substringToIndex:2].uppercaseString];
	}

	return resultTitle;
}

#pragma mark - MOCR lazy instatiations

- (NSArray*)recognitionLanguages
{
	return @[
		@"English",
		@"French",
		@"German",
		@"Italian",
		@"Polish",
		@"PortugueseBrazilian",
		@"Russian",
		@"Spanish",
		@"ChineseSimplified",
		@"ChineseTraditional",
		@"Japanese",
		@"Korean"
	];
}

- (void)updateLogMessage:(NSString*)logMessage
{
	if(logMessage.length > 0) {
		NSLog(@"%@", logMessage);
	}
}

#pragma mark - Drawing results

/// Drawing text lines.
- (void)drawTextLines:(NSArray*)textLines progress:(RTRResultStabilityStatus)progress
{
	[self clearScreenFromRegions];
	
	CALayer* textRegionsLayer = [[CALayer alloc] init];
	textRegionsLayer.frame = _previewLayer.frame;
	textRegionsLayer.name = RTRTextRegionLayerName;

	for(RTRTextLine* textLine in textLines) {
		[self drawTextLine:textLine inLayer:textRegionsLayer progress:progress];
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
	CGPoint topLeft = [self scaledPointFromCMocrPoint:textLine.quadrangle[0]];
	CGPoint bottomLeft = [self scaledPointFromCMocrPoint:textLine.quadrangle[1]];
	CGPoint bottomRight = [self scaledPointFromCMocrPoint:textLine.quadrangle[2]];
	CGPoint topRight = [self scaledPointFromCMocrPoint:textLine.quadrangle[3]];
	[self drawQuadrangleWithPoint0:topLeft Point1:bottomLeft Point2:bottomRight Point3:topRight inLayer:layer progress:progress];

	NSString* recognizedString = textLine.text;
	if(recognizedString == nil) {
		return;
	}
	
	CATextLayer* textLayer = [CATextLayer layer];
	// Creating the text layer rectangle: it should be close to the quadrangle drawn previously.
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
- (void)drawQuadrangleWithPoint0:(CGPoint)p0 Point1:(CGPoint)p1 Point2:(CGPoint)p2 Point3:(CGPoint)p3
	inLayer:(CALayer*)layer progress:(RTRResultStabilityStatus)progress
{
	CAShapeLayer* area = [CAShapeLayer layer];
	UIBezierPath* recognizedAreaPath = [UIBezierPath bezierPath];
	[recognizedAreaPath moveToPoint:p0];
	[recognizedAreaPath addLineToPoint:p1];
	[recognizedAreaPath addLineToPoint:p2];
	[recognizedAreaPath addLineToPoint:p3];
	[recognizedAreaPath closePath];
	area.path = recognizedAreaPath.CGPath;
	area.strokeColor = [[self progressColor:progress] CGColor];
	area.fillColor = [UIColor clearColor].CGColor;
	[layer addSublayer:area];
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

/// Scale the point coordinates.
- (CGPoint)scaledPointFromCMocrPoint:(NSValue*)mocrPoint
{
	CGFloat layerWidth = _previewLayer.bounds.size.width;
	CGFloat layerHeight = _previewLayer.bounds.size.height;
	
	CGFloat widthScale = layerWidth / _imageBufferSize.width;
	CGFloat heightScale = layerHeight / _imageBufferSize.height;
	
	CGPoint point = [mocrPoint CGPointValue];
	point.x *= widthScale;
	point.y *= heightScale;
	
	return point;
}

#pragma mark - RTRRecognitionServiceDelegate

- (void)onBufferProcessedWithTextLines:(NSArray*)textLines resultStatus:(RTRResultStabilityStatus)resultStatus
{
	dispatch_async(dispatch_get_main_queue(), ^{
		if(!self.captureButton.selected) {
			return;
		}

		if(resultStatus == RTRResultStabilityStable) {
			self.captureButton.selected = NO;
			self.whiteBackgroundView.hidden = NO;
            [_textCaptureService stopTasks];
		}

		[self drawTextLines:textLines progress:resultStatus];
	});
}

- (void)onWarning:(RTRCallbackWarningCode)warningCode
{
	NSString* message = [self stringFromWarningCode:warningCode];
	[self updateLogMessage:message];
}

- (void)onError:(NSError*)error
{
	NSLog(@"Error: %@", error);
}

/// Human-readable descriptions for the RTRCallbackWarningCode constants.
- (NSString*)stringFromWarningCode:(RTRCallbackWarningCode)warningCode
{
	NSString* warningString;
	switch(warningCode) {
		case RTRCallbackWarningSmallTextSizeInFindText:
			warningString = @"Text is too small";
			break;

		default:
			warningString = @"Unknown warning code";
	}

	return warningString;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
	NSString* language = self.recognitionLanguages[indexPath.row];
	BOOL isSelected = ![_selectedRecognitionLanguages containsObject:language];
	if(isSelected) {
		[_selectedRecognitionLanguages addObject:language];
	} else {
		[_selectedRecognitionLanguages removeObject:language];
	}

	[self.recognizeLanguageButton setTitle:[self languagesButtonTitle]];

	[tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
}

#pragma mark - UITableViewDatasource

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
	return [self recognitionLanguages].count;
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
	UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	NSString* language = [self recognitionLanguages][indexPath.row];
	cell.textLabel.text = language;
	cell.accessoryType = [_selectedRecognitionLanguages containsObject:language]
		? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;

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
	self.languagesTableView.hidden = !show;
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
