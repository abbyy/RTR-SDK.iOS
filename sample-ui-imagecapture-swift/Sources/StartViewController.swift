// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

import AbbyyUI

class StartViewController: UIViewController {

	@IBOutlet weak var placeholderImageView: UIImageView!
	@IBOutlet weak var versionLabel: UILabel!
	@IBOutlet weak var sharePdfButton: UIButton!

	var capturedImage: UIImage? = nil {
		didSet {
			updateState()
		}
	}

	var captureController: AUICaptureController?
}

// MARK: UIViewController overrides & UI

extension StartViewController {
	override func viewDidLoad()
	{
		super.viewDidLoad()
		versionLabel.text = "Build Number: \(RecognitionEngine.version)"
		updateState()
	}

	override var supportedInterfaceOrientations: UIInterfaceOrientationMask
	{
		return .portrait
	}
}

// MARK: Actions

extension StartViewController {

	func updateState()
	{
		let hasImage = capturedImage != nil
		sharePdfButton.isHidden = !hasImage
		placeholderImageView.image = capturedImage ?? UIImage(named: "emptyCollection")
	}

	func presentCaptureController()
	{
		guard let engine = RecognitionEngine.shared else {
			let alert = UIAlertController(
				title: "SomethingWentWrong".localized,
				message: "InvalidLicenseMessage".localized,
				preferredStyle: .alert)
			alert.addAction(UIAlertAction(title: "OK".localized, style: .default))
			UIViewController.top?.present(alert, animated: true)
			return;
		}
		// Capture Controller Configuration
		captureController = AUICaptureController()
		guard let captureController = captureController else {
			return
		}
		captureController.modalPresentationStyle = .fullScreen

		// Create capture scenario using RTREngine
		let captureScenario = AUIImageCaptureScenario(engine: engine)

		// Configure capture scenario
		// Image will be cropped and quadrangle result will be nil
		captureScenario.cropEnabled = true

		// Send recognition callback to self
		// See "AUIImageCaptureScenarioDelegate implementation" section
		captureScenario.delegate = self

		// Bind capture scenario with capture controller
		captureController.captureScenario = captureScenario

		present(captureController, animated: true)
	}

	@IBAction func onScanNewDocumentTapped(sender: UIButton)
	{
		capturedImage = nil
		presentCaptureController()
	}

	@IBAction func onSharePdfTapped(sender: UIButton)
	{
		guard let capturedImage = capturedImage else {
			return
		}

		let activityViewController = UIActivityViewController(
			activityItems: [capturedImage],
			applicationActivities: nil)
		if let popover = activityViewController.popoverPresentationController {
			activityViewController.modalPresentationStyle = .popover
			popover.permittedArrowDirections = [.down, .up]
			popover.sourceView = sharePdfButton
		}
		present(activityViewController, animated: true, completion: nil)
	}
}

// MARK: AUIImageCaptureScenarioDelegate implementation

extension StartViewController: AUIImageCaptureScenarioDelegate & UINavigationControllerDelegate
{
	func captureScenario(_
		scenario: AUIImageCaptureScenario,
		didFailWithError error: Error)
	{
		let alert = UIAlertController(
			title: "SomethingWentWrong".localized,
			message: error.localizedDescription,
			preferredStyle: .alert)
		alert.addAction(UIAlertAction(
			title: "OK".localized,
			style: .cancel))
		UIViewController.top?.present(alert, animated: true, completion: { [weak self] in
			self?.captureController?.paused = true
		})
	}

	func captureScenario(_
		captureScenario: AUIImageCaptureScenario,
		didCaptureImageWith result: AUIImageCaptureResult)
	{
		let sb = UIStoryboard(name: "\(SingleImagePreviewController.self)", bundle: nil)
		if let vc = sb.instantiateInitialViewController() as? SingleImagePreviewController {
			vc.image = result.image
			vc.delegate = self
			captureController?.pushViewController(vc, animated: true)
		}
	}

	func captureScenarioDidCancel(_ scenario: AUICaptureScenario)
	{
		self.captureController?.dismiss(animated: true)
	}
}

// MARK: SingleImagePreviewControllerDelegate implementation

extension StartViewController: SingleImagePreviewControllerDelegate
{
	func onRejectPage(
		according previewController: SingleImagePreviewController,
		sender: Any?)
	{
		captureController?.popViewController(animated: true)
	}

	func onConfirmPage(
		according previewController: SingleImagePreviewController,
		sender: Any?)
	{
		capturedImage = previewController.image
		dismiss(animated: true)
	}
}
