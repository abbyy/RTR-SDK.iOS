// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

import UIKit

extension String {
	var localized: String {
		return NSLocalizedString(self, comment: "")
	}
}

extension UIButton {
	@IBInspectable public var referenceText: String? {
		get {
			return titleLabel?.text
		}
		set(value) {
			setTitle(value?.localized, for: .normal)
		}
	}
}
