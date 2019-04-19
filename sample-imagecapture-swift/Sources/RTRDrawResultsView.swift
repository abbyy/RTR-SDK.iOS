/// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
/// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

import AbbyyRtrSDK

class RTRDrawResultsView: UIView {
	/// The background color for the rest of the screen outside the document boundary.
	private let areaFogColor: UIColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.7)

	var documentBoundaryPoints : Array<CGPoint>? {
		get {
			guard let boundary = documentBoundary else {
				return nil
			}

			var result: Array<CGPoint> = []
			for pointValue in boundary {
				result.append(pointValue.cgPointValue)
			}
			return result
		}
	}

	/// Image size, to scale coordinates.
	var imageBufferSize: CGSize = CGSize.zero
	/// Found document boundary.
	var documentBoundary: Array<NSValue>? = nil
	/// Quality assessment blocks.
	var blocks: Array<RTRQualityAssessmentForOCRBlock>? = nil

// MARK: - LifeCycle

	override init(frame: CGRect)
	{
		super.init(frame: frame)
		self.doInit()
	}

	required init?(coder aDecoder: NSCoder)
	{
		super.init(coder: aDecoder)
		self.doInit()
	}

	/// Clear view.
	func clear()
	{
		documentBoundary = nil
		blocks = nil
		setNeedsDisplay()
	}

// MARK: - Private

	private func doInit()
	{
		isExclusiveTouch = true
	}

	override func draw(_ rect: CGRect)
	{
		super.draw(rect)

		if let currentContext = UIGraphicsGetCurrentContext() {
			currentContext.saveGState()
			currentContext.translateBy(x: 0, y: 0)
			currentContext.scaleBy(x: bounds.width / imageBufferSize.width, y: bounds.height / imageBufferSize.height)

			drawBlocks(context: currentContext)
			drawFogOverDocumentBoundary(context: currentContext)

			currentContext.restoreGState()
		}
	}

	private func drawBlocks(context: CGContext)
	{
		context.saveGState()

		if let currentContext: CGContext = UIGraphicsGetCurrentContext() {
			if let boundary = documentBoundary {
				if boundary.count != 0 {
					addPathForDocumentBoundary(context: currentContext)
					currentContext.clip()
				}
			}

			if let blocksToDraw = blocks {
				for block in blocksToDraw {
					var color: UIColor?
					var fillRect = false
					switch(block.type) {
						case .textBlock:
							color = UIColor.init(red: (1 - CGFloat(block.quality) / 100), green: CGFloat(block.quality) / 100, blue: 0, alpha: 0.4)
							fillRect = true
						case .unknownBlock:
							color = UIColor.lightGray.withAlphaComponent(0.2)
					}
					if let blockColor = color {
						drawBlock(rect: block.rect, color: blockColor, fill: fillRect, context: currentContext)
					}
				}
			}
		}
		context.restoreGState()
	}

	private func drawBlock(rect: CGRect, color: UIColor, fill: Bool, context: CGContext)
	{
		context.setStrokeColor(color.cgColor)
		context.stroke(rect)
		if fill {
			context.setFillColor(color.cgColor)
			context.fill(rect)
		}
	}

	private func drawFogOverDocumentBoundary(context: CGContext)
	{
		if let boundary = documentBoundary {
			if boundary.count == 0 {
				return
			}

			context.saveGState()
			let scaledBounds = CGRect.init(origin: CGPoint.zero, size: imageBufferSize)
			context.addRect(scaledBounds)
			addPathForDocumentBoundary(context: context)
			context.clip(using: CGPathFillRule.evenOdd)

			context.setFillColor(areaFogColor.cgColor)
			context.fill(scaledBounds)

			context.restoreGState()
		}
	}

	private func addPathForDocumentBoundary(context: CGContext)
	{
		addPathForPoints(context: context, points: documentBoundaryPoints)
	}

	private func addPathForPoints(context: CGContext!, points: Array<CGPoint>?)
	{
		if let _points = points {
			context.addLines(between: _points)
			context.closePath()
		}
	}
}
