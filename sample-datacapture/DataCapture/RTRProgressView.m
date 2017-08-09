// ABBYY® Real-Time Recognition SDK 1 © 2016 ABBYY Production LLC.
// ABBYY is either a registered trademark or a trademark of ABBYY Software Ltd.

#import "RTRProgressView.h"

@interface RTRProgressView ()

@property (nonatomic, weak) IBOutlet UIView* view;

@end

@implementation RTRProgressView

- (instancetype)initWithCoder:(NSCoder*)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if(self != nil) {
		[self doInitRoutine];
	}
	return self;
}

- (instancetype)initWithFrame:(CGRect)frame
{
	self = [super initWithFrame:frame];
	if(self != nil) {
		[self doInitRoutine];
	}
	return self;
}

- (void)doInitRoutine
{
	NSString* className = NSStringFromClass([self class]);
	self.view = [[[self currentBundle] loadNibNamed:className owner:self options:nil] firstObject];

	NSAssert(self.view != nil, nil);
	[self addSubview:self.view];

	NSDictionary* views = @{ @"view" : self.view };
	NSArray* horizontalConstraints = [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-0-[view]-0-|" options:0 metrics:nil views:views];

	NSArray* verticalConstraints = [NSLayoutConstraint constraintsWithVisualFormat:@"V:|-0-[view]-0-|" options:0 metrics:nil views:views];
	self.view.translatesAutoresizingMaskIntoConstraints = NO;

	[NSLayoutConstraint activateConstraints:horizontalConstraints];
	[NSLayoutConstraint activateConstraints:verticalConstraints];
}

- (NSBundle*)currentBundle
{
#if !TARGET_INTERFACE_BUILDER
	return [NSBundle mainBundle];
#else
	return [NSBundle bundleForClass:[self class]];
#endif
}

- (void)setProgress:(NSInteger)progress color:(UIColor*)color
{
	NSArray<UIView*>* rings = self.view.subviews;
	[rings enumerateObjectsUsingBlock:^(UIView* obj, NSUInteger idx, BOOL* stop) {
		obj.backgroundColor = (idx + 1 <= progress) ? color : [UIColor clearColor];
		obj.layer.borderColor = color.CGColor;
	}];
}

@end
