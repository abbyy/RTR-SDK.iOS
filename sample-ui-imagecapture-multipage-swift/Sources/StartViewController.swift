// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

import AbbyyUI

class ImageCollectionViewCell: UICollectionViewCell {
	var imageView: UIImageView? {
		willSet {
			imageView?.removeFromSuperview()
		}
		didSet {
			if let imageView = imageView {
				imageView.contentMode = .scaleAspectFill
				contentView.addSubview(imageView)
			}
		}
	}

	override func prepareForReuse()
	{
		super.prepareForReuse()
		imageView = nil
	}
}

struct Profile: Equatable {
	let name: String
	let requiredPageCount: UInt
	let documentSize: AUIDocumentSize
	let minAspectRatio: CGFloat
	let maxAspectRatio: CGFloat
}

extension Profile {
	/// BusinessCard.
	static var businessCard: Profile {
		return Profile(name: "One Business Card", requiredPageCount: 1, documentSize: .businessCard, minAspectRatio: 1.38, maxAspectRatio: 2.09)
	}

	/// A4 document.
	static var a4Document: Profile {
		return Profile(name: "A4 Document", requiredPageCount: 0, documentSize: .A4, minAspectRatio: 0, maxAspectRatio: 0)
	}

	/// Unknown document set.
	static var unknownDocument: Profile {
		return Profile(name: "Unknown Set", requiredPageCount: 0, documentSize: .any, minAspectRatio: 1, maxAspectRatio: CGFloat.infinity)
	}
}

class StartViewController: UIViewController {

	var engine: RTREngine!
	let dataStorage = DataStorage()
	var scenario: AUIMultiPageImageCaptureScenario? {
		didSet {
			updateResult()
		}
	}

	@IBOutlet weak var addPagesButton: UIButton!
	@IBOutlet weak var placeholderImageView: UIImageView!
	@IBOutlet weak var versionLabel: UILabel!
	@IBOutlet weak var sharePdfButton: UIButton!

	@IBOutlet weak var profilesControl: UISegmentedControl!

	private let profiles: [Profile] = [.unknownDocument, .a4Document, .businessCard]

	fileprivate let minPointsPerItem = 88

	var columnsCount: Int {
		return Int(UIScreen.main.bounds.width) / minPointsPerItem
	}

	@IBOutlet weak var pagesCollection: UICollectionView!
	var collectionCellsInset: CGFloat = 2

	var captureController: AUICaptureController?
	var capturedCountOnCurrentSession = 0
}

// MARK: - UIViewController overrides & UI

