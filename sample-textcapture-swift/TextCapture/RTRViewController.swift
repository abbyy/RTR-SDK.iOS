// ABBYY® Real-Time Recognition SDK 1 © 2016 ABBYY Production LLC.
// ABBYY is either a registered trademark or a trademark of ABBYY Software Ltd.

import UIKit
import AVFoundation

class RTRViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {

	/// Cell ID for languagesTableView.
	private let RTRTableCellID = "RTRTableCellID"
	/// Name for text region layers.
	private let RTRTextRegionsLayerName = "RTRTextRegionLayerName"

	/// View with video preview layer
	@IBOutlet weak var previewView: UIView!
	/// Stop/Start capture button
	@IBOutlet weak var captureButton: UIButton!

	/// Recognition languages table
	@IBOutlet weak var languagesTableView: UITableView!
	/// Button for show / hide table with recognition languages.
	@IBOutlet weak var recognizeLanguageButton: UIBarButtonItem!
	/// White view for highlight recognition results.
	@IBOutlet weak var whiteBackgroundView: UIView!
	/// View for displaying current area of interest.
	@IBOutlet weak var overlayView: RTRSelectedAreaView!
	
	/// Progress indicator view.
	@IBOutlet weak var progressIndicatorView: RTRProgressView?
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
	private var selectedRecognitionLanguages = Set(["English"])
	// Recommended session preset.
	private let SessionPreset = AVCaptureSession.Preset.hd1280x720
	private var ImageBufferSize = CGSize(width: 720, height: 1280)
	
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
	private var selectedArea: CGRect = CGRect.zero {
		didSet {
			self.overlayView.selectedArea = selectedArea
		}
	}
	
	/// Shortcut. Perform block asynchronously on main thread.
	private func performBlockOnMainThread(_ delay: Double, closure: @escaping ()->())
	{
		DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
			closure()
		}
	}

