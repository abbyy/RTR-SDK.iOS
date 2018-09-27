// ABBYY® Real-Time Recognition SDK 1 © 2016 ABBYY Production LLC.
// ABBYY is either a registered trademark or a trademark of ABBYY Software Ltd.

import UIKit

final class RTRSelectedAreaView: UIView {
	
	private struct Constants {
		// Border thickness of capture zone
		static let AreaBorderThickness: CGFloat = 1.0
		// Background color
		static let AreaFogColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.7)
		// Border color of capture zone
		static let AreaBorderColor = UIColor(red: 0.3, green: 0.63, blue: 1, alpha: 0.5)
	}
	
	internal var selectedArea = CGRect.zero {
		didSet {
			DispatchQueue.main.async {
				self.setNeedsDisplay()
			}
		}
	}

	// MARK: - LifeCycle

	override init(frame: CGRect) {
		super.init(frame: frame)
		self.doInit()
	}

	required init?(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
		self.doInit()
	}

	// MARK: - Private

	private func doInit() {
		self.isExclusiveTouch = true
	}

	override func draw(_ rect: CGRect) {
		super.draw(rect)

		guard let currentContext = UIGraphicsGetCurrentContext() else {
			return
		}

		currentContext.saveGState()
		currentContext.translateBy(x: 0, y: 0)

		self.drawFogLayer(currentContext) 
		self.drawBorderLayer(currentContext) 

		currentContext.restoreGState()
	}

	private func drawFogLayer(_ context: CGContext) {
		context.saveGState()

		let scaledBounds = self.superview?.bounds ?? .zero

		// Fill the background
		context.setFillColor(Constants.AreaFogColor.cgColor)
		context.fill(scaledBounds)

		let intersection = self.selectedArea.intersection(scaledBounds)
		context.addRect(intersection)
		context.clip()
		context.clear(intersection)

		context.setFillColor(UIColor.clear.cgColor)
		context.fill(intersection)

		context.restoreGState() 
	}

	private func drawBorderLayer(_ context: CGContext) {
		// Draw the outline of the capture zone
		self.addPathForSelectedArea(context) 
		context.setStrokeColor(Constants.AreaBorderColor.cgColor)
		context.setLineWidth(Constants.AreaBorderThickness)
		context.drawPath(using: CGPathDrawingMode.stroke) 
	}

	private func addPathForSelectedArea(_ context: CGContext) {
		let origin = self.selectedArea.origin
		let width = self.selectedArea.width
		let height = self.selectedArea.height

		let points = [origin,
			CGPoint(x: origin.x + width, y: origin.y),
			CGPoint(x: origin.x + width, y: origin.y + height),
			CGPoint(x: origin.x, y: origin.y + height)]

		context.addLines(between: points) 
		context.closePath() 
	}
}
