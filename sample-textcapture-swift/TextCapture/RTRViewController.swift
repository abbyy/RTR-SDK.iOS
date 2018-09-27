// ABBYY® Real-Time Recognition SDK 1 © 2016 ABBYY Production LLC.
// ABBYY is either a registered trademark or a trademark of ABBYY Software Ltd.

import UIKit
import AVFoundation

/// Shortcut. Perform block asynchronously on main thread.
private func performBlockOnMainThread(_ delay: Double, closure: @escaping () -> Void)
{
	DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
		closure()
	}
}

final class RTRViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {

	private struct Constants {
		/// Cell ID for languagesTableView.
		static let RTRTableCellID = "RTRTableCellID"
		/// Name for text region layers.
		static let RTRTextRegionsLayerName = "RTRTextRegionLayerName"
		// Recommended session preset.
		static let SessionPreset = AVCaptureSession.Preset.hd1280x720
	}
	
	/// View with video preview layer
	@IBOutlet weak var previewView: UIView?
	/// Stop/Start capture button
	@IBOutlet weak var captureButton: UIButton?

	/// Recognition languages table
	@IBOutlet weak var languagesTableView: UITableView?
	/// Button for show / hide table with recognition languages.
	@IBOutlet weak var recognizeLanguageButton: UIBarButtonItem?
	/// White view for highlight recognition results.
	@IBOutlet weak var whiteBackgroundView: UIView?
	/// View for displaying current area of interest.
	@IBOutlet weak var overlayView: RTRSelectedAreaView?
	
	/// Progress indicator view.
	@IBOutlet weak var progressIndicatorView: RTRProgressView?
	/// Label for error or warning info.
	@IBOutlet weak var infoLabel: UILabel?

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
	private var selectedRecognitionLanguages = Set(["English"])
	/// Image size.
	private var imageBufferSize = CGSize(width: 720, height: 1280)
	
	/// Is recognition running.
	private var isRunning = true
	
	private let RecognitionLanguages = ["English",
										"French",
										"German",
										"Italian",
										"Polish",
										"PortugueseBrazilian",
										"Russian",
										"ChineseSimplified",
										"ChineseTraditional",
										"Japanese",
										"Korean",
										"Spanish"]
	/// Area of interest in view coordinates.
	private var selectedArea = CGRect.zero {
		didSet {
			self.overlayView?.selectedArea = selectedArea
		}
	}

	// MARK: - LifeCycle