//# MARK: - LifeCycle
	
	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	override func viewDidLoad()
	{
		super.viewDidLoad()

		self.languagesTableView.register(UITableViewCell.self, forCellReuseIdentifier: RTRTableCellID)
		self.languagesTableView.tableFooterView = UIView(frame: CGRect.zero)
		self.languagesTableView.isHidden = true
		
		self.prepareUIForRecognition()

		self.captureButton.isSelected = false
		self.captureButton.setTitle("Stop", for: UIControlState.selected)
		self.captureButton.setTitle("Start", for: UIControlState.normal)

		self.languagesTableView.isHidden = true
		let recognizeLanguageButtonTitle = self.languagesButtonTitle()
		self.recognizeLanguageButton.title = recognizeLanguageButtonTitle

		weak var weakSelf = self
		let completion:(Bool) -> Void = { granted in
			weakSelf?.performBlockOnMainThread(0) { 
				weakSelf?.configureCompletionAccess(granted)
			}
		}
		
		let status = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
		switch status {
			case AVAuthorizationStatus.authorized:
				completion(true)
				
			case AVAuthorizationStatus.notDetermined:
				AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler: { (granted) in
					DispatchQueue.main.async {
						completion(granted)
					}
				})
				
			case AVAuthorizationStatus.restricted, AVAuthorizationStatus.denied:
				completion(false)
		}
	}
	
	override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator)
	{
		let wasRunning = self.isRunning
		self.isRunning = false
		self.textCaptureService?.stopTasks()
		self.clearScreenFromRegions()
		
		coordinator.animate(alongsideTransition: nil) { (context) in
			self.ImageBufferSize = CGSize(width:min(self.ImageBufferSize.width, self.ImageBufferSize.height),
			                              height:max(self.ImageBufferSize.width, self.ImageBufferSize.height))
			if(UIInterfaceOrientationIsLandscape(UIApplication.shared.statusBarOrientation)) {
				self.ImageBufferSize = CGSize(width:self.ImageBufferSize.height, height:self.ImageBufferSize.width);
			}
			
			self.updateAreaOfInterest()
			self.isRunning = wasRunning;
		}
	}

	override func viewWillDisappear(_ animated: Bool)
	{
		self.session?.stopRunning()
		self.isRunning = false
		self.captureButton.isSelected = false
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

//# MARK: - Private

	func configureCompletionAccess(_ accessGranted: Bool)
	{
		if !UIImagePickerController.isCameraDeviceAvailable(UIImagePickerControllerCameraDevice.rear) {
			self.captureButton.isEnabled = false
			self.updateLogMessage("Device has no camera")
			return
		}

		if !accessGranted {
			self.captureButton.isEnabled = false
			self.updateLogMessage("Camera access denied")
			return
		}
		
		let licensePath = (Bundle.main.bundlePath as NSString).appendingPathComponent("AbbyyRtrSdk.license")
		self.engine = RTREngine.sharedEngine(withLicense: NSData(contentsOfFile: licensePath) as Data!)
		assert(self.engine != nil)
		guard self.engine != nil else {
			self.captureButton.isEnabled = false;
			self.updateLogMessage("Invalid License")
			return
		}
		
		self.recognizeLanguageButton.isEnabled = true
		self.textCaptureService = self.engine?.createTextCaptureService(with: self)
		self.textCaptureService?.setRecognitionLanguages(selectedRecognitionLanguages)
		
		self.configureAVCaptureSession()
		self.configurePreviewLayer()
		self.session?.startRunning()
		
		NotificationCenter.default.addObserver(self, selector:#selector(RTRViewController.avSessionFailed(_:)), name: NSNotification.Name.AVCaptureSessionRuntimeError, object: nil)
		NotificationCenter.default.addObserver(self, selector:#selector(RTRViewController.applicationDidEnterBackground(_:)), name: NSNotification.Name.UIApplicationDidEnterBackground, object: nil)
		NotificationCenter.default.addObserver(self, selector:#selector(RTRViewController.applicationWillEnterForeground(_:)), name: NSNotification.Name.UIApplicationWillEnterForeground, object: nil)
		
		self.capturePressed("" as AnyObject)
	}

	private func configureAVCaptureSession()
	{
		self.session = AVCaptureSession()
		
		if let session = self.session {
			session.sessionPreset = SessionPreset
			
			if let device = AVCaptureDevice.default(for: AVMediaType.video) {
				do {
					let input = try AVCaptureDeviceInput(device: device)
					assert((self.session?.canAddInput(input))!, "impossible to add AVCaptureDeviceInput")
					self.session?.addInput(input)
				} catch let error as NSError {
					print(error.localizedDescription)
				}
			} else {
				self.updateLogMessage("Can't access device for capture video")
				return
			}
			
			let videoDataOutput = AVCaptureVideoDataOutput()
			let videoDataOutputQueue = DispatchQueue(label: "videodataqueue", attributes: .concurrent)
			videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
			videoDataOutput.videoSettings = [String(kCVPixelBufferPixelFormatTypeKey): Int(kCVPixelFormatType_32BGRA)]
			assert((session.canAddOutput(videoDataOutput)), "impossible to add AVCaptureVideoDataOutput")
			session.addOutput(videoDataOutput)
			
			let connection = videoDataOutput.connection(with: AVMediaType.video)
			connection!.isEnabled = true
		}
	}

	private func configurePreviewLayer()
	{
		if let session = self.session {
			self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
			self.previewLayer?.backgroundColor = UIColor.black.cgColor
			self.previewLayer?.videoGravity = AVLayerVideoGravity.resize
			let rootLayer = self.previewView.layer
			rootLayer .insertSublayer(self.previewLayer!, at: 0)
			
			self.updatePreviewLayerFrame()
		}
	}

	private func updatePreviewLayerFrame()
	{
		let orientation = UIApplication.shared.statusBarOrientation
		if let previewLayer = self.previewLayer, let connection = previewLayer.connection {
			connection.videoOrientation = self.videoOrientation(orientation)
			let viewBounds = self.view.bounds
			self.previewLayer?.frame = viewBounds
			self.selectedArea = viewBounds.insetBy(dx: viewBounds.width/8.0, dy: viewBounds.height/3.0)
			
			self.updateAreaOfInterest()
		}
	}

	private func updateAreaOfInterest()
	{
		// Scale area of interest from view coordinate system to image coordinates.
		let affineTransform = CGAffineTransform(scaleX: self.ImageBufferSize.width * 1.0 / self.overlayView.frame.width, y: self.ImageBufferSize.height * 1.0 / self.overlayView.frame.height)
		let selectedRect = self.selectedArea.applying(affineTransform)
		self.textCaptureService?.setAreaOfInterest(selectedRect)
	}

	private func videoOrientation(_ orientation: UIInterfaceOrientation) -> AVCaptureVideoOrientation
	{
		switch orientation {
			case UIInterfaceOrientation.portrait:
				return AVCaptureVideoOrientation.portrait
			case UIInterfaceOrientation.portraitUpsideDown:
				return AVCaptureVideoOrientation.portraitUpsideDown
			case UIInterfaceOrientation.landscapeLeft:
				return AVCaptureVideoOrientation.landscapeLeft
			case UIInterfaceOrientation.landscapeRight:
				return AVCaptureVideoOrientation.landscapeRight
			default:
				return AVCaptureVideoOrientation.portrait
		}
	}

	private func languagesButtonTitle() -> String
	{
		if self.selectedRecognitionLanguages.count == 1 {
			return self.selectedRecognitionLanguages.first!
		}

		var languageCodes = [String]()

		for language in self.selectedRecognitionLanguages {
			let index = language.index(language.startIndex, offsetBy: 2)
			languageCodes.append(String(language[..<index]))
		}

		return languageCodes.joined(separator: " ")
	}

	private func tryToCloseLanguagesTable()
	{
		if self.selectedRecognitionLanguages.isEmpty {
			return
		}

		self.updateLogMessage("")
		self.textCaptureService?.setRecognitionLanguages(self.selectedRecognitionLanguages)
		self.capturePressed("" as AnyObject)
		self.languagesTableView.isHidden = true
	}
	
	private func updateLogMessage(_ message: String?)
	{
		performBlockOnMainThread(0){
			if let _message = message {
				self.infoLabel.text = _message
			} else {
				self.infoLabel.text = ""
			}
			
		}
	}
	
	func prepareUIForRecognition()
	{
		self.clearScreenFromRegions()
		self.whiteBackgroundView.isHidden = true
		self.progressIndicatorView?.setProgress(0, self.progressColor(RTRResultStabilityStatus.notReady))
	}

//# MARK: - Drawing result

	private func drawTextLines(_ textLines: [RTRTextLine], _ progress:RTRResultStabilityStatus)
	{
		self.clearScreenFromRegions()

		let textRegionsLayer = CALayer()
		textRegionsLayer.frame = self.previewLayer!.frame
		textRegionsLayer.name = RTRTextRegionsLayerName

		for textLine in textLines {
			self.drawTextLine(textLine, textRegionsLayer, progress)
		}

		self.previewView.layer.addSublayer(textRegionsLayer)
	}

	func drawTextLine(_ textLine: RTRTextLine, _ layer: CALayer, _ progress: RTRResultStabilityStatus)
	{
		let topLeft = self.scaledPoint(cMocrPoint: textLine.quadrangle[0] as! NSValue)
		let bottomLeft = self.scaledPoint(cMocrPoint: textLine.quadrangle[1] as! NSValue)
		let bottomRight = self.scaledPoint(cMocrPoint: textLine.quadrangle[2] as! NSValue)
		let topRight = self.scaledPoint(cMocrPoint: textLine.quadrangle[3] as! NSValue)

		self.drawQuadrangle(topLeft, bottomLeft, bottomRight, topRight, layer, progress) 

		let recognizedString = textLine.text

		let textLayer = CATextLayer()
		let textWidth = self.distanceBetween(topLeft, topRight) 
		let textHeight = self.distanceBetween(topLeft, bottomLeft) 
		let rectForTextLayer = CGRect(x: bottomLeft.x, y: bottomLeft.y, width: textWidth, height: textHeight) 

		// Selecting the initial font size by rectangle
		let textFont = self.font(string: recognizedString!, rect: rectForTextLayer)
		textLayer.font = textFont
		textLayer.fontSize = textFont.pointSize
		textLayer.foregroundColor = self.progressColor(progress).cgColor
		textLayer.alignmentMode = kCAAlignmentCenter
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

	func progressColor(_ progress:RTRResultStabilityStatus) -> UIColor
	{
		switch progress {
			case RTRResultStabilityStatus.notReady, RTRResultStabilityStatus.tentative:
				return UIColor(hex: 0xFF6500)
			case RTRResultStabilityStatus.verified:
				return UIColor(hex: 0xC96500)
			case RTRResultStabilityStatus.available:
				return UIColor(hex: 0x886500)
			case RTRResultStabilityStatus.tentativelyStable:
				return UIColor(hex: 0x4B6500)
			case RTRResultStabilityStatus.stable:
				return UIColor(hex: 0x006500)
		}
	}

	/// Remove all visible regions
	private func clearScreenFromRegions()
	{
		// Get all visible regions
		let sublayers = self.previewView.layer.sublayers

		// Remove all layers with name - TextRegionsLayer
		for layer in sublayers! {
			if layer.name == RTRTextRegionsLayerName {
				layer.removeFromSuperlayer()
			}
		}
	}

	private func scaledPoint(cMocrPoint mocrPoint: NSValue) -> CGPoint
	{
		let layerWidth = self.previewLayer?.bounds.width
		let layerHeight = self.previewLayer?.bounds.height

		let widthScale = layerWidth! / ImageBufferSize.width
		let heightScale = layerHeight! / ImageBufferSize.height


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
			let attributes = [NSAttributedStringKey.font: UIFont.boldSystemFont(ofSize: fontSize)]
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
		if !self.selectedRecognitionLanguages.contains(language) {
			self.selectedRecognitionLanguages.insert(language)
		} else {
			self.selectedRecognitionLanguages.remove(language)
		}

		self.recognizeLanguageButton.title = self.languagesButtonTitle()
		tableView .reloadRows(at: [indexPath], with: UITableViewRowAnimation.automatic)
	}

//# MARK: - UITableViewDatasource

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
	{
		return RecognitionLanguages.count
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
	{
		let cell = UITableViewCell(style: UITableViewCellStyle.default, reuseIdentifier: nil)
		let language = RecognitionLanguages[indexPath.row]
		cell.textLabel?.text = language
		cell.accessoryType = self.selectedRecognitionLanguages.contains(language) ? UITableViewCellAccessoryType.checkmark : UITableViewCellAccessoryType.none
		cell.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.4)
		cell.textLabel?.textColor = UIColor.white
		cell.tintColor = UIColor.white
		return cell
	}

//# MARK: - Notifications

	@objc
	func avSessionFailed(_ notification: NSNotification)
	{
		let alertView = UIAlertView(title: "AVSession Failed!", message: nil, delegate: nil, cancelButtonTitle:"OK")
		alertView.show()
	}

	@objc
	func applicationDidEnterBackground(_ notification: NSNotification)
	{
		self.session?.stopRunning()
		self.clearScreenFromRegions()
		self.whiteBackgroundView.isHidden = true
		self.textCaptureService?.stopTasks()
		self.captureButton.isSelected = true
		self.isRunning = false
	}

	@objc
	func applicationWillEnterForeground(_ notification: NSNotification)
	{
		self.session?.startRunning()
	}


//# MARK: - Actions

	@IBAction func onReconitionLanguages(_ sender: AnyObject)
	{
		if self.languagesTableView.isHidden {
			self.isRunning = false
			self.captureButton.isSelected = false
			self.languagesTableView.reloadData()
			self.languagesTableView.isHidden = false
		} else {
			self.tryToCloseLanguagesTable()
		}
	}

	@IBAction func capturePressed(_ sender: AnyObject)
	{
		if !self.captureButton.isEnabled {
			return
		}

		self.captureButton.isSelected = !self.captureButton.isSelected
		self.isRunning = self.captureButton.isSelected

		if self.isRunning {
			self.prepareUIForRecognition()
			self.session?.startRunning()
		} else {
			self.textCaptureService?.stopTasks()
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
		if !self.isRunning {
			return
		}
		
		// Image is prepared
		let orientation = UIApplication.shared.statusBarOrientation
		connection.videoOrientation = self.videoOrientation(orientation)
		
		self.textCaptureService?.add(sampleBuffer)
	}
}

extension RTRViewController: RTRTextCaptureServiceDelegate
{
	func onBufferProcessed(with textLines: [RTRTextLine]!, resultStatus: RTRResultStabilityStatus)
	{
		self.performBlockOnMainThread(0) { 
			if !self.isRunning {
				return
			}
			
			self.progressIndicatorView!.setProgress(resultStatus.rawValue, self.progressColor(resultStatus))
			
			if resultStatus == RTRResultStabilityStatus.stable {
				self.isRunning = false
				self.captureButton.isSelected = false
				self.whiteBackgroundView.isHidden = false
				self.textCaptureService?.stopTasks()
			}
			
			self.drawTextLines(textLines, resultStatus)
		}
	}
	
	func onWarning(_ warningCode: RTRCallbackWarningCode)
	{
		let message = self.stringFromWarningCode(warningCode);
		if message.count > 0 {
			if(!self.isRunning) {
				return;
			}
			
			self.updateLogMessage(message);
			
			// Clear message after 2 seconds.
			performBlockOnMainThread(2){
				self.updateLogMessage(nil)
			}
		}
	}
	
	func onError(_ error: Error!)
	{
		print(error.localizedDescription)
		performBlockOnMainThread(0) {
			
			if self.isRunning {
				
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
				
				self.updateLogMessage(description)
				self.isRunning = false
				self.captureButton.isSelected = false
				
			}

		}
		
	}
}
