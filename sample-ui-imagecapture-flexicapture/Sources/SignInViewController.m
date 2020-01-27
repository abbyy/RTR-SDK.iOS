/// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
/// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

#import "SignInViewController.h"
#import "NSUserDefaults+FCSignInData.h"
#import "NSUserDefaults+FCUserData.h"
#import "SelectProjectViewController.h"
#import "FlexiCaptureClient.h"
#import "RecognizerEngine.h"

typedef NS_ENUM(NSUInteger, ConnectionState) {
	/// not all text fields filled
	ConnectionStateWaitingForData,
	/// show "Connection" button
	ConnectionStateReadyToConnection,
	/// show progress indicator
	ConnectionStateConnectingInProgress,
	/// show "Successful connection" message
	ConnectionStateSuccessfulConnection,
	/// show "No connection" message
	ConnectionStateNoConnection,
	/// show "Enter password" message
	ConnectionStateEnterPassword,
	/// show "No projects" message
	ConnectionStateNoProjects,
};

@interface SignInViewController () <UITextFieldDelegate, SelectProjectViewControllerDelegate>
@end

@interface SignInViewController ()

@property (nonatomic, weak) IBOutlet UIScrollView* scrollView;

@property (nonatomic, weak) IBOutlet UITextField* urlTextField;
@property (nonatomic, weak) IBOutlet UITextField* tenantTextField;
@property (nonatomic, weak) IBOutlet UITextField* usernameTextField;
@property (nonatomic, weak) IBOutlet UITextField* passwordTextField;

@property (nonatomic, weak) IBOutlet UIImageView* urlLockImageView;
@property (nonatomic, weak) IBOutlet UIImageView* tenantLockImageView;
@property (nonatomic, weak) IBOutlet UIImageView* usernameLockImageView;

@property (nonatomic, weak) IBOutlet UIButton* signInButton;

@property (nonatomic, weak) IBOutlet UIView* connectingIndicatorView;

@property (nonatomic, weak) IBOutlet UIView* connectionInfoView;
@property (nonatomic, weak) IBOutlet UIImageView* connectionInfoImageView;
@property (nonatomic, weak) IBOutlet UILabel* connectionInfoLabel;
@property (nonatomic, weak) IBOutlet UIButton* reconnectButton;

@property (nonatomic, weak) IBOutlet UIButton* selectProjectButton;
@property (nonatomic, weak) IBOutlet UIImageView* selectProjectArrowImageView;
@property (nonatomic, weak) IBOutlet UIStackView* selectProjectStackView;

/// strong link is used to prevent re-creation when the element should be deleted from the navigation bar or added to it
@property (nonatomic, strong) IBOutlet UIBarButtonItem* logOutButtonItem;

@property (nonatomic, weak) IBOutlet UILabel* versionLabel;

@property (nonatomic, strong) NSArray<NSString*>* projectsNames;

@property (nonatomic, assign) ConnectionState currentConnectionState;

@property (nonatomic, weak) UITextField* activeTextField;

@end

@implementation SignInViewController

