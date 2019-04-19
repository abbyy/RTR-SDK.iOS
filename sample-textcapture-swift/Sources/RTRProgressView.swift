// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

import Foundation
import AbbyyRtrSDK

@IBDesignable
class RTRProgressView: UIView {

	@IBOutlet weak var view: UIView?

	required init?(coder aDecoder: NSCoder)
	{
		super.init(coder: aDecoder)
		doInitRoutine();
	}

	required override init(frame: CGRect)
	{
		super.init(frame: frame)
		doInitRoutine();
	}

	public func setProgress(_ progress: Int, _ color:UIColor)
	{
		if let view = self.view {
			let rings = view.subviews
			for (index, ring) in rings.enumerated() {
				ring.backgroundColor = (index + 1 <= progress) ? color : .clear
				ring.layer.borderColor = color.cgColor
			}
		}
	}

	public var currentBundle: Bundle {
		#if !TARGET_INTERFACE_BUILDER
			return Bundle.main
		#else
			return Bundle(for: type(of: self))
		#endif
	}

	public func doInitRoutine()
	{
		let className = NSStringFromClass(type(of: self))
		let views = currentBundle.loadNibNamed(className, owner: self, options: nil)
		view = views!.first as? UIView

		assert(view != nil, "Check is view loaded")

		if let view = self.view {
			addSubview(view)
			let views: [String : Any] = ["view": view]
			let horizontalConstraints = NSLayoutConstraint.constraints(withVisualFormat: "H:|-0-[view]-0-|", metrics: nil, views: views)
			let verticalConstraints = NSLayoutConstraint.constraints(withVisualFormat: "V:|-0-[view]-0-|", metrics: nil, views: views)
			view.translatesAutoresizingMaskIntoConstraints = false
			NSLayoutConstraint.activate(horizontalConstraints)
			NSLayoutConstraint.activate(verticalConstraints)
		}
	}

}
