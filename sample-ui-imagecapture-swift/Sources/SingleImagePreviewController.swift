// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

import UIKit

protocol SingleImagePreviewControllerDelegate {
	func onRejectPage(
		according previewController: SingleImagePreviewController,
		sender: Any?)
	func onConfirmPage(
		according previewController: SingleImagePreviewController,
		sender: Any?)
}

class SingleImagePreviewController: UIViewController {

	@IBOutlet weak var imageView: UIImageView!

	var delegate: SingleImagePreviewControllerDelegate?
	var image: UIImage!
	var pageNumber: Int?

	override var prefersStatusBarHidden: Bool {
		return false
	}

	override func viewDidLoad()
	{
		super.viewDidLoad()
		imageView.contentMode = .scaleAspectFit
		imageView.image = image
	}

	override func viewWillAppear(_ animated: Bool)
	{
		super.viewWillAppear(animated)
		setupNavigationBar()
	}

	func setupNavigationBar()
	{
		navigationController?.setNavigationBarHidden(false, animated: true)
		navigationController?.navigationBar.barStyle = .black
		let cancelButton = UIBarButtonItem(
			title: "Delete".localized,
			style: .plain, 
			target: self, 
			action: #selector(onDeleteTapped))
		cancelButton.tintColor = .white
		navigationItem.title = "SinglePagePreviewTitle".localized
		navigationItem.leftBarButtonItem = cancelButton
	}

	@IBAction func onDoneTapped(sender: UIButton)
	{
		delegate?.onConfirmPage(according: self, sender: sender)
	}

	@objc func onDeleteTapped(sender: UIBarButtonItem)
	{
		delegate?.onRejectPage(according: self, sender: sender)
	}
}