- (void)viewDidLoad
{
	[super viewDidLoad];

	NSBundle* bundle = [NSBundle bundleForClass:RTREngine.class];
	self.versionLabel.text = [NSString stringWithFormat:@"Build: %@", bundle.infoDictionary[@"CFBundleVersion"] ];

	self.urlTextField.delegate = self;
	self.tenantTextField.delegate = self;
	self.usernameTextField.delegate = self;
	self.passwordTextField.delegate = self;

	// text changed -> change state
	[self.urlTextField addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];
	[self.tenantTextField addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];
	[self.usernameTextField addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];
	[self.passwordTextField addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];

	// we need to know current active textField
	[self.urlTextField addTarget:self action:@selector(textFieldEditingDidBegin:) forControlEvents:UIControlEventEditingDidBegin];
	[self.tenantTextField addTarget:self action:@selector(textFieldEditingDidBegin:) forControlEvents:UIControlEventEditingDidBegin];
	[self.usernameTextField addTarget:self action:@selector(textFieldEditingDidBegin:) forControlEvents:UIControlEventEditingDidBegin];
	[self.passwordTextField addTarget:self action:@selector(textFieldEditingDidBegin:) forControlEvents:UIControlEventEditingDidBegin];

	// hints
	NSUserDefaults* userDefaults = NSUserDefaults.standardUserDefaults;
	self.urlTextField.text = userDefaults.url;
	self.tenantTextField.text = userDefaults.tenant;
	self.usernameTextField.text = userDefaults.username;

	if(userDefaults.authorized) {
		self.projectsNames = @[userDefaults.projectName];
		self.currentConnectionState = ConnectionStateEnterPassword;
		[self.selectProjectButton setTitle:userDefaults.projectName forState:UIControlStateNormal];
	} else {
		self.currentConnectionState = [self checkRequiredTextFieldsFilled] ? ConnectionStateReadyToConnection : ConnectionStateWaitingForData;
	}

	self.selectProjectButton.enabled = NO;

	// tint arrow
	self.selectProjectArrowImageView.image = [self.selectProjectArrowImageView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];

	// hide keyboard on tap
	UITapGestureRecognizer* tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideKeyboard)];
	tapGesture.cancelsTouchesInView = NO;
	[self.scrollView addGestureRecognizer:tapGesture];

	// keyboard notifications
	[NSNotificationCenter.defaultCenter addObserver:self
		selector:@selector(keyboardWasShown:)
		name:UIKeyboardDidShowNotification object:nil];

	[NSNotificationCenter.defaultCenter addObserver:self
		selector:@selector(keyboardWillBeHidden:)
		name:UIKeyboardWillHideNotification object:nil];
}

- (void)dealloc
{
	[NSNotificationCenter.defaultCenter removeObserver:self name:UIKeyboardDidShowNotification object:nil];
	[NSNotificationCenter.defaultCenter removeObserver:self name:UIKeyboardWillHideNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	self.navigationController.navigationBarHidden = NO;
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];

	[self cancelSignInRequest];
}

- (IBAction)onSignIn:(id)sender
{
	[self signIn];
}

- (IBAction)onReconnect:(id)sender
{
	[self signIn];
}

- (IBAction)onSelectProject:(id)sender
{
	if(self.projectsNames.count > 0) {
		UIStoryboard* storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
		SelectProjectViewController* vc = [storyboard instantiateViewControllerWithIdentifier:@"SelectProjectViewController"];
		NSParameterAssert([vc isKindOfClass:SelectProjectViewController.class]);

		NSUserDefaults* userDefaults = NSUserDefaults.standardUserDefaults;
		vc.projectsNames = self.projectsNames;
		vc.selectedProjectName = userDefaults.projectName;
		vc.delegate = self;

		[self.navigationController pushViewController:vc animated:YES];
	}
}

- (IBAction)onLogOut:(id)sender
{
	UIAlertController* alert = [UIAlertController
		alertControllerWithTitle:NSLocalizedString(@"LogOut", nil)
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
		[wSelf cancelSignInRequest];

		[wSelf signOut];
		wSelf.urlTextField.text = @"";
		wSelf.tenantTextField.text = @"";
		wSelf.usernameTextField.text = @"";
		wSelf.passwordTextField.text = @"";

		wSelf.currentConnectionState = ConnectionStateWaitingForData;
	}]];

	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - utilities

- (BOOL)checkRequiredTextFieldsFilled
{
	if(self.urlTextField.text.length == 0) {
		return NO;
	}
	if(self.usernameTextField.text.length == 0) {
		return NO;
	}
	if(self.passwordTextField.text.length == 0) {
		return NO;
	}

	return YES;
}

