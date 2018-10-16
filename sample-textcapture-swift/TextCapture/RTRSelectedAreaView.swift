// ABBYY® Real-Time Recognition SDK 1 © 2016 ABBYY Production LLC.
// ABBYY is either a registered trademark or a trademark of ABBYY Software Ltd.

import UIKit

class RTRSelectedAreaView: UIView {
	/// Border thickness of capture zone
	private let AreaBorderThickness : CGFloat = 1.0
	/// Background color
	private let AreaFogColor: UIColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.7)
	/// Border color of capture zone
	private let AreaBorderColor: UIColor = UIColor(red: 1, green: 1, blue: 1, alpha: 0.5)

	internal var selectedArea: CGRect = CGRect.zero {
		didSet {
			weak var weakSelf = self
			DispatchQueue.main.async {
				if let strongSelf = weakSelf {
					strongSelf.setNeedsDisplay()
				}
			}
		}
	}

//# MARK: - LifeCycle

	override init(frame: CGRect) {
		super.init(frame: frame)
		doInit()
	}

	required init?(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
		doInit()
	}

//# MARK: - Private

	private func doInit() {
		isExclusiveTouch = true
	}

	override func draw(_ rect: CGRect) {
		super.draw(rect)

		if let currentContext = UIGraphicsGetCurrentContext() {
			currentContext.saveGState()
			currentContext.translateBy(x: 0, y: 0)

			drawFogLayer(currentContext)
			drawBorderLayer(currentContext)

			currentContext.restoreGState()
		}
	}

	private func drawFogLayer(_ context: CGContext) {
		context.saveGState()

		if let superview = self.superview {
			let scaledBounds = superview.bounds

			// Fill the background
			context.setFillColor(AreaFogColor.cgColor)
			context.fill(scaledBounds)

			let intersection = selectedArea.intersection(scaledBounds)
			context.addRect(intersection)
			context.clip()
			context.clear(intersection)

			context.setFillColor(UIColor.clear.cgColor)
			context.fill(intersection)

			context.restoreGState()
		}
	}

	private func drawBorderLayer(_ context: CGContext) {
		// Draw the outline of the capture zone
		addPathForSelectedArea(context)
		context.setStrokeColor(AreaBorderColor.cgColor) 
		context.setLineWidth(AreaBorderThickness) 
		context.drawPath(using: CGPathDrawingMode.stroke) 
	}

	private func addPathForSelectedArea(_ context: CGContext) {
		let origin = selectedArea.origin
		let width = selectedArea.width
		let height = selectedArea.height

		let points = [origin,
			CGPoint.init(x: selectedArea.origin.x + width, y: origin.y),
			CGPoint.init(x: selectedArea.origin.x + width, y: origin.y + height),
			CGPoint.init(x: selectedArea.origin.x, y: origin.y + height)]

		context.addLines(between: points) 
		context.closePath() 
	}
}