	override func viewDidLoad()
	{
		super.viewDidLoad()

		self.languagesTableView?.register(UITableViewCell.self, forCellReuseIdentifier: Constants.RTRTableCellID)
		self.languagesTableView?.tableFooterView = UIView(frame: .zero)
		self.languagesTableView?.isHidden = true
		
		self.prepareUIForRecognition()

		self.captureButton?.isSelected = false
		self.captureButton?.setTitle("Stop", for: .selected)
		self.captureButton?.setTitle("Start", for: .normal)

		self.languagesTableView?.isHidden = true
		self.recognizeLanguageButton?.title = self.languagesButtonTitle()

		let completion: (Bool) -> Void = { [weak self] granted in
			performBlockOnMainThread(0) {
				self?.configureCompletionAccess(granted)
			}
		}
		
		let status = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
		switch status {
			case .authorized:
				completion(true)
				
			case .notDetermined:
				AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler: { granted in
					DispatchQueue.main.async {
						completion(granted)
					}
				})
				
			case .restricted,
				 .denied:
				completion(false)
		}
	}
	
	override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator)
	{
		let wasRunning = self.isRunning
		self.isRunning = false
		self.textCaptureService?.stopTasks()
		self.clearScreenFromRegions()
		
		coordinator.animate(alongsideTransition: nil) { _ in
			self.imageBufferSize = CGSize(width: min(self.imageBufferSize.width, self.imageBufferSize.height),
			                              height: max(self.imageBufferSize.width, self.imageBufferSize.height))
			if(UIApplication.shared.statusBarOrientation.isLandscape) {
				self.imageBufferSize = CGSize(width: self.imageBufferSize.height, height: self.imageBufferSize.width)
			}
			
			self.updateAreaOfInterest()
			self.isRunning = wasRunning
		}
	}

	override func viewWillDisappear(_ animated: Bool)
	{
		self.session?.stopRunning()
		self.isRunning = false
		self.captureButton?.isSelected = false
		self.textCaptureService?.stopTasks()

		super.viewWillDisappear(animated)
	}

	override func viewDidLayoutSubviews()
	{
		super.viewDidLayoutSubviews()

		self.updatePreviewLayerFrame()
	}

	override var prefersStatusBarHidden: Bool {
		return true
	}

	// MARK: - Private

	func configureCompletionAccess(_ accessGranted: Bool)
	{
		guard UIImagePickerController.isCameraDeviceAvailable(.rear) else {
			self.captureButton?.isEnabled = false
			self.updateLogMessage("Device has no camera")
			return
		}

		guard accessGranted else {
			self.captureButton?.isEnabled = false
			self.updateLogMessage("Camera access denied")
			return
		}
		
		guard let licenseUrl = Bundle.main.url(forResource: "AbbyyRtrSdk", withExtension: "license")
			, let licenseData = try? Data(contentsOf: licenseUrl) else {
				self.captureButton?.isEnabled = false
				self.updateLogMessage("Invalid License file")
				return
		}

		self.engine = RTREngine.sharedEngine(withLicense: licenseData)
		assert(self.engine != nil)
		guard self.engine != nil else {
			self.captureButton?.isEnabled = false
			self.updateLogMessage("Invalid License")
			return
		}
		
		self.recognizeLanguageButton?.isEnabled = true
		self.textCaptureService = self.engine?.createTextCaptureService(with: self)
		self.textCaptureService?.setRecognitionLanguages(self.selectedRecognitionLanguages)
		
		self.configureAVCaptureSession()
		self.configurePreviewLayer()
		self.session?.startRunning()
		
		NotificationCenter.default.addObserver(self,
											   selector: #selector(RTRViewController.avSessionFailed(_:)),
											   name: NSNotification.Name.AVCaptureSessionRuntimeError, object: nil)
		
		NotificationCenter.default.addObserver(self,
											   selector: #selector(RTRViewController.applicationDidEnterBackground(_:)),
											   name: UIApplication.didEnterBackgroundNotification, object: nil)
		
		NotificationCenter.default.addObserver(self,
											   selector: #selector(RTRViewController.applicationWillEnterForeground(_:)),
											   name: UIApplication.willEnterForegroundNotification, object: nil)
		
		self.capturePressed()
	}

	private func configureAVCaptureSession()
	{
		let session = AVCaptureSession()
		session.sessionPreset = Constants.SessionPreset
		
		if let device = AVCaptureDevice.default(for: .video) {
			do {
				let input = try AVCaptureDeviceInput(device: device)
				assert(session.canAddInput(input), "impossible to add AVCaptureDeviceInput")
				session.addInput(input)
			} catch {
				print(error)
			}
		} else {
			self.updateLogMessage("Can't access device for capture video")
			return
		}
		
		let videoDataOutput = AVCaptureVideoDataOutput()
		let videoDataOutputQueue = DispatchQueue(label: "videodataqueue", attributes: .concurrent)
		videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
		videoDataOutput.videoSettings = [String(kCVPixelBufferPixelFormatTypeKey): Int(kCVPixelFormatType_32BGRA)]
		assert(session.canAddOutput(videoDataOutput), "impossible to add AVCaptureVideoDataOutput")
		session.addOutput(videoDataOutput)
		
		let connection = videoDataOutput.connection(with: AVMediaType.video)
		connection!.isEnabled = true
		
		self.session = session
	}

	private func configurePreviewLayer()
	{
		if let session = self.session {
			let previewLayer = AVCaptureVideoPreviewLayer(session: session)
			previewLayer.backgroundColor = UIColor.black.cgColor
			previewLayer.videoGravity = .resize
			
			self.previewView?.layer.insertSublayer(previewLayer, at: 0)
			self.previewLayer = previewLayer
		}
	}

	private func updatePreviewLayerFrame()
	{
		let orientation = UIApplication.shared.statusBarOrientation
		if let previewLayer = self.previewLayer
			, let connection = previewLayer.connection {
			connection.videoOrientation = self.videoOrientation(orientation)
			let viewBounds = self.view.bounds
			self.previewLayer?.frame = viewBounds
			self.selectedArea = viewBounds.insetBy(dx: viewBounds.width / 8.0, dy: viewBounds.height / 3.0)
			
			self.updateAreaOfInterest()
		}
	}

	private func updateAreaOfInterest()
	{
		guard let overlayView = self.overlayView
			, let textCaptureService = self.textCaptureService else {
				return
		}
		// Scale area of interest from view coordinate system to image coordinates.
		let affineTransform = CGAffineTransform(scaleX: self.imageBufferSize.width * 1.0 / overlayView.frame.width,
												y: self.imageBufferSize.height * 1.0 / overlayView.frame.height)
		let selectedRect = self.selectedArea.applying(affineTransform)
		textCaptureService.setAreaOfInterest(selectedRect)
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
		if self.selectedRecognitionLanguages.count == 1 {
			return self.selectedRecognitionLanguages.first ?? ""
		}

		return self.selectedRecognitionLanguages
			.map { lang in
				lang[..<lang.index(lang.startIndex, offsetBy: 2)]
			}
			.joined(separator: " ")
	}

	private func tryToCloseLanguagesTable()
	{
		if self.selectedRecognitionLanguages.isEmpty {
			return
		}

		self.updateLogMessage("")
		self.textCaptureService?.setRecognitionLanguages(self.selectedRecognitionLanguages)
		self.capturePressed()
		self.languagesTableView?.isHidden = true
	}
	
	private func updateLogMessage(_ message: String?)
	{
		performBlockOnMainThread(0){ [weak self] in
			guard let `self` = self else { return }
			self.infoLabel?.text = message ?? ""
		}
	}
	
	func prepareUIForRecognition()
	{
		self.clearScreenFromRegions()
		self.whiteBackgroundView?.isHidden = true
		self.progressIndicatorView?.setProgress(0, self.progressColor(RTRResultStabilityStatus.notReady))
	}

	// MARK: - Drawing result

	private func drawTextLines(_ textLines: [RTRTextLine], _ progress:RTRResultStabilityStatus)
	{
		self.clearScreenFromRegions()

		let textRegionsLayer = CALayer()
		textRegionsLayer.frame = self.previewLayer!.frame
		textRegionsLayer.name = Constants.RTRTextRegionsLayerName

		for textLine in textLines {
			self.drawTextLine(textLine, textRegionsLayer, progress)
		}

		self.previewView?.layer.addSublayer(textRegionsLayer)
	}

	func drawTextLine(_ textLine: RTRTextLine, _ layer: CALayer, _ progress: RTRResultStabilityStatus)
	{
		let topLeft = self.scaledPoint(cMocrPoint: textLine.quadrangle[0] as! NSValue)
		let bottomLeft = self.scaledPoint(cMocrPoint: textLine.quadrangle[1] as! NSValue)
		let bottomRight = self.scaledPoint(cMocrPoint: textLine.quadrangle[2] as! NSValue)
		let topRight = self.scaledPoint(cMocrPoint: textLine.quadrangle[3] as! NSValue)

		self.drawQuadrangle(topLeft, bottomLeft, bottomRight, topRight, layer, progress) 

		guard let recognizedString = textLine.text else {
			return
		}

		let textLayer = CATextLayer()
		let textWidth = self.distanceBetween(topLeft, topRight) 
		let textHeight = self.distanceBetween(topLeft, bottomLeft) 
		let rectForTextLayer = CGRect(x: bottomLeft.x, y: bottomLeft.y, width: textWidth, height: textHeight) 

		// Selecting the initial font size by rectangle
		let textFont = self.font(string: recognizedString, rect: rectForTextLayer)
		textLayer.font = textFont
		textLayer.fontSize = textFont.pointSize
		textLayer.foregroundColor = self.progressColor(progress).cgColor
		textLayer.alignmentMode = CATextLayerAlignmentMode.center
		textLayer.string = recognizedString
		textLayer.frame = rectForTextLayer

		// Rotate the text layer
		let angle = asin((bottomRight.y - bottomLeft.y) / self.distanceBetween(bottomLeft, bottomRight))
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
		area.strokeColor = self.progressColor(progress).cgColor 
		area.fillColor = UIColor.clear.cgColor 
		layer.addSublayer(area) 
	}

	func progressColor(_ progress: RTRResultStabilityStatus) -> UIColor
	{
		switch progress {
			case .notReady,
				 .tentative:
				return UIColor(hex: 0xFF6500)
			case .verified:
				return UIColor(hex: 0xC96500)
			case .available:
				return UIColor(hex: 0x886500)
			case .tentativelyStable:
				return UIColor(hex: 0x4B6500)
			case .stable:
				return UIColor(hex: 0x006500)
		}
	}

	/// Remove all visible regions
	private func clearScreenFromRegions()
	{
		// Get all visible regions
		guard let sublayers = self.previewView?.layer.sublayers else {
			return
		}

		// Remove all layers with name - RTRTextRegionLayerName
		sublayers
			.filter { $0.name == Constants.RTRTextRegionsLayerName }
			.forEach{ $0.removeFromSuperlayer() }
	}

	private func scaledPoint(cMocrPoint mocrPoint: NSValue) -> CGPoint
	{
		guard let previewLayer = self.previewLayer else {
			return .zero
		}
		
		let layerWidth = previewLayer.bounds.width
		let layerHeight = previewLayer.bounds.height

		let widthScale = layerWidth / self.imageBufferSize.width
		let heightScale = layerHeight / self.imageBufferSize.height

		var point = mocrPoint.cgPointValue
		point.x *= widthScale
		point.y *= heightScale

		return point
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

	// MARK: - UITableViewDelegate

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
	{
		let language = RecognitionLanguages[indexPath.row]
		if !self.selectedRecognitionLanguages.contains(language) {
			self.selectedRecognitionLanguages.insert(language)
		} else {
			self.selectedRecognitionLanguages.remove(language)
		}

		self.recognizeLanguageButton?.title = self.languagesButtonTitle()
		tableView.reloadRows(at: [indexPath], with: .automatic)
	}

	// MARK: - UITableViewDatasource

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
	{
		return RecognitionLanguages.count
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
	{
		let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
		let language = RecognitionLanguages[indexPath.row]
		cell.textLabel?.text = language
		cell.accessoryType = self.selectedRecognitionLanguages.contains(language) ? .checkmark : .none
		cell.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.4)
		cell.textLabel?.textColor = UIColor.white
		cell.tintColor = UIColor.white
		return cell
	}

	// MARK: - Notifications

	@objc
	func avSessionFailed(_ notification: NSNotification)
	{
		let alert = UIAlertController(title: "AVSession Failed!", message: nil, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action"), style: .default, handler: nil))
		
		self.present(alert, animated: true, completion: nil)
	}

	@objc
	func applicationDidEnterBackground(_ notification: NSNotification)
	{
		self.session?.stopRunning()
		self.clearScreenFromRegions()
		self.whiteBackgroundView?.isHidden = true
		self.textCaptureService?.stopTasks()
		self.captureButton?.isSelected = true
		self.isRunning = false
	}

	@objc
	func applicationWillEnterForeground(_ notification: NSNotification)
	{
		self.session?.startRunning()
	}


	// MARK: - Actions

	@IBAction func onReconitionLanguages(_ sender: AnyObject)
	{
		guard let languagesTableView = self.languagesTableView else { return }
		if languagesTableView.isHidden {
			self.isRunning = false
			self.captureButton?.isSelected = false
			languagesTableView.reloadData()
			languagesTableView.isHidden = false
		} else {
			self.tryToCloseLanguagesTable()
		}
	}

	@IBAction func capturePressed(_ sender: AnyObject? = nil)
	{
		guard let captureButton = self.captureButton else {
			return
		}
		
		if !captureButton.isEnabled {
			return
		}

		captureButton.isSelected.toggle()
		self.isRunning = captureButton.isSelected

		if self.isRunning {
			self.updateLogMessage("")
			self.prepareUIForRecognition()
			self.session?.startRunning()
		} else {
			self.textCaptureService?.stopTasks()
		}
	}
	
	/// Human-readable descriptions for the RTRCallbackWarningCode constants.
	private func stringFromWarningCode(_ warningCode: RTRCallbackWarningCode) -> String
	{
		switch warningCode {
			case .textTooSmall:
				return "Text is too small"
			default:
				return ""
		}
	}
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension RTRViewController: AVCaptureVideoDataOutputSampleBufferDelegate
{
	func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
	{
		if !self.isRunning {
			return
		}
		
		// Image is prepared
		DispatchQueue.main.async {
			let orientation = UIApplication.shared.statusBarOrientation
			connection.videoOrientation = self.videoOrientation(orientation)
			
			self.textCaptureService?.add(sampleBuffer)
		}
		
	}
}

// MARK: - RTRTextCaptureServiceDelegate

extension RTRViewController: RTRTextCaptureServiceDelegate
{
	func onBufferProcessed(with textLines: [RTRTextLine], resultStatus: RTRResultStabilityStatus)
	{
		performBlockOnMainThread(0) { [weak self] in
			guard let `self` = self else { return }
			
			if !self.isRunning {
				return
			}
			
			self.progressIndicatorView?.setProgress(resultStatus.rawValue, self.progressColor(resultStatus))
			
			if resultStatus == .stable {
				self.isRunning = false
				self.captureButton?.isSelected = false
				self.whiteBackgroundView?.isHidden = false
				self.textCaptureService?.stopTasks()
			}
			
			self.drawTextLines(textLines, resultStatus)
		}
	}
	
	func onWarning(_ warningCode: RTRCallbackWarningCode)
	{
		let message = self.stringFromWarningCode(warningCode)
		guard !message.isEmpty
			, self.isRunning else {
				return
		}
		
		self.updateLogMessage(message)
		
		// Clear message after 2 seconds.
		performBlockOnMainThread(2){ [weak self] in
			self?.updateLogMessage("")
		}
	}
	
	func onError(_ error: Error)
	{
		print(error)
		performBlockOnMainThread(0) { [weak self] in
			guard let `self` = self else { return }
			
			if self.isRunning {
				
				let message: String
				switch error.localizedDescription {
				case let str where str.contains("ChineseJapanese.rom"):
					message = "Chineze, Japanese and Korean are available in EXTENDED version only. Contact us for more information."
				case let str where str.contains("KoreanSpecific.rom"):
					message = "Chineze, Japanese and Korean are available in EXTENDED version only. Contact us for more information."
				case let str where str.contains("Russian.edc"):
					message = "Cyrillic script languages are available in EXTENDED version only. Contact us for more information."
				case let str where str.contains(".trdic"):
					message = "Translation is available in EXTENDED version only. Contact us for more information."
				default:
					message = error.localizedDescription
				}
				
				self.updateLogMessage(message)
				self.isRunning = false
				self.captureButton?.isSelected = false
				
			}

		}
		
	}
}
