// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

import AVFoundation
import AbbyyRtrSDK

class RTRViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {

	/// Cell ID for tableView.
	private let RTRTableCellID = "RTRTableCellID"
	/// Name for text region layers.
	private let RTRTextRegionsLayerName = "RTRTextRegionLayerName"

	/// View with video preview layer
	@IBOutlet weak var previewView: UIView!
	/// Stop/Start capture button
	@IBOutlet weak var captureButton: UIButton!

	/// Recognition languages table
	@IBOutlet weak var tableView: UITableView!
	/// Button for show / hide table with recognition languages.
	@IBOutlet weak var settingsButton: UIBarButtonItem!
	/// White view for highlight recognition results.
	@IBOutlet weak var whiteBackgroundView: UIView!
	/// View for displaying current area of interest.
	@IBOutlet weak var overlayView: RTRSelectedAreaView!

	/// Progress indicator view.
	@IBOutlet weak var progressIndicatorView: RTRProgressView!
	/// Label for error or warning info.
	@IBOutlet weak var infoLabel: UILabel!

	/// Camera session.
	private var session: AVCaptureSession?
	/// Video preview layer.
	private var previewLayer: AVCaptureVideoPreviewLayer?
	/// Engine for AbbyyRtrSDK.
	private var engine: RTREngine?
	/// Service for runtime recognition.
	private var textCaptureService: RTRTextCaptureService?
	/// Selected recognition languages.
	/// Default recognition language.
	private var selectedRecognitionLanguages = Set([RTRLanguageName.english])
	// Recommended session preset.
	private let SessionPreset = AVCaptureSession.Preset.hd1280x720
	private var ImageBufferSize = CGSize(width: 720, height: 1280)

	/// Is recognition running.
	private var isRunning = true

	private let RecognitionLanguages: [RTRLanguageName] = [
		.english,
		.french,
		.german,
		.italian,
		.polish,
		.portugueseBrazilian,
		.russian,
		.chineseSimplified,
		.chineseTraditional,
		.japanese,
		.korean,
		.spanish
	]
	/// Area of interest in view coordinates.
	private var selectedArea: CGRect = CGRect.zero {
		didSet {
			overlayView.selectedArea = selectedArea
		}
	}

//# MARK: - LifeCycle

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	override func viewDidLoad()
	{
		super.viewDidLoad()

		tableView.register(UITableViewCell.self, forCellReuseIdentifier: RTRTableCellID)
		tableView.tableFooterView = UIView(frame: CGRect.zero)
		tableView.isHidden = true

		prepareUIForRecognition()

		captureButton.isSelected = false
		captureButton.setTitle("Stop", for: UIControl.State.selected)
		captureButton.setTitle("Start", for: UIControl.State.normal)

		tableView.isHidden = true
		let recognizeLanguageButtonTitle = languagesButtonTitle()
		settingsButton.title = recognizeLanguageButtonTitle

		weak var weakSelf = self
		let completion:(Bool) -> Void = { granted in
			DispatchQueue.main.async {
				if let strongSelf = weakSelf {
					strongSelf.configureCompletionAccess(granted)
				}
			}
		}

		let status = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
		switch status {
			case AVAuthorizationStatus.authorized:
				completion(true)

			case AVAuthorizationStatus.notDetermined:
				AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler: { (granted) in
					completion(granted)
				})

			case AVAuthorizationStatus.restricted, AVAuthorizationStatus.denied:
				completion(false)

			@unknown default:
				assert(false)
		}
	}

	override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator)
	{
		let wasRunning = isRunning
		isRunning = false
		if let service = textCaptureService {
			service.stopTasks()
		}
		clearScreenFromRegions()

		weak var weakSelf = self
		coordinator.animate(alongsideTransition: nil) { (context) in
			if let strongSelf = weakSelf {
				let oldSize = strongSelf.ImageBufferSize
				let newSize = CGSize(width:min(oldSize.width, oldSize.height), height:max(oldSize.width, oldSize.height))
				if(UIApplication.shared.statusBarOrientation.isLandscape) {
					strongSelf.ImageBufferSize = CGSize(width:newSize.height, height:newSize.width);
				} else {
					strongSelf.ImageBufferSize = newSize
				}

				strongSelf.updateAreaOfInterest()
				strongSelf.isRunning = wasRunning;
			}
		}
	}

	override func viewWillDisappear(_ animated: Bool)
	{
		isRunning = false
		captureButton.isSelected = false
		if let service = textCaptureService {
			service.stopTasks()
		}
		if let session = self.session {
			session.stopRunning()
		}
		super.viewWillDisappear(animated)
	}

	override func viewDidLayoutSubviews()
	{
		super.viewDidLayoutSubviews()
		updatePreviewLayerFrame()
	}

	override var prefersStatusBarHidden: Bool {
		return true
	}

