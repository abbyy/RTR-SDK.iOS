/// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
/// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

#import "RTRDrawResultsView.h"

#import <AbbyyRtrSDK/AbbyyRtrSDK.h>

@implementation RTRDrawResultsView {
	/// The background color for the rest of the screen outside the document boundary.
	UIColor* _areaFogColor;
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
	_areaFogColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
	self.exclusiveTouch = YES;
}

- (void)drawRect:(CGRect)rect
{
	[super drawRect:rect];

	CGContextRef currentContext = UIGraphicsGetCurrentContext();

	CGContextSaveGState(currentContext);
	CGContextTranslateCTM(currentContext, 0, 0);
	CGContextScaleCTM(currentContext, CGRectGetWidth(self.bounds) / self.imageBufferSize.width,
		CGRectGetHeight(self.bounds) / self.imageBufferSize.height);

	[self drawBlocksInContext:currentContext];
	[self drawFogOverDocumentInContext:currentContext];

	CGContextRestoreGState(currentContext);
}

- (void)drawBlocksInContext:(CGContextRef)context
{
	CGContextSaveGState(context);
	CGContextRef currentContext = UIGraphicsGetCurrentContext();

	if(self.documentBoundary.count != 0) {
		[self addPathForDocumentBoundaryToContext:currentContext];
		CGContextClip(currentContext);
	}

	for(RTRQualityAssessmentForOCRBlock* block in self.blocks) {
		UIColor* color = nil;
		BOOL fillRect = NO;
		switch(block.type) {
			case RTRQualityAssessmentForOCRTextBlock:
				color = [UIColor colorWithRed:((100.f - block.quality) / 100.f) green:(block.quality / 100.f) blue:0 alpha:0.4f];
				fillRect = YES;
				break;
			case RTRQualityAssessmentForOCRUnknownBlock:
				color = [[UIColor lightGrayColor] colorWithAlphaComponent:0.2f];
				break;
			default:
				break;
		}
		if(color != nil) {
			[self drawImageQuadrangle:block.rect color:color fill:fillRect context:currentContext];
		}
	}

	CGContextRestoreGState(context);
}

- (void)addPathForDocumentBoundaryToContext:(CGContextRef)context
{
	NSArray* boundary = self.documentBoundary;
	CGPoint firstPoint = [boundary.firstObject CGPointValue];
	CGContextMoveToPoint(context, firstPoint.x, firstPoint.y);
	for(NSValue* obj in boundary) {
		CGContextAddLineToPoint(context, obj.CGPointValue.x, obj.CGPointValue.y);
	}

	CGContextClosePath(context);
}

- (void)drawImageQuadrangle:(CGRect)blockRect color:(UIColor*)color fill:(BOOL)fill context:(CGContextRef)context
{
	CGContextSetStrokeColorWithColor(context, color.CGColor);
	CGContextStrokeRect(context, blockRect);
	if(fill) {
		CGContextSetFillColorWithColor(context, color.CGColor);
		CGContextFillRect(context, blockRect);
	}
}

- (void)drawFogOverDocumentInContext:(CGContextRef)context
{
	if(self.documentBoundary.count == 0) {
		return;
	}
	CGContextSaveGState(context);

	CGRect scaledBounds = CGRectMake(0, 0, self.imageBufferSize.width, self.imageBufferSize.height);

	CGContextAddRect(context, scaledBounds);
	[self addPathForDocumentBoundaryToContext:context];
	CGContextEOClip(context);

	// Fill the background outside the area of interest
	CGContextSetFillColorWithColor(context, _areaFogColor.CGColor);
	CGContextFillRect(context, scaledBounds);

	CGContextRestoreGState(context);
}

- (void)clear
{
	self.blocks = nil;
	self.documentBoundary = nil;

	[self setNeedsDisplay];
}

@end