- (void)signIn
{
	if(![self checkRequiredTextFieldsFilled]) {
		return;
	}

	NSString* url = self.urlTextField.text;
	NSString* tenant = self.tenantTextField.text;
	NSString* username = self.usernameTextField.text;
	NSString* password = self.passwordTextField.text;

	[self signOut];
	self.currentConnectionState = ConnectionStateConnectingInProgress;

	__weak typeof(self) wSelf = self;
	[FlexiCaptureClient requestProjectsListWithUrl:url tenant:tenant username:username password:password success:^(NSString* authTicket, NSArray* projects) {
		[wSelf processProjects:projects];

		if(wSelf.currentConnectionState != ConnectionStateNoProjects) {
			wSelf.currentConnectionState = ConnectionStateSuccessfulConnection;

			NSUserDefaults* userDefaults = NSUserDefaults.standardUserDefaults;
			userDefaults.url = url;
			userDefaults.tenant = tenant;
			userDefaults.username = username;
			userDefaults.authTicket = authTicket;
		}
	} fail:^(NSError* error) {
		if(error.code == NSURLErrorCancelled) {
			wSelf.currentConnectionState = [wSelf checkRequiredTextFieldsFilled] ? ConnectionStateReadyToConnection : ConnectionStateWaitingForData;
		} else {
			wSelf.currentConnectionState = ConnectionStateNoConnection;
			[wSelf showErrorMessage:error.localizedDescription];
		}
	}];
}

- (void)signOut
{
	NSUserDefaults* userDefaults = NSUserDefaults.standardUserDefaults;
	userDefaults.url = @"";
	userDefaults.tenant = @"";
	userDefaults.username = @"";
	userDefaults.authTicket = @"";
	userDefaults.projectName = @"";
}

- (void)processProjects:(NSArray*)projects
{
	NSMutableArray* projectsNames = @[].mutableCopy;
	for(NSDictionary* project in projects) {
		[projectsNames addObject:project[@"name"]];
	}

	if(projectsNames.count == 0) {
		self.currentConnectionState = ConnectionStateNoProjects;
		return;
	}

	self.projectsNames = projectsNames;

	NSUserDefaults* userDefaults = NSUserDefaults.standardUserDefaults;
	userDefaults.projectName = self.projectsNames[0];

	__weak typeof(self) wSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{
		[wSelf.selectProjectButton setTitle:wSelf.projectsNames.firstObject forState:UIControlStateNormal];
		wSelf.selectProjectButton.enabled = YES;
	});
}

- (void)cancelSignInRequest
{
	[FlexiCaptureClient cancelAllRequests];
}

- (void)showErrorMessage:(NSString*)message
{
	UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error", nil)
		message:message
		preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Ok", nil) style:UIAlertActionStyleDefault handler:nil]];
	[self.navigationController presentViewController:alert animated:YES completion:nil];
}

#pragma mark - SelectProjectViewControllerDelegate

- (void)selectedProject:(NSString*)projectName
{
	NSUserDefaults* userDefaults = NSUserDefaults.standardUserDefaults;
	userDefaults.projectName = projectName;

	__weak typeof(self) wSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{
		[wSelf.selectProjectButton setTitle:projectName forState:UIControlStateNormal];
	});
}
#pragma mark - connection state

- (void)setCurrentConnectionState:(ConnectionState)currentConnectionState
{
	_currentConnectionState = currentConnectionState;

	__weak typeof(self) wSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{
		switch(wSelf.currentConnectionState) {
			case ConnectionStateWaitingForData:
				[wSelf setWaitingForData];
				break;
			case ConnectionStateReadyToConnection:
				[wSelf setReadyToConnection];
				break;
			case ConnectionStateConnectingInProgress:
				[wSelf connectionInfoConnectionInProgress];
				break;
			case ConnectionStateSuccessfulConnection:
				[wSelf connectionInfoSuccessfulConnection];
				break;
			case ConnectionStateNoConnection:
				[wSelf connectionInfoNoConnection];
				break;
			case ConnectionStateEnterPassword:
				[wSelf connectionInfoEnterPassword];
				break;
			case ConnectionStateNoProjects:
				[wSelf connectionInfoNoProjects];
				break;
			default:
				NSAssert(NO, @"Unexpected");
				break;
		}
	});
}

#pragma mark - connection info

- (void)setWaitingForData
{
	[self hideConnectionInfo];
	self.signInButton.enabled = NO;
	self.signInButton.hidden = NO;
	self.navigationItem.rightBarButtonItems = @[];
	self.selectProjectStackView.hidden = YES;

	[self refreshInputTextState];
}

- (void)setReadyToConnection
{
	[self hideConnectionInfo];
	self.signInButton.enabled = YES;
	self.signInButton.hidden = NO;
	self.navigationItem.rightBarButtonItems = @[];
	self.selectProjectStackView.hidden = YES;

	[self refreshInputTextState];
}

