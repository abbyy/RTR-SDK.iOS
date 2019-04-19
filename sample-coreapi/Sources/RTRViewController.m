// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

#import "RTRViewController.h"

#import <AVFoundation/AVFoundation.h>
#import <AbbyyRtrSDK/AbbyyRtrSDK.h>

typedef enum : NSInteger {
	RTRCoreAPIScenarioText,
	RTRCoreAPIScenarioBusinessCards,
	RTRCoreAPIScenarioCount,
} RTRCoreAPIScenarioType;

/// Cell ID for languagesTableView.
static NSString* const RTRTableCellID = @"RTRTableCellID";

@interface RTRViewController () <UIImagePickerControllerDelegate, UITableViewDelegate, UITableViewDataSource,
	UINavigationControllerDelegate>

/// Recognition languages table.
@property (nonatomic, weak) IBOutlet UITableView* languagesTableView;
/// Button for show / hide table with availabe Core API actions.
@property (nonatomic, weak) IBOutlet UIBarButtonItem* actionsButton;
/// Button for show / hide table with recognition languages.
@property (nonatomic, weak) IBOutlet UIBarButtonItem* recognitionLanguagesButton;

/// Open Photo Library button.
@property (nonatomic, weak) IBOutlet UIButton* selectImageButton;

/// Text view for recognized text.
@property (nonatomic, weak) IBOutlet UITextView* textView;
/// Recognition progress view.
@property (nonatomic, weak) IBOutlet UIProgressView* progressView;
/// Label for error or warning info.
@property (nonatomic, weak) IBOutlet UILabel* infoLabel;

/// Store selected image for re-recognition on languages changing.
@property (nonatomic, strong) UIImage* selectedImage;

@property (atomic, assign) NSUInteger lastTaskNumber;
@property (nonatomic, assign) RTRCoreAPIScenarioType currentCoreAPIScenario;
@property (nonatomic, assign) BOOL currentTableForLanguages;

@property (nonatomic, strong) NSArray<NSString*>* recognitionLanguages;

@end

#pragma mark -

@implementation RTRViewController {
	/// Engine for AbbyyRtrSDK.
	RTREngine* _engine;
	/// Selected recognition languages.
	NSMutableSet* _selectedRecognitionLanguages;
}

#pragma mark - UIView LifeCycle

- (void)viewDidLoad
{
	[super viewDidLoad];

	// Default recognition language.
	_selectedRecognitionLanguages = [[NSSet setWithObject:RTRLanguageNameEnglish] mutableCopy];

	[self.languagesTableView registerClass:[UITableViewCell class] forCellReuseIdentifier:RTRTableCellID];

	self.languagesTableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];

	self.languagesTableView.hidden = YES;
	[self.recognitionLanguagesButton setTitle:[self languagesButtonTitle]];

	self.textView.text = @"";
	[self.progressView setProgress:0];

	NSString* licensePath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"license"];
	_engine = [RTREngine sharedEngineWithLicenseData:[NSData dataWithContentsOfFile:licensePath]];
	if(_engine == nil) {
		self.selectImageButton.enabled = NO;
		[self updateLogMessage:@"Invalid License"];
		return;
	}

	_lastTaskNumber = 0;

	self.actionsButton.enabled = YES;
	self.recognitionLanguagesButton.enabled = YES;
}

- (BOOL)prefersStatusBarHidden
{
	return NO;
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
	return UIStatusBarStyleLightContent;
}

#pragma mark - Actions

- (IBAction)capturePressed
{
	if(!self.selectImageButton.enabled) {
		return;
	}

	UIImagePickerController* photoLibrary = [[UIImagePickerController alloc] init];
	photoLibrary.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
	photoLibrary.delegate = self;
	photoLibrary.modalPresentationStyle = UIModalPresentationOverFullScreen;

	[self presentViewController:photoLibrary animated:YES completion:nil];
}

- (IBAction)onChangeAction
{
	self.currentTableForLanguages = NO;
	[self changeLanguagesTableVisibilty];
}

- (IBAction)onReconitionLanguages
{
	self.currentTableForLanguages = YES;
	[self changeLanguagesTableVisibilty];
}

- (void)changeLanguagesTableVisibilty
{
	if(self.languagesTableView.hidden) {
		[self.languagesTableView reloadData];
		[self showSettingsTable:YES];

	} else {
		[self tryToCloseLanguagesTable];
	}
}

- (void)tryToCloseLanguagesTable
{
	if(self.currentTableForLanguages) {
		if(_selectedRecognitionLanguages.count != 0) {
			[self showSettingsTable:NO];
		}
	} else {
		[self showSettingsTable:NO];
	}
}

