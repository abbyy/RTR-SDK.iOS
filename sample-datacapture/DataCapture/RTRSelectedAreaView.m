// ABBYY® Real-Time Recognition SDK 1 © 2016 ABBYY Production LLC.
// ABBYY is either a registered trademark or a trademark of ABBYY Software Ltd.

#import "RTRSelectedAreaView.h"

#pragma mark - Constants

/// The area of interest border thickness.
static const CGFloat AreaBorderThickness = 1.f;

/// The background color for the rest of the screen outside the area of interest.
static const CGFloat CropFogRedColorComponent = 0.f;
static const CGFloat CropFogGreenColorComponent = 0.f;
static const CGFloat CropFogBlueColorComponent = 0.f;
static const CGFloat CropFogAlphaColorComponent = 0.7f;

/// The area of interest border color.
static const CGFloat CropBorderRedColorComponent = 1.f;
static const CGFloat CropBorderGreenColorComponent = 1.f;
static const CGFloat CropBorderBlueColorComponent = 1.f;
static const CGFloat CropBorderAlphaColorComponent = 0.5f;

@implementation RTRSelectedAreaView {
	/// Background color.
	UIColor* _areaFogColor;
	/// Border color.
	UIColor* _areaBorderColor;
}

- (id)initWithCoder:(NSCoder*)aDecoder
{
	self = [super initWithCoder:aDecoder];

	if(self != nil) {
		[self doInit];
	}
	
	return self;
}

- (id)initWithFrame:(CGRect)frame
{
	self = [super initWithFrame:frame];

	if(self != nil) {
		[self doInit];
	}

	return self;
}

- (void)doInit
{
	_areaFogColor = [UIColor colorWithRed:CropFogRedColorComponent green:CropFogGreenColorComponent
		blue:CropFogBlueColorComponent alpha:CropFogAlphaColorComponent];

	_areaBorderColor = [UIColor colorWithRed:CropBorderRedColorComponent green:
		CropBorderGreenColorComponent blue:CropBorderBlueColorComponent alpha:CropBorderAlphaColorComponent];

	self.exclusiveTouch = YES;
}

- (void)setSelectedArea:(CGRect)selectedArea
{
	_selectedArea = selectedArea;
	[self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect
{
	[super drawRect:rect];

	CGContextRef currentContext = UIGraphicsGetCurrentContext();

	CGContextSaveGState(currentContext);
	CGContextTranslateCTM(currentContext, 0, 0);

	[self drawFogLayerInContext:currentContext];
	[self drawBorderLayerInContext:currentContext];

	CGContextRestoreGState(currentContext);
}

- (void)drawFogLayerInContext:(CGContextRef)context
{
	CGContextSaveGState(context);

	CGRect scaledBounds = self.superview.bounds;

	CGContextAddRect(context, scaledBounds);
	[self addPathForSelectedAreaToContext:context];
	CGContextEOClip(context);

	// Fill the background outside the area of interest
	CGContextSetFillColorWithColor(context, _areaFogColor.CGColor);
	CGContextFillRect(context, scaledBounds);

	CGContextRestoreGState(context);
}

- (void)drawBorderLayerInContext:(CGContextRef)context
{
	// Draw the border of the area of interest
	[self addPathForSelectedAreaToContext:context];
	CGContextSetStrokeColorWithColor(context, _areaBorderColor.CGColor);
	CGContextSetLineWidth(context, AreaBorderThickness);
	CGContextDrawPath(context, kCGPathStroke);
}

- (void)addPathForSelectedAreaToContext:(CGContextRef)context
{
	CGPoint origin = self.selectedArea.origin;
	CGFloat width = CGRectGetWidth(self.selectedArea);
	CGFloat height = CGRectGetHeight(self.selectedArea);
	CGPoint points[] = {
		origin,
		CGPointMake(self.selectedArea.origin.x + width, origin.y),
		CGPointMake(self.selectedArea.origin.x + width, origin.y + height),
		CGPointMake(self.selectedArea.origin.x, origin.y + height)
	};

	CGContextAddLines(context, points, 4);
	CGContextClosePath(context);
}

@end