- (void)hideConnectionInfo
{
	self.connectionInfoView.hidden = YES;
	self.connectingIndicatorView.hidden = YES;
	self.navigationItem.rightBarButtonItems = @[];
}

- (void)connectionInfoConnectionInProgress
{
	self.signInButton.hidden = YES;
	self.connectionInfoView.hidden = YES;
	self.connectingIndicatorView.hidden = NO;
	self.selectProjectStackView.hidden = YES;
	self.navigationItem.rightBarButtonItems = @[];

	[self setInputTextDisabled];
}

- (void)connectionInfoNoConnection
{
	self.signInButton.hidden = YES;
	self.connectingIndicatorView.hidden = YES;
	self.connectionInfoView.hidden = NO;
	self.selectProjectStackView.hidden = YES;
	self.navigationItem.rightBarButtonItems = @[];

	UIColor* redColor = [[UIColor alloc] initWithRed:198 / 255.0 green:12 / 255.0 blue:48 / 255.0 alpha:1.0];
	self.connectionInfoImageView.image = [UIImage imageNamed:@"error"];
	[self.connectionInfoLabel setTextColor:redColor];
	self.connectionInfoLabel.text = NSLocalizedString(@"NoConnection", nil);

	self.reconnectButton.hidden = NO;
	self.reconnectButton.enabled = [self checkRequiredTextFieldsFilled];

	[self refreshInputTextState];
}

- (void)connectionInfoSuccessfulConnection
{
	self.signInButton.hidden = YES;
	self.connectingIndicatorView.hidden = YES;
	self.connectionInfoView.hidden = NO;
	self.selectProjectStackView.hidden = NO;
	self.navigationItem.rightBarButtonItems = @[self.logOutButtonItem];

	UIColor* greenColor = [[UIColor alloc] initWithRed:51 / 255.0 green:170 / 255.0 blue:121 / 255.0 alpha:1.0];
	self.connectionInfoImageView.image = [UIImage imageNamed:@"success"];
	[self.connectionInfoLabel setTextColor:greenColor];
	self.connectionInfoLabel.text = NSLocalizedString(@"SuccessfulConnection", nil);

	self.reconnectButton.hidden = NO;
	self.reconnectButton.enabled = [self checkRequiredTextFieldsFilled];

	[self setInputTextDisabled];
}

- (void)connectionInfoEnterPassword
{
	self.signInButton.hidden = YES;
	self.connectingIndicatorView.hidden = YES;
	self.connectionInfoView.hidden = NO;
	self.selectProjectStackView.hidden = NO;
	self.navigationItem.rightBarButtonItems = @[self.logOutButtonItem];

	self.connectionInfoImageView.image = [UIImage imageNamed:@"warning"];
	[self.connectionInfoLabel setTextColor:UIColor.blackColor];
	self.connectionInfoLabel.text = NSLocalizedString(@"EnterPasswordToChangeProject", nil);

	self.reconnectButton.hidden = NO;
	self.reconnectButton.enabled = [self checkRequiredTextFieldsFilled];

	[self setInputTextDisabled];
}

- (void)connectionInfoNoProjects
{
	self.signInButton.hidden = YES;
	self.connectingIndicatorView.hidden = YES;
	self.connectionInfoView.hidden = NO;
	self.selectProjectStackView.hidden = YES;
	self.navigationItem.rightBarButtonItems = @[self.logOutButtonItem];

	self.connectionInfoImageView.image = [UIImage imageNamed:@"warning"];
	[self.connectionInfoLabel setTextColor:UIColor.blackColor];
	self.connectionInfoLabel.text = NSLocalizedString(@"NoProjectsFound", nil);

	self.reconnectButton.hidden = NO;
	self.reconnectButton.enabled = [self checkRequiredTextFieldsFilled];

	[self refreshInputTextState];
}

- (void)refreshInputTextState
{
	NSUserDefaults* userDefaults = NSUserDefaults.standardUserDefaults;
	if(userDefaults.authorized) {
		[self setInputTextDisabled];
	} else {
		[self setInputTextEnabled];
	}
}

