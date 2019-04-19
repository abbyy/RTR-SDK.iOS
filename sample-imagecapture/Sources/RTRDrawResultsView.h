/// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
/// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

#import <UIKit/UIKit.h>

@class RTRQualityAssessmentForOCRBlock;

/// View to draw results.
@interface RTRDrawResultsView : UIView

/// Image size, to scale coordinates.
@property (nonatomic, assign) CGSize imageBufferSize;
/// Found document boundary.
@property (nonatomic, strong) NSArray<NSValue*>* documentBoundary;
/// Quality assessment blocks.
@property (nonatomic, strong) NSArray<RTRQualityAssessmentForOCRBlock*>* blocks;

/// Clear view.
- (void)clear;

@end
