// ABBYY® Real-Time Recognition SDK 1 © 2016 ABBYY Production LLC.
// ABBYY is either a registered trademark or a trademark of ABBYY Software Ltd.

import Foundation

@IBDesignable
class RTRProgressView: UIView {
	
	@IBOutlet weak var view: UIView?
	
	required init?(coder aDecoder: NSCoder)
	{
		super.init(coder: aDecoder)
		self.doInitRoutine();
	}
	
	required override init(frame: CGRect)
	{
		super.init(frame: frame)
		self.doInitRoutine();
	}
	
	public func setProgress(_ progress: Int, _ color:UIColor)
	{
		if let rings = self.view?.subviews {
			for (index, view) in rings.enumerated() {
				view.backgroundColor = (index + 1 <= progress) ? color : UIColor.clear
				view.layer.borderColor = color.cgColor
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
		let views = self.currentBundle.loadNibNamed(className, owner: self, options: nil)
		self.view = views!.first as? UIView
		
		assert(self.view != nil, "Check is view loaded")
		
		if let view = self.view {
			self.addSubview(view)
			let views: [String : Any] = ["view": view]
			
			let horizontalConstraints = NSLayoutConstraint.constraints(withVisualFormat: "H:|-0-[view]-0-|", metrics: nil, views: views)
			let verticalConstraints = NSLayoutConstraint.constraints(withVisualFormat: "V:|-0-[view]-0-|", metrics: nil, views: views)
			view.translatesAutoresizingMaskIntoConstraints = false
			NSLayoutConstraint.activate(horizontalConstraints)
			NSLayoutConstraint.activate(verticalConstraints)
		}

	}

}
