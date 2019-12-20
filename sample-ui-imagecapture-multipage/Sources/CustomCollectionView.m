/// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
/// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

#import "CustomCollectionView.h"

@implementation CustomCollectionView

- (void)reloadData
{
	[super reloadData];
	self.backgroundImageView.hidden = [self numberOfItemsInSection:0] > 0;
}

@end
