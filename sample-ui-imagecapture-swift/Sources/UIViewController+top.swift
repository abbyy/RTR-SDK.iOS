// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

import UIKit

extension UIViewController {
	class var top: UIViewController? {
		var topController = UIApplication.shared.keyWindow?.rootViewController
		while ((topController?.presentedViewController) != nil) {
			topController = topController?.presentedViewController!
		}
		return topController
	}
}