- (void)setInputTextEnabled
{
	[self setInputTextColor:UIColor.blackColor];

	self.urlTextField.enabled = YES;
	self.tenantTextField.enabled = YES;
	self.usernameTextField.enabled = YES;

	self.urlLockImageView.hidden = YES;
	self.tenantLockImageView.hidden = YES;
	self.usernameLockImageView.hidden = YES;
}

- (void)setInputTextDisabled
{
	UIColor* grayColor = [[UIColor alloc] initWithRed:60 / 255.0 green:60 / 255.0 blue:67 / 255.0 alpha:0.3];
	[self setInputTextColor:grayColor];

	self.urlTextField.enabled = NO;
	self.tenantTextField.enabled = NO;
	self.usernameTextField.enabled = NO;

	self.urlLockImageView.hidden = NO;
	self.tenantLockImageView.hidden = NO;
	self.usernameLockImageView.hidden = NO;
}

- (void)setInputTextColor:(UIColor*)color
{
	self.urlTextField.textColor = color;
	self.tenantTextField.textColor = color;
	self.usernameTextField.textColor = color;
}

#pragma mark - TextFields notifications

// Called when the UIControlEventEditingChanged is sent
- (void)textFieldDidChange:(UITextField*)textField
{
	switch(self.currentConnectionState) {
		case ConnectionStateWaitingForData:
		case ConnectionStateReadyToConnection:
			self.currentConnectionState = [self checkRequiredTextFieldsFilled] ? ConnectionStateReadyToConnection : ConnectionStateWaitingForData;
			break;
		case ConnectionStateConnectingInProgress:
			// Do nothing: text editing should be disabled during connection
			break;
		case ConnectionStateSuccessfulConnection:
		case ConnectionStateNoConnection:
		case ConnectionStateEnterPassword:
		case ConnectionStateNoProjects:
			// refresh UI
			self.currentConnectionState = self.currentConnectionState;
			break;
	}
}

// Called when the UIControlEventEditingDidBegin is sent
- (void)textFieldEditingDidBegin:(UITextField*)textField
{
	self.activeTextField = textField;
}

#pragma mark - keyboard

- (void)hideKeyboard
{
	// refresh current UI state
	self.currentConnectionState = self.currentConnectionState;

	[self.scrollView endEditing:YES];
}

- (void)textFieldDidEndEditing:(UITextField*)textField
{
	if(textField != self.passwordTextField) {
		textField.text = [textField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	}
}

- (BOOL)textFieldShouldReturn:(UITextField*)textField
{
	if(textField == self.urlTextField) {
		[self.tenantTextField becomeFirstResponder];
	} else if(textField == self.tenantTextField) {
		[self.usernameTextField becomeFirstResponder];
	} else if(textField == self.usernameTextField) {
		[self.passwordTextField becomeFirstResponder];
	} else if(textField == self.passwordTextField) {
		[textField resignFirstResponder];
		[self signIn];
	} else {
		[textField resignFirstResponder];
	}

	return YES;
}

// Called when the UIKeyboardDidShowNotification is sent.
- (void)keyboardWasShown:(NSNotification*)aNotification
{
	NSDictionary* info = [aNotification userInfo];
	CGSize kbSize = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue].size;

	UIEdgeInsets contentInsets = UIEdgeInsetsMake(0.0, 0.0, kbSize.height, 0.0);
	self.scrollView.contentInset = contentInsets;
	self.scrollView.scrollIndicatorInsets = contentInsets;

	// If activeTextField is overlaped by keyboard, scroll to make it visible
	CGRect aRect = self.view.frame;
	aRect.size.height -= kbSize.height;
	if(!CGRectContainsPoint(aRect, self.activeTextField.frame.origin)) {
		[self.scrollView scrollRectToVisible:self.activeTextField.frame animated:YES];
	}
}

// Called when the UIKeyboardWillHideNotification is sent
- (void)keyboardWillBeHidden:(NSNotification*)aNotification
{
	UIEdgeInsets contentInsets = UIEdgeInsetsZero;
	self.scrollView.contentInset = contentInsets;
	self.scrollView.scrollIndicatorInsets = contentInsets;
}

@end