//# MARK: - Private

	func configureCompletionAccess(_ accessGranted: Bool)
	{
		if !UIImagePickerController.isCameraDeviceAvailable(UIImagePickerController.CameraDevice.rear) {
			captureButton.isEnabled = false
			updateLogMessage("Device has no camera")
			return
		}

		if !accessGranted {
			captureButton.isEnabled = false
			updateLogMessage("Camera access denied")
			return
		}

		let licensePath = (Bundle.main.bundlePath as NSString).appendingPathComponent("license")
		let licenseUrl = URL.init(fileURLWithPath: licensePath)
		if let data = try? Data(contentsOf: licenseUrl) {
			engine = RTREngine.sharedEngine(withLicense: data)
		}
		guard let rtrEngine = engine else {
			captureButton.isEnabled = false;
			updateLogMessage("Invalid License")
			return
		}

		settingsButton.isEnabled = true

		let service = rtrEngine.createTextCaptureService(with: self)
		service.setRecognitionLanguages(Set(selectedRecognitionLanguages.map{ $0.rawValue }))
		textCaptureService = service

		configureAVCaptureSession()
		configurePreviewLayer()
		session?.startRunning()

		NotificationCenter.default.addObserver(self, selector:#selector(RTRViewController.avSessionFailed(_:)), name: NSNotification.Name.AVCaptureSessionRuntimeError, object: nil)
		NotificationCenter.default.addObserver(self, selector:#selector(RTRViewController.applicationDidEnterBackground(_:)), name: UIApplication.didEnterBackgroundNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector:#selector(RTRViewController.applicationWillEnterForeground(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)

		capturePressed()
	}

	private func configureAVCaptureSession()
	{
		session = AVCaptureSession()

		if let session = self.session {
			session.sessionPreset = SessionPreset

			if let device = AVCaptureDevice.default(for: AVMediaType.video) {
				do {
					let input = try AVCaptureDeviceInput(device: device)
					assert(session.canAddInput(input), "impossible to add AVCaptureDeviceInput")
					session.addInput(input)
				} catch let error as NSError {
					print(error.localizedDescription)
				}
			} else {
				updateLogMessage("Can't access device for capture video")
				return
			}

			let videoDataOutput = AVCaptureVideoDataOutput()
			let videoDataOutputQueue = DispatchQueue(label: "videodataqueue", attributes: .concurrent)
			videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
			videoDataOutput.videoSettings = [String(kCVPixelBufferPixelFormatTypeKey): Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
			assert((session.canAddOutput(videoDataOutput)), "impossible to add AVCaptureVideoDataOutput")
			session.addOutput(videoDataOutput)

			if let connection = videoDataOutput.connection(with: AVMediaType.video) {
				connection.isEnabled = true
			}
		}
	}

	private func configurePreviewLayer()
	{
		if let session = self.session {
			let layer = AVCaptureVideoPreviewLayer(session: session)
			layer.backgroundColor = UIColor.black.cgColor
			layer.videoGravity = AVLayerVideoGravity.resize
			let rootLayer = previewView.layer
			rootLayer.insertSublayer(layer, at: 0)

			previewLayer = layer
			updatePreviewLayerFrame()
		}
	}

	private func updatePreviewLayerFrame()
	{
		let orientation = UIApplication.shared.statusBarOrientation
		if let previewLayer = self.previewLayer, let connection = previewLayer.connection {
			connection.videoOrientation = videoOrientation(orientation)
			let viewBounds = view.bounds
			previewLayer.frame = viewBounds
			selectedArea = viewBounds.insetBy(dx: viewBounds.width / 8.0, dy: viewBounds.height / 3.0)

			updateAreaOfInterest()
		}
	}

	private func updateAreaOfInterest()
	{
		// Scale area of interest from view coordinate system to image coordinates.
		let affineTransform = CGAffineTransform(scaleX: ImageBufferSize.width * 1.0 / overlayView.frame.width,
			y: ImageBufferSize.height * 1.0 / overlayView.frame.height)
		let selectedRect = selectedArea.applying(affineTransform)
		if let service = textCaptureService {
			service.setAreaOfInterest(selectedRect)
		}
	}

	private func videoOrientation(_ orientation: UIInterfaceOrientation) -> AVCaptureVideoOrientation
	{
		switch orientation {
			case .portrait:
				return .portrait
			case .portraitUpsideDown:
				return .portraitUpsideDown
			case .landscapeLeft:
				return .landscapeLeft
			case .landscapeRight:
				return .landscapeRight
			default:
				return .portrait
		}
	}

	private func languagesButtonTitle() -> String
	{
		if selectedRecognitionLanguages.count == 1 {
			return selectedRecognitionLanguages.first!.rawValue
		}

		var languageCodes = [String]()

		for language in selectedRecognitionLanguages {
			let index = language.rawValue.index(language.rawValue.startIndex, offsetBy: 2)
			languageCodes.append(String(language.rawValue[..<index]))
		}

		return languageCodes.joined(separator: " ")
	}

	private func tryToCloseLanguagesTable()
	{
		if selectedRecognitionLanguages.isEmpty {
			return
		}

		updateLogMessage("")
		tableView.isHidden = true

		if let service = textCaptureService {
			service.setRecognitionLanguages(Set(selectedRecognitionLanguages.map{ $0.rawValue }))
			capturePressed()
		}
	}

	private func updateLogMessage(_ message: String?)
	{
		weak var weakSelf = self

		DispatchQueue.main.async {
			if let strongSelf = weakSelf {
				if let _message = message {
					strongSelf.infoLabel.text = _message
				} else {
					strongSelf.infoLabel.text = ""
				}
			}
		}
	}

	func prepareUIForRecognition()
	{
		clearScreenFromRegions()
		whiteBackgroundView.isHidden = true
		progressIndicatorView.setProgress(0, progressColor(.notReady))
	}

//# MARK: - Drawing result

	private func drawTextLines(_ lines: [RTRTextLine]?, _ progress:RTRResultStabilityStatus)
	{
		if let textLines = lines {
			if let previewLayer = self.previewLayer {
				clearScreenFromRegions()

				let textRegionsLayer = CALayer()
				textRegionsLayer.frame = previewLayer.frame
				textRegionsLayer.name = RTRTextRegionsLayerName

				for textLine in textLines {
					drawTextLine(textLine, textRegionsLayer, progress)
				}

				previewView.layer.addSublayer(textRegionsLayer)
			}
		}
	}

	func drawTextLine(_ textLine: RTRTextLine, _ layer: CALayer, _ progress: RTRResultStabilityStatus)
	{
		let topLeft = scaledPoint(imagePoint: textLine.quadrangle[0])
		let bottomLeft = scaledPoint(imagePoint: textLine.quadrangle[1])
		let bottomRight = scaledPoint(imagePoint: textLine.quadrangle[2])
		let topRight = scaledPoint(imagePoint: textLine.quadrangle[3])

		drawQuadrangle(topLeft, bottomLeft, bottomRight, topRight, layer, progress)

		let recognizedString = textLine.text

		let textLayer = CATextLayer()
		let textWidth = distanceBetween(topLeft, topRight)
		let textHeight = distanceBetween(topLeft, bottomLeft)
		let rectForTextLayer = CGRect(x: bottomLeft.x, y: bottomLeft.y, width: textWidth, height: textHeight) 

		// Selecting the initial font size by rectangle
		let textFont = font(string: recognizedString, rect: rectForTextLayer)
		textLayer.font = textFont
		textLayer.fontSize = textFont.pointSize
		textLayer.foregroundColor = progressColor(progress).cgColor
		textLayer.alignmentMode = CATextLayerAlignmentMode.center
		textLayer.string = recognizedString
		textLayer.frame = rectForTextLayer

		// Rotate the text layer
		let angle = asin((bottomRight.y - bottomLeft.y) / distanceBetween(bottomLeft, bottomRight))
		textLayer.anchorPoint = CGPoint(x: 0, y: 0)
		textLayer.position = bottomLeft
		textLayer.transform = CATransform3DRotate(CATransform3DIdentity, angle, 0, 0, 1)

		layer.addSublayer(textLayer)
	}

	func drawQuadrangle(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ layer: CALayer, _ progress: RTRResultStabilityStatus)
	{
		let area = CAShapeLayer()
		let recognizedAreaPath = UIBezierPath() 
		recognizedAreaPath.move(to: p0) 
		recognizedAreaPath.addLine(to: p1) 
		recognizedAreaPath.addLine(to: p2) 
		recognizedAreaPath.addLine(to: p3) 
		recognizedAreaPath.close() 
		area.path = recognizedAreaPath.cgPath 
		area.strokeColor = progressColor(progress).cgColor
		area.fillColor = UIColor.clear.cgColor 
		layer.addSublayer(area) 
	}

	func progressColor(_ progress:RTRResultStabilityStatus) -> UIColor
	{
		switch progress {
			case .notReady, .tentative:
				return UIColor(hex: 0xFF6500)
			case .verified:
				return UIColor(hex: 0xC96500)
			case .available:
				return UIColor(hex: 0x886500)
			case .tentativelyStable:
				return UIColor(hex: 0x4B6500)
			case .stable:
				return UIColor(hex: 0x006500)
			@unknown default:
				assert(false)
				return .black
		}
	}

	/// Remove all visible regions
	private func clearScreenFromRegions()
	{
		// Get all visible regions
		if let sublayers = previewView.layer.sublayers {

			// Remove all layers with name - TextRegionsLayer
			for layer in sublayers {
				if layer.name == RTRTextRegionsLayerName {
					layer.removeFromSuperlayer()
				}
			}
		}
	}

	private func scaledPoint(imagePoint: NSValue) -> CGPoint
	{
		if let previewLayer = self.previewLayer {
			let layerWidth = previewLayer.bounds.width
			let layerHeight = previewLayer.bounds.height

			let widthScale = layerWidth / ImageBufferSize.width
			let heightScale = layerHeight / ImageBufferSize.height


			var point = imagePoint.cgPointValue
			point.x *= widthScale
			point.y *= heightScale

			return point
		}
		return CGPoint.zero;
	}

	private func distanceBetween(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat
	{
		let vector = CGVector(dx: p2.x - p1.x, dy: p2.y - p1.y)
		return sqrt(vector.dx * vector.dx + vector.dy * vector.dy)
	}

	private func font(string: String, rect: CGRect) -> UIFont
	{
		var minFontSize: CGFloat = 0.1
		var maxFontSize: CGFloat = 72.0
		var fontSize: CGFloat = minFontSize

		let rectSize = rect.size

		while true {
			let attributes = [NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: fontSize)]
			let labelSize = (string as NSString).size(withAttributes: attributes)

			if rectSize.height - labelSize.height > 0 {
				minFontSize = fontSize

				if rectSize.height * 0.99 - labelSize.height < 0 {
					break
				}
			} else {
				maxFontSize = fontSize
			}

			if abs(minFontSize - maxFontSize) < 0.01 {
				break
			}

			fontSize = (minFontSize + maxFontSize) / 2 
		}

		return UIFont.boldSystemFont(ofSize: fontSize)
	}

//# MARK: - UITableViewDelegate

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
	{
		let language = RecognitionLanguages[indexPath.row]
		if !selectedRecognitionLanguages.contains(language) {
			selectedRecognitionLanguages.insert(language)
		} else {
			selectedRecognitionLanguages.remove(language)
		}

		settingsButton.title = languagesButtonTitle()
		tableView .reloadRows(at: [indexPath], with: UITableView.RowAnimation.automatic)
	}

//# MARK: - UITableViewDatasource

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
	{
		return RecognitionLanguages.count
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
	{
		let cell = UITableViewCell(style: UITableViewCell.CellStyle.default, reuseIdentifier: nil)
		let language = RecognitionLanguages[indexPath.row]
		if let label = cell.textLabel {
			label.text = language.rawValue
			label.textColor = .white
		}
		cell.accessoryType = selectedRecognitionLanguages.contains(language) ? UITableViewCell.AccessoryType.checkmark : UITableViewCell.AccessoryType.none
		cell.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.4)
		cell.tintColor = .white
		return cell
	}

//# MARK: - Notifications

	@objc
	func avSessionFailed(_ notification: NSNotification)
	{
		weak var weakSelf = self
		DispatchQueue.main.async {
			var message = "AVSession Failed! "
			if let userInfo = notification.userInfo {
				if let error = userInfo[AVCaptureSessionErrorKey] {
					message = message + (error as! String)
				}
			}
			if let strongSelf = weakSelf {
				strongSelf.infoLabel.text = message
			}
		}
	}

	@objc
	func applicationDidEnterBackground(_ notification: NSNotification)
	{
		clearScreenFromRegions()
		whiteBackgroundView.isHidden = true
		captureButton.isSelected = true
		isRunning = false

		if let service = textCaptureService {
			service.stopTasks()
		}
		if let session = self.session {
			session.stopRunning()
		}
	}

	@objc
	func applicationWillEnterForeground(_ notification: NSNotification)
	{
		if let session = self.session {
			session.startRunning()
		}
	}

//# MARK: - Actions

	@IBAction func onReconitionLanguages()
	{
		if tableView.isHidden {
			isRunning = false
			captureButton.isSelected = false
			tableView.reloadData()
			tableView.isHidden = false
		} else {
			tryToCloseLanguagesTable()
		}
	}

	@IBAction func capturePressed()
	{
		if !captureButton.isEnabled {
			return
		}

		captureButton.isSelected = !captureButton.isSelected
		isRunning = captureButton.isSelected

		if isRunning {
			prepareUIForRecognition()
			if let session = self.session {
				session.startRunning()
			}
		} else {
			if let service = textCaptureService {
				service.stopTasks()
			}
		}
	}

	/// Human-readable descriptions for the RTRCallbackWarningCode constants.
	private func stringFromWarningCode(_ warningCode: RTRCallbackWarningCode) -> String
	{
		var warningString: String
		switch warningCode {
			case .textTooSmall:
				warningString = "Text is too small"
			default:
				warningString = ""
		}
		return warningString
	}
}

extension RTRViewController: AVCaptureVideoDataOutputSampleBufferDelegate
{
	func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
	{
		if !isRunning {
			return
		}

		var orientation: UIInterfaceOrientation = .portrait
		DispatchQueue.main.sync {
			orientation = UIApplication.shared.statusBarOrientation
		}

		let frameOrientation = videoOrientation(orientation)
		if connection.videoOrientation != frameOrientation {
			connection.videoOrientation = frameOrientation
			return
		}

		if let service = textCaptureService {
			service.add(sampleBuffer)
		}
	}
}

extension RTRViewController: RTRTextCaptureServiceDelegate
{
	func onBufferProcessed(with textLines: [RTRTextLine], resultStatus: RTRResultStabilityStatus)
	{
		if !isRunning {
			return
		}

		progressIndicatorView.setProgress(resultStatus.rawValue, progressColor(resultStatus))

		if resultStatus == .stable {
			isRunning = false
			captureButton.isSelected = false
			whiteBackgroundView.isHidden = false
			if let service = textCaptureService {
				service.stopTasks()
			}
		}

		drawTextLines(textLines, resultStatus)
	}

	func onWarning(_ warningCode: RTRCallbackWarningCode)
	{
		let message = stringFromWarningCode(warningCode);
		if message.count > 0 {
			if(!isRunning) {
				return;
			}

			updateLogMessage(message);

			weak var weakSelf = self
			// Clear message after 2 seconds.
			DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
				if let strongSelf = weakSelf {
					strongSelf.updateLogMessage("")
				}
			}
		}
	}

	func onError(_ error: Error)
	{
		print(error.localizedDescription)
		if isRunning {
			var description = error.localizedDescription
			if description.contains("ChineseJapanese.rom") {
				description = "Chineze, Japanese and Korean are available in EXTENDED version only. Contact us for more information."
			} else if description.contains("KoreanSpecific.rom") {
				description = "Chineze, Japanese and Korean are available in EXTENDED version only. Contact us for more information."
			} else if description.contains("Russian.edc") {
				description = "Cyrillic script languages are available in EXTENDED version only. Contact us for more information."
			} else if description.contains(".trdic") {
				description = "Translation is available in EXTENDED version only. Contact us for more information."
			} else if description.contains("region is invalid") {
				return
			}

			isRunning = false
			captureButton.isSelected = false
			updateLogMessage(description)
		}
	}
}