#pragma mark -

- (NSString*)languagesButtonTitle
{
	if(_selectedRecognitionLanguages.count == 1) {
		return _selectedRecognitionLanguages.anyObject;
	}

	NSMutableString* resultTitle = [@"" mutableCopy];
	for(NSString* language in _selectedRecognitionLanguages) {
		if([language isEqualToString:RTRLanguageNameChineseSimplified]) {
			[resultTitle appendString:@"CHS "];
		} else if([language isEqualToString:RTRLanguageNameChineseTraditional]) {
			[resultTitle appendString:@"CHT "];
		} else {
			[resultTitle appendFormat:@"%@ ", [language substringToIndex:2].uppercaseString];
		}
	}

	return resultTitle;
}

#pragma mark -

- (NSArray*)recognitionLanguages
{
	if(_recognitionLanguages == nil) {
		_recognitionLanguages = @[
			RTRLanguageNameChineseSimplified,
			RTRLanguageNameChineseTraditional,
			RTRLanguageNameEnglish,
			RTRLanguageNameFrench,
			RTRLanguageNameGerman,
			RTRLanguageNameItalian,
			RTRLanguageNameJapanese,
			RTRLanguageNameKorean,
			RTRLanguageNamePolish,
			RTRLanguageNamePortugueseBrazilian,
			RTRLanguageNameRussian,
			RTRLanguageNameSpanish,
		];
	}
	return _recognitionLanguages;
}

- (void)updateLogMessage:(NSString*)message
{
	dispatch_async(dispatch_get_main_queue(), ^{
		self.infoLabel.text = message;
	});
}

- (void)showTextBlocks:(NSArray<RTRTextBlock*>*)textBlocks
{
	NSMutableString* text = [@"" mutableCopy];
	for(RTRTextBlock* block in textBlocks) {
		for(RTRTextLine* line in block.textLines) {
			[text appendFormat:@"%@\n", line.text];
		}
		[text appendString:@"\n"];
	}

	self.textView.text = text;
}

- (void)showDataFields:(NSArray<RTRDataField*>*)dataFields
{
	NSMutableString* text = [@"" mutableCopy];
	for(RTRDataField* field in dataFields) {
		[text appendFormat:@"%@: %@\n", field.name, field.text];
	}

	self.textView.text = text;
}

#pragma mark - UIImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController*)picker didFinishPickingMediaWithInfo:(NSDictionary*)info
{
	UIImage* image = [info valueForKey:UIImagePickerControllerOriginalImage];
	self.selectedImage = image;

	__weak typeof(self) weakSelf = self;
	typeof(^{}) completion = ^{
		[picker.presentingViewController dismissViewControllerAnimated:YES completion:^{
			[weakSelf recognizeImage:image];
		}];
	};

	if(NSThread.isMainThread) {
		completion();
	} else {
		dispatch_async(dispatch_get_main_queue(), completion);
	}
}

