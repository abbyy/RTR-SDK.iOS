/// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
/// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

#import "CustomButton.h"

@implementation CustomButton

- (void)setBackgroundColor:(UIColor*)backgroundColor
{
	[super setBackgroundColor:backgroundColor];
	self.customBackgroundColor = backgroundColor;
}

- (void)setHighlighted:(BOOL)highlighted
{
	[super setHighlighted:highlighted];
	if(highlighted) {
		super.backgroundColor = [self.customBackgroundColor colorWithAlphaComponent:0.6];
	} else {
		super.backgroundColor = self.customBackgroundColor;
	}
}

- (void)setSelected:(BOOL)selected
{
	[super setSelected:selected];
	if(selected) {
		super.backgroundColor = [self.customBackgroundColor colorWithAlphaComponent:0.6];
	} else {
		super.backgroundColor = self.customBackgroundColor;
	}
}

- (void)setEnabled:(BOOL)enabled
{
	[super setEnabled:enabled];
	if(!enabled) {
		super.backgroundColor = [self.customBackgroundColor colorWithAlphaComponent:0.2];
	} else {
		super.backgroundColor = self.customBackgroundColor;
	}
}

@end

@interface UIButton (Localization)

@property (nonatomic, strong) NSString* referenceText;

@end

@implementation UIButton (Localization)

- (NSString*)referenceText
{
	return self.titleLabel.text;
}

- (void)setReferenceText:(NSString*)referenceText
{
	[self setTitle:NSLocalizedString(referenceText, nil) forState:UIControlStateNormal];
}

@end