extension StartViewController {
	override func viewDidLoad()
	{
		super.viewDidLoad()
		addPagesButton.isHidden = true
		sharePdfButton.isHidden = true
		pagesCollection.delegate = self
		pagesCollection.dataSource = self
		versionLabel.text = "Build Number: \(RecognitionEngine.version)"

		let recognizer = UITapGestureRecognizer(target: self, action: #selector(StartViewController.onPageTap))
		pagesCollection.addGestureRecognizer(recognizer)

		profilesControl.addTarget(self, action: #selector(StartViewController.onProfileChanged), for: .valueChanged)
		profilesControl.removeAllSegments()
		for profile in profiles {
			profilesControl.insertSegment(withTitle: profile.name.localized, at: profilesControl.numberOfSegments, animated: false)
		}
		profilesControl.selectedSegmentIndex = 0
		profilesControl.apportionsSegmentWidthsByContent = true

		dataStorage.errorHandler = { [weak self] error in
			self?.showAlert(with: error)
		}
	}

	override func viewDidAppear(_ animated: Bool)
	{
		super.viewDidAppear(animated)

		if RecognitionEngine.shared == nil {
			showLicenseError()
			return
		} else {
			engine = RecognitionEngine.shared
		}

		if scenario == nil {
			onProfileChanged(sender: profilesControl)
		}
	}

	override var supportedInterfaceOrientations: UIInterfaceOrientationMask
	{
		return .portrait
	}

	func showLicenseError()
	{
		let alert = UIAlertController(title: nil, message: "InvalidLicenseMessage".localized, preferredStyle: .alert)
		UIViewController.top?.present(alert, animated: true)
	}

	func showAlert(with error: Error)
	{
		let alert = UIAlertController(title: "SomethingWentWrong".localized, message: error.localizedDescription, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
		UIViewController.top?.present(alert, animated: true)
	}

	func updateResult()
	{
		dataStorage.capturedImages = scenario?.result
		updateState()
	}

	func updateState()
	{
		let hasCapturedFrames = dataStorage.itemsCount > 0

		addPagesButton.isHidden = !hasCapturedFrames
		sharePdfButton.isHidden = !hasCapturedFrames
		placeholderImageView.isHidden = hasCapturedFrames
		pagesCollection.reloadData()
	}
}

// MARK: - Actions

extension StartViewController {

	func presentCaptureController()
	{
		// Create capture controller
		captureController = AUICaptureController()
		guard let captureController = captureController else {
			return
		}

		// Bind capture scenario with capture controller
		captureController.captureScenario = scenario
		captureController.modalPresentationStyle = .fullScreen

		present(captureController, animated: true)
	}

	@IBAction func onScanNewDocumentTapped(sender: UIButton)
	{
		do {
			if let scenario = scenario {
				/// Remove all data for old result
				try scenario.result.clear()
			}
			/// New scenario for new document
			scenario = try createScenario()
			presentCaptureController()
		} catch {
			showAlert(with: error)
		}
	}

	@IBAction func onAddPagesTapped(sender: UIButton)
	{
		presentCaptureController()
	}

	@IBAction func onSharePdfTapped(sender: UIButton)
	{
		func prettyFileName() -> String
		{
			let currentDate = Date()
			let formatter = DateFormatter()
			formatter.dateStyle = .medium
			formatter.timeStyle = .medium
			let dateString = formatter.string(from: currentDate)
			return "ImageCapture - \(dateString).pdf"
		}

		func showExportErrorWarning(with error: Error)
		{
			let alert = UIAlertController(
				title: "SomethingWentWrong".localized,
				message: String.localizedStringWithFormat(
					"PdfExportWithError".localized, "\(error)"),
				preferredStyle: .alert)
			alert.addAction(UIAlertAction(title: "Ok".localized, style: .default))
			UIViewController.top?.present(alert, animated: true)
		}

		let pdfFileName = prettyFileName()
		let progressAlert = UIAlertController(
			title: "ExportInProgress".localized,
			message: "",
			preferredStyle: .alert)
		let exportingProgressCallack: (ImageExporter.PdfExportStatus) -> Void = { status in
			DispatchQueue.main.async {
				progressAlert.message = "\(status.currentAction.rawValue.capitalized): \(status.pagesProcessed) / \(status.pagesCount).."
			}
		}

		self.present(progressAlert, animated: true)

		DispatchQueue.global(qos: .default).async { [weak self] in
			do {
				guard let self = self else {
					return
				}
				try self.dataStorage.exportAsPdf(filename: pdfFileName, progress: exportingProgressCallack)
				DispatchQueue.main.async {
					let pdfFilePath = self.dataStorage
						.exporter
						.tmpDirectory
						.appendingPathComponent(pdfFileName)
					progressAlert.dismiss(animated: true, completion: {
						self.showShareController(with: [pdfFilePath], sourceView: self.sharePdfButton)
					})
				}
			} catch {
				DispatchQueue.main.async {
					self?.dismiss(animated: true, completion: {
						showExportErrorWarning(with: error)
					})
				}
			}
		}
	}

	@objc func onPageTap(recognizer: UITapGestureRecognizer!)
	{
		if recognizer.state != .ended {
			return
		}

		let point = recognizer.location(in: pagesCollection)
		guard let indexPath = pagesCollection.indexPathForItem(at: point) else {
			return
		}

		let alert = UIAlertController(
			title: nil,
			message: nil,
			preferredStyle: .actionSheet)
		alert.addAction(UIAlertAction(title: "Open Page".localized, style: .default, handler: { action in
			self.openPage(index: indexPath)
		}))
		alert.addAction(UIAlertAction(title: "Share Page".localized, style: .default, handler: { action in
			self.sharePage(index: indexPath)
		}))
		alert.addAction(UIAlertAction(title: "Delete Page".localized, style: .destructive, handler: { action in
			self.deletePage(index: indexPath)
		}))
		alert.addAction(UIAlertAction(title: "Cancel".localized, style: .cancel))
		if let popover = alert.popoverPresentationController {
			alert.modalPresentationStyle = .popover
			popover.permittedArrowDirections = [.down, .up]
			if let cell = pagesCollection.cellForItem(at: indexPath) {
				popover.sourceView = cell
			}
		}
		UIViewController.top?.present(alert, animated: true)
	}

	func openPage(index: IndexPath)
	{
		scenario?.startAsEditorAtPageId = dataStorage.imagesIdentifiers[index.row]
		presentCaptureController()
	}

	func showShareController(with items: [Any], sourceView: UIView)
	{
		let activityViewController = UIActivityViewController(
			activityItems: items,
			applicationActivities: nil)
		if let popover = activityViewController.popoverPresentationController {
			activityViewController.modalPresentationStyle = .popover
			popover.permittedArrowDirections = [.down, .up]
			popover.sourceView = sourceView
		}

		present(activityViewController, animated: true, completion: nil)
	}

	func sharePage(index: IndexPath)
	{
		let progressAlert = UIAlertController(
			title: "ExportInProgress".localized,
			message: "",
			preferredStyle: .alert)

		self.present(progressAlert, animated: true)

		let imageLoader = dataStorage.fetchResultImage(at: index.row)
		imageLoader.loadingCompleteHandler = { [weak self] image in
			progressAlert.dismiss(animated: true, completion: {
				if let image = image {
					if let cell = self?.pagesCollection.cellForItem(at: index) {
						self?.showShareController(with: [image], sourceView: cell)
					}
				}
			})
		}
		dataStorage.loadingQueue.addOperation(imageLoader)
	}

	func deletePage(index: IndexPath)
	{
		let operation = dataStorage.remove(at: index.row)
		operation.completionBlock = {
			DispatchQueue.main.async { [weak self] in
				self?.pagesCollection.deleteItems(at: [index])
				self?.updateState()
			}
		}
		dataStorage.loadingQueue.addOperation(operation)
	}

	func createScenario() throws -> AUIMultiPageImageCaptureScenario
	{
		let profile = profiles[profilesControl.selectedSegmentIndex]
		// Create capture scenario using RTREngine and default page storage
		let storageURL = dataStorage.directoryURL.appendingPathComponent(profile.name)
		let imageCaptureScenario = try AUIMultiPageImageCaptureScenario(engine: engine, storagePath: storageURL.path)
		imageCaptureScenario.delegate = self
		if profile != .unknownDocument {
			imageCaptureScenario.captureSettings = self
		}
		imageCaptureScenario.requiredPageCount = profile.requiredPageCount
		return imageCaptureScenario
	}

	@objc func onProfileChanged(sender: UISegmentedControl!)
	{
		do {
			scenario = try createScenario()
		} catch {
			showAlert(with: error)
		}
	}
}

// MARK: - AUIMultiImageCaptureScenarioDelegate implementation

extension StartViewController: AUIMultiPageImageCaptureScenarioDelegate & UINavigationControllerDelegate
{
	func captureScenario(_ captureScenario: AUIMultiPageImageCaptureScenario, didFinishWith result: AUIMultiPageImageCaptureResult)
	{
		updateResult()
		captureController?.dismiss(animated: true)
	}

	func captureScenario(_ captureScenario: AUIMultiPageImageCaptureScenario, onCloseWith result: AUIMultiPageImageCaptureResult)
	{
		do {
			if try result.pages().count == 0 {
				updateResult()
				captureController?.dismiss(animated: true)
				return
			}
		} catch {
			showAlert(with: error)
			return
		}

		self.captureController?.setPaused(true, animated: true)
		let alert = UIAlertController(
			title: "DectructiveActionWarning".localized,
			message: "AllPagesOnCurrentSessionWillBeDeletedWarning".localized,
			preferredStyle: .alert)
		alert.addAction(UIAlertAction(
			title: "Cancel".localized,
			style: .cancel,
			handler: { action in
				self.captureController?.setPaused(false, animated: true)
			}))
		alert.addAction(UIAlertAction(
			title: "Confirm".localized,
			style: .destructive,
			handler: { action in
				do {
					try result.clear()
					self.updateResult()
					self.captureController?.dismiss(animated: true)
				} catch {
					self.showAlert(with: error)
				}
			}))
		UIViewController.top?.present(alert, animated: true)
	}

	func captureScenario(_ captureScenario: AUIMultiPageImageCaptureScenario, didFailWithError error: Error, result: AUIMultiPageImageCaptureResult)
	{
		captureController?.paused = true
		showAlert(with: error)
	}
}

// MARK: - AUIMultiPageCaptureSettings implementation

extension StartViewController: AUIMultiPageCaptureSettings
{
	func captureScenario(_ captureScenario: AUIMultiPageImageCaptureScenario, onConfigureImageCaptureSettings settings: AUIImageCaptureSettings, forPageAt index: UInt)
	{
		let profile = profiles[profilesControl.selectedSegmentIndex]
		settings.documentSize = profile.documentSize
		settings.aspectRatioMin = profile.minAspectRatio
		settings.aspectRatioMax = profile.maxAspectRatio
	}
}

// MARK: - UICollectionViewDelegate implementation

extension StartViewController: UICollectionViewDelegate & UICollectionViewDelegateFlowLayout
{
	func collectionView(_ collectionView: UICollectionView,
		layout collectionViewLayout: UICollectionViewLayout,
		sizeForItemAt indexPath: IndexPath) -> CGSize
	{
		return CGSize(
			width: view.frame.width / CGFloat(columnsCount) - collectionCellsInset * 2,
			height: view.frame.width / CGFloat(columnsCount) - collectionCellsInset * 2)
	}

	func collectionView(_ collectionView: UICollectionView,
		layout collectionViewLayout: UICollectionViewLayout,
		minimumLineSpacingForSectionAt section: Int) -> CGFloat
	{
		return collectionCellsInset
	}

	func collectionView(_ collectionView: UICollectionView,
		layout collectionViewLayout: UICollectionViewLayout,
		minimumInteritemSpacingForSectionAt section: Int) -> CGFloat
	{
		return collectionCellsInset
	}

	func collectionView(_ collectionView: UICollectionView,
			layout collectionViewLayout: UICollectionViewLayout,
			insetForSectionAt section: Int) -> UIEdgeInsets
	{
		return UIEdgeInsets(
			top: collectionCellsInset,
			left: collectionCellsInset,
			bottom: collectionCellsInset,
			right: collectionCellsInset)
	}

	func collectionView(_ collectionView: UICollectionView,
		willDisplay cell: UICollectionViewCell,
		forItemAt indexPath: IndexPath)
	{
		guard let imageCell = cell as? ImageCollectionViewCell else { return }

		let updateCellClosure: (UIImage?) -> Void = { [weak self] image in
			imageCell.imageView?.image = image
			self?.dataStorage.loadingOperations.removeValue(forKey: indexPath.row)
		}
		if let dataLoader = dataStorage.loadingOperations[indexPath.row] {
			if let image = dataLoader.image {
				imageCell.imageView?.image = image
				dataStorage.loadingOperations.removeValue(forKey: indexPath.row)
			} else {
				dataLoader.loadingCompleteHandler = updateCellClosure
			}
		} else {
			let dataLoader = dataStorage.fetchThumbnail(at: indexPath.row)
			dataLoader.loadingCompleteHandler = updateCellClosure
			dataStorage.loadingQueue.addOperation(dataLoader)
			dataStorage.loadingOperations[indexPath.row] = dataLoader
		}
	}

	func collectionView(_ collectionView: UICollectionView,
		didEndDisplaying cell: UICollectionViewCell,
		forItemAt indexPath: IndexPath)
	{
		if let dataLoader = dataStorage.loadingOperations[indexPath.row] {
			dataLoader.cancel()
			dataStorage.loadingOperations.removeValue(forKey: indexPath.row)
		}
	}
}

// MARK: - UICollectionViewDataSource implementation

extension StartViewController: UICollectionViewDataSource
{
	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int
	{
		return dataStorage.itemsCount
	}

	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell
	{
		let cell = collectionView.dequeueReusableCell(
			withReuseIdentifier: "PageCell",
			for: indexPath) as? ImageCollectionViewCell
		
		let cellSize = CGSize(
			width: view.frame.width / CGFloat(columnsCount),
			height: view.frame.width / CGFloat(columnsCount))
		
		cell?.imageView = UIImageView(frame: CGRect(origin: .zero, size: cellSize))
		
		return cell ?? UICollectionViewCell()
	}
}
