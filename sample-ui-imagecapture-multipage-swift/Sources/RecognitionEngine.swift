// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

import UIKit
import AbbyyRtrSDK

/// Wrapper class to get access to Mobile Capture SDK
class RecognitionEngine {
	static var shared: RTREngine? = {
		// Provide path to ABBYY license file to initialize RTR engine
		let licensePath = URL(fileURLWithPath: Bundle.main.bundlePath)
			.appendingPathComponent("license")
		if let data = try? Data(contentsOf: licensePath) {
			return RTREngine.sharedEngine(withLicense: data)
		}
		return .none
	}()

	static var version: String {
		let sdkInfo = Bundle(for: RTREngine.self).infoDictionary
		let versionKey = "CFBundleVersion"
		return sdkInfo?[versionKey] as? String ?? "Unknown"
	}

	private init() {}
}
