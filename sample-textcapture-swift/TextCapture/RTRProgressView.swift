// ABBYY® Real-Time Recognition SDK 1 © 2016 ABBYY Production LLC.
// ABBYY is either a registered trademark or a trademark of ABBYY Software Ltd.

import Foundation

@IBDesignable
class RTRProgressView: UIView {
	
	@IBOutlet weak var view: UIView?
	
	required init?(coder aDecoder: NSCoder)
	{
		super.init(coder: aDecoder)
		self.doInitRoutine()
	}
	
	required override init(frame: CGRect)
	{
		super.init(frame: frame)
		self.doInitRoutine()
	}
	
	public func setProgress(_ progress: Int, _ color: UIColor)
	{
		guard let rings = self.view?.subviews else {
			return
		}
		
		rings.enumerated().forEach { (index, view) in
			view.backgroundColor = (index + 1 <= progress) ? color : .clear
			view.layer.borderColor = color.cgColor
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
		guard let views = self.currentBundle.loadNibNamed(className, owner: self, options: nil)
			, let view = views.first as? UIView else {
				print("View not loaded")
				return
		}
		
		self.addSubview(view)
		let viewsDic = ["view": view]
		
		let horizontalConstraints = NSLayoutConstraint.constraints(withVisualFormat: "H:|-0-[view]-0-|", metrics: nil, views: viewsDic)
		let verticalConstraints = NSLayoutConstraint.constraints(withVisualFormat: "V:|-0-[view]-0-|", metrics: nil, views: viewsDic)
		view.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate(horizontalConstraints + verticalConstraints)
		
		self.view = view
	}

}