- (void)recognizeImage:(UIImage*)image
{
	self.textView.text = @"";
	self.infoLabel.text = @"";

	self.lastTaskNumber++;
	NSUInteger currentTaskNumber = self.lastTaskNumber;

	__weak typeof(self) weakSelf = self;
	RTRProgressCallbackBlock progressBlock = ^BOOL(NSInteger percentage, RTRCallbackWarningCode warningCode)
	{
		if(currentTaskNumber != weakSelf.lastTaskNumber) {
			return NO;
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			[weakSelf.progressView setProgress:percentage * 1.f / 100 animated:YES];
			[weakSelf onWarning:warningCode];
		});

		return YES;
	};

	typeof(^{}) actionBlock = nil;

	id<RTRCoreAPI> coreAPI = [_engine createCoreAPI];
	[coreAPI.textRecognitionSettings setRecognitionLanguages:_selectedRecognitionLanguages];
	switch(self.currentCoreAPIScenario) {
		case RTRCoreAPIScenarioText:
		{
			actionBlock = ^{
				NSError* error;
				NSArray<RTRTextBlock*>* result = [coreAPI recognizeTextOnImage:image onProgress:progressBlock
					onTextOrientationDetected:nil error:&error];

				dispatch_async(dispatch_get_main_queue(), ^{
					if(currentTaskNumber == weakSelf.lastTaskNumber) {
						if(result == nil) {
							[weakSelf onError:error];
						} else {
							[weakSelf showTextBlocks:result];
						}
					}
					[weakSelf.progressView setProgress:1 animated:YES];
					[weakSelf.progressView setProgress:0 animated:NO];
				});
			};
			[coreAPI.textRecognitionSettings setRecognitionLanguages:_selectedRecognitionLanguages];
			break;
		}

		case RTRCoreAPIScenarioBusinessCards:
		{
			actionBlock = ^{
				NSError* error;
				NSArray<RTRDataField*>* result = [coreAPI extractDataFromImage:image onProgress:progressBlock
					onTextOrientationDetected:nil error:&error];

				dispatch_async(dispatch_get_main_queue(), ^{
					if(currentTaskNumber == weakSelf.lastTaskNumber) {
						if(result == nil) {
							[weakSelf onError:error];
						} else {
							[weakSelf showDataFields:result];
						}
					}
					[weakSelf.progressView setProgress:1 animated:YES];
					[weakSelf.progressView setProgress:0 animated:NO];
				});
			};
			[coreAPI.dataCaptureSettings.configureDataCaptureProfile setRecognitionLanguages:_selectedRecognitionLanguages];
			break;
		}
		default:
			break;
	}

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), actionBlock);
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController*)picker
{
	[picker.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)onWarning:(RTRCallbackWarningCode)warningCode
{
	NSString* message = [self stringFromWarningCode:warningCode];
	if(message.length > 0) {
		[self updateLogMessage:message];
	}
}

- (void)onError:(NSError*)error
{
	[self updateLogMessage:error.localizedDescription];
}

/// Human-readable descriptions for the RTRCallbackWarningCode constants.
- (NSString*)stringFromWarningCode:(RTRCallbackWarningCode)warningCode
{
	NSString* warningString;
	switch(warningCode) {
		case RTRCallbackWarningTextTooSmall:
			warningString = @"Text is too small.";
			break;

		case RTRCallbackWarningRecognitionIsSlow:
			warningString = @"The image is being recognized too slowly, perhaps something is going wrong.";
			break;

		case RTRCallbackWarningProbablyLowQualityImage:
			warningString = @"The image probably has low quality.";
			break;

		case RTRCallbackWarningProbablyWrongLanguage:
			warningString = @"The chosen recognition language is probably wrong.";
			break;

		case RTRCallbackWarningWrongLanguage:
			warningString = @"The chosen recognition language is wrong.";
			break;

		default:
			break;
	}

	return warningString;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
	if(self.currentTableForLanguages) {
		NSString* language = self.recognitionLanguages[indexPath.row];
		BOOL isSelected = ![_selectedRecognitionLanguages containsObject:language];
		if(isSelected) {
			[_selectedRecognitionLanguages addObject:language];
		} else {
			[_selectedRecognitionLanguages removeObject:language];
		}

		[self.recognitionLanguagesButton setTitle:[self languagesButtonTitle]];

		[tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
	} else {
		self.currentCoreAPIScenario = indexPath.row;
		[self.actionsButton setTitle:[self titleForAction:self.currentCoreAPIScenario]];
		[self tryToCloseLanguagesTable];
	}
}

#pragma mark - UITableViewDatasource

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
	if(self.currentTableForLanguages) {
		return self.recognitionLanguages.count;
	} else {
		return RTRCoreAPIScenarioCount;
	}
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
	UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	if(self.currentTableForLanguages) {
		NSString* language = self.recognitionLanguages[indexPath.row];
		cell.textLabel.text = language;
		cell.accessoryType = [_selectedRecognitionLanguages containsObject:language]
			? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	} else {
		cell.textLabel.text = [self titleForAction:indexPath.row];
		cell.accessoryType = self.currentCoreAPIScenario == indexPath.row
			? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	}

	cell.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.4f];
	cell.textLabel.textColor = [UIColor whiteColor];
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

#pragma mark - CoreAPI Actions

- (NSString*)titleForAction:(RTRCoreAPIScenarioType)action
{
	switch(action) {
		case RTRCoreAPIScenarioText:
			return @"Text";
			break;

		case RTRCoreAPIScenarioBusinessCards:
			return @"BusinessCards";
			break;

		default:
			break;
	}
	return nil;
}

#pragma mark - Utils

- (void)showSettingsTable:(BOOL)show
{
	self.languagesTableView.hidden = !show;
	[self updateLogMessage:nil];
	if(!show) {
		if(_selectedRecognitionLanguages.count == 0) {
			[_selectedRecognitionLanguages addObject:RTRLanguageNameEnglish];
			[self.recognitionLanguagesButton setTitle:[self languagesButtonTitle]];
		}
		if(self.selectedImage != nil) {
			[self recognizeImage:self.selectedImage];
		}
	}
}

@end
