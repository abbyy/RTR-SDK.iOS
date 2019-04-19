// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

import AVFoundation
import AbbyyRtrSDK

/// Info about a data capture scenario.
class RTRScenarioInfo : Equatable {
	static func == (lhs: RTRScenarioInfo, rhs: RTRScenarioInfo) -> Bool {
		return lhs.name == rhs.name
	}

	/// Scenario name.
	let name : String
	/// Description.
	let description : String
	/// Regular expression.
	let regEx : String?
	/// Recognition Language.
	let language : RTRLanguageName?

	init(name: String, description: String, regEx: String? = nil, language: RTRLanguageName? = nil)
	{
		self.name = name
		self.description = description
		self.regEx = regEx
		self.language = language
	}
}

// MARK: -

class RTRViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {

	/// Cell ID for tableView.
	private let RTRTableCellID = "RTRTableCellID"
	/// Name for text region layers.
	private let RTRTextRegionsLayerName = "RTRTextRegionLayerName"

	/// View with video preview layer
	@IBOutlet weak var previewView: UIView!
	/// Stop/Start capture button
	@IBOutlet weak var captureButton: UIButton!

	/// Scenarios table.
	@IBOutlet weak var tableView: UITableView!
	/// Button for show / hide table with scenarios.
	@IBOutlet weak var showSettingsButton: UIBarButtonItem!
	/// White view for highlight recognition results.
	@IBOutlet weak var whiteBackgroundView: UIView!
	/// View for displaying current area of interest.
	@IBOutlet weak var overlayView: RTRSelectedAreaView!
	
	/// Progress indicator view.
	@IBOutlet weak var progressIndicatorView: RTRProgressView?
	/// Label for error or warning info.
	@IBOutlet weak var infoLabel: UILabel!
	/// Label for description of the selected scenario.
	@IBOutlet weak var descriptionLabel: UILabel!

	/// Camera session.
	private var session: AVCaptureSession?
	/// Video preview layer.
	private var previewLayer: AVCaptureVideoPreviewLayer?
	/// Engine for AbbyyRtrSDK.
	private var engine: RTREngine?
	/// Service for runtime recognition.
	private var dataCaptureService: RTRDataCaptureService?
	// Recommended session preset.
	private let SessionPreset = AVCaptureSession.Preset.hd1920x1080
	private var ImageBufferSize = CGSize(width: 1080, height: 1920)
	
	/// Is recognition running.
	private var isRunning = true
	
	private var _scenarioPresets: Array<RTRScenarioInfo>?
	private var scenarioPresets: Array<RTRScenarioInfo> {
		get {
			if _scenarioPresets == nil {
				// BusinessCards.
				let businessCards = RTRScenarioInfo(name: "BusinessCards", description: "BusinessCards (EN)", language: RTRLanguageName.english )
				/// Number. A group of at least 2 digits (12, 345, 6789, 071570184356).
				let number = RTRScenarioInfo(name: "Number", description: "Integer number:  12  345  6789", regEx: "[0-9]{2,}", language: RTRLanguageName.english )
				/// Code. A group of digits mixed with letters of mixed capitalization.
				/// Requires at least one digit and at least one letter (X6YZ64, 32VPA, zyy777, 67xR5dYz).
				let code = RTRScenarioInfo(name: "Code", description: "Mix of digits with letters:  X6YZ64  32VPA  zyy777", regEx: "([a-zA-Z]+[0-9]+|[0-9]+[a-zA-Z]+)[0-9a-zA-Z]*", language: RTRLanguageName.english )
				/// PartID. Groups of digits and capital letters separated by dots or hyphens
				/// (002A-X345-D3-BBCD, AZ-553453-A34RRR.B, 003551.126663.AX).
				let partID = RTRScenarioInfo(name: "PartID", description: "Part or product id:  002A-X345-D3-BBCD  AZ-5-A34.B  001.123.AX", regEx: "[0-9a-zA-Z]+((\\.|-)[0-9a-zA-Z]+)+", language: RTRLanguageName.english )
				/// Area Code. A group of digits in round brackets (01), (23), (4567), (1349857157).
				let areaCode = RTRScenarioInfo(name: "AreaCode", description: "Digits in round brackets as found in phone numbers:  (01)  (23)  (4567)", regEx: "\\([0-9]+\\)", language: RTRLanguageName.english )
				/// Date. Chinese or Japanese date in traditional form (2017年1月19日, 925年12月31日, 1900年07月29日, 2008年8月8日).
				let date = RTRScenarioInfo(name: "ChineseJapaneseDate", description: "2008年8月8日", regEx: "[12][0-9]{3}年\\w*((0?[1-9])|(1[0-2]))月\\w*(([01]?[0-9])|(3[01]))日", language: RTRLanguageName.chineseSimplified )

				///	International Bank Account Number (DE, ES, FR, GB).
				let iban = RTRScenarioInfo(name: "IBAN", description: "International Bank Account Number (DE, ES, FR, GB)" )

				/// Machine Readable Zone in identity documents. Requires MRZ.rom to be present in patterns.
				let mrz = RTRScenarioInfo(name: "MRZ", description: "Machine Readable Zone in identity documents" )

				_scenarioPresets = [businessCards, number, code, partID, areaCode, date, iban, mrz]
			}
			return _scenarioPresets!
		}
	}

	/// Data capture settings.
	private var _selectedScenario: RTRScenarioInfo?
	private var selectedScenario: RTRScenarioInfo {
		get {
			if _selectedScenario == nil {
				_selectedScenario = scenarioPresets.first
			}
			return _selectedScenario!
		}
	}

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
		showSettingsButton.title = settingsButtonTitle()
		descriptionLabel.text = selectedScenario.description

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
		}
	}
	
	override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator)
	{
		let wasRunning = isRunning
		isRunning = false
		if let service = dataCaptureService {
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
		if let service = dataCaptureService {
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

	private func createDataCaptureService(scenarioInfo: RTRScenarioInfo) -> RTRDataCaptureService?
	{
		guard let engine = self.engine else { return nil }

		if let regEx = scenarioInfo.regEx {

			let service = engine.createDataCaptureService(with: self, profile: nil)!
			guard
				let builder = service.configureDataCaptureProfile()
			else {
				return nil
			}

			if let language = scenarioInfo.language {
				builder.setRecognitionLanguages([language.rawValue])
			}

			builder.addScheme(scenarioInfo.name)!.addField(scenarioInfo.name).setRegEx(regEx)
			builder.checkAndApply()

			return service

		} else {
			let service = engine.createDataCaptureService(with: self, profile: scenarioInfo.name)!

			if let language = scenarioInfo.language, let builder = service.configureDataCaptureProfile() {
				builder.setRecognitionLanguages([language.rawValue])
				builder.checkAndApply()
			}

			return service
		}
	}

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
		guard engine != nil else {
			captureButton.isEnabled = false;
			updateLogMessage("Invalid License")
			return
		}

		showSettingsButton.isEnabled = true
		
		configureAVCaptureSession()
		configurePreviewLayer()
		session?.startRunning()

		NotificationCenter.default.addObserver(self, selector:#selector(RTRViewController.avSessionFailed(_:)), name: NSNotification.Name.AVCaptureSessionRuntimeError, object: nil)
		NotificationCenter.default.addObserver(self, selector:#selector(RTRViewController.applicationDidEnterBackground(_:)), name: UIApplication.didEnterBackgroundNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector:#selector(RTRViewController.applicationWillEnterForeground(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)

		if let service = createDataCaptureService(scenarioInfo: selectedScenario) {
			dataCaptureService = service
			captureButtonPressed()
		}
	}

	private func configureAVCaptureSession()
	{
		self.session = AVCaptureSession()
		
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
			videoDataOutput.videoSettings = [String(kCVPixelBufferPixelFormatTypeKey): Int(kCVPixelFormatType_32BGRA)]
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
			if orientation.isPortrait {
				selectedArea = viewBounds.insetBy(dx: viewBounds.width / 15.0, dy: viewBounds.height / 3.0)
			} else {
				selectedArea = viewBounds.insetBy(dx: viewBounds.width / 8.0, dy: viewBounds.height / 8.0)
			}
			
			updateAreaOfInterest()
		}
	}

	private func updateAreaOfInterest()
	{
		// Scale area of interest from view coordinate system to image coordinates.
		let affineTransform = CGAffineTransform(scaleX: ImageBufferSize.width * 1.0 / overlayView.frame.width,
			y: ImageBufferSize.height * 1.0 / overlayView.frame.height)
		let selectedRect = selectedArea.applying(affineTransform)
		if let service = dataCaptureService {
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

	private func settingsButtonTitle() -> String
	{
		return selectedScenario.name
	}

	private func tryToCloseTable()
	{
		updateLogMessage("")
		tableView.isHidden = true
		descriptionLabel.isHidden = false

		if let service = createDataCaptureService(scenarioInfo: selectedScenario) {
			dataCaptureService = service
			captureButtonPressed()
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
		progressIndicatorView?.setProgress(0, progressColor(.notReady))
	}

//# MARK: - Drawing result

	private func drawDataFields(_ dataFields: [RTRDataField], _ progress:RTRResultStabilityStatus)
	{
		clearScreenFromRegions()
		for dataField in dataFields {
			drawLines(dataField.components ?? [], progress)
		}
	}

	private func drawLines(_ textLines: [RTRDataField], _ progress:RTRResultStabilityStatus)
	{
		if let previewLayer = self.previewLayer {
			let textRegionsLayer = CALayer()
			textRegionsLayer.frame = previewLayer.frame
			textRegionsLayer.name = RTRTextRegionsLayerName

			for textLine in textLines {
				drawLine(textLine, textRegionsLayer, progress)
			}

			previewView.layer.addSublayer(textRegionsLayer)
		}
	}

	func drawLine(_ textLine: RTRDataField, _ layer: CALayer, _ progress: RTRResultStabilityStatus)
	{
		let topLeft = scaledPoint(imagePoint: textLine.quadrangle[0] )
		let bottomLeft = scaledPoint(imagePoint: textLine.quadrangle[1])
		let bottomRight = scaledPoint(imagePoint: textLine.quadrangle[2])
		let topRight = scaledPoint(imagePoint: textLine.quadrangle[3])

		drawQuadrangle(topLeft, bottomLeft, bottomRight, topRight, layer, progress)

		let textLayer = CATextLayer()
		let textWidth = distanceBetween(topLeft, topRight)
		let textHeight = distanceBetween(topLeft, bottomLeft)
		let rectForTextLayer = CGRect(x: bottomLeft.x, y: bottomLeft.y, width: textWidth, height: textHeight) 

		// Selecting the initial font size by rectangle
		let textFont = font(string: textLine.text, rect: rectForTextLayer)
		textLayer.font = textFont
		textLayer.fontSize = textFont.pointSize
		textLayer.foregroundColor = progressColor(progress).cgColor
		textLayer.alignmentMode = CATextLayerAlignmentMode.center
		textLayer.string = textLine.text
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
		_selectedScenario = scenarioPresets[indexPath.row]
		showSettingsButton.title = settingsButtonTitle()
		descriptionLabel.text = selectedScenario.description
		tryToCloseTable()
	}

//# MARK: - UITableViewDatasource

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
	{
		return scenarioPresets.count
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
	{
		let cellId = "cell id"
		var cell: UITableViewCell! = tableView.dequeueReusableCell(withIdentifier: cellId)
		if cell == nil {
			cell = UITableViewCell(style: UITableViewCell.CellStyle.subtitle, reuseIdentifier: cellId)
		}
		let scenario = scenarioPresets[indexPath.row]
		cell.textLabel?.text = scenario.name
		cell.detailTextLabel?.text = scenario.description
		cell.accessoryType = selectedScenario == scenario ? UITableViewCell.AccessoryType.checkmark : UITableViewCell.AccessoryType.none
		cell.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.4)
		cell.textLabel?.textColor = UIColor.white
		cell.detailTextLabel?.textColor = UIColor.white
		cell.tintColor = UIColor.white
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

		if let service = dataCaptureService {
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

	@IBAction func onSettingsButtonPressed()
	{
		if tableView.isHidden {
			isRunning = false
			captureButton.isSelected = false
			descriptionLabel.isHidden = true
			tableView.reloadData()
			tableView.isHidden = false
		} else {
			tryToCloseTable()
		}
	}

	@IBAction func captureButtonPressed()
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
			if let service = dataCaptureService {
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

	private func nextCamera() -> AVCaptureDevice?
	{
		if let session = self.session {
			if let input = session.inputs.first as? AVCaptureDeviceInput {
				let currentDevice = input.device
				let devices = AVCaptureDevice.devices(for: .video)
				if let index = devices.index(where: { $0 === currentDevice }) {
					return devices[((index + 1) % devices.count)];
				} else {
					return devices.first
				}
			}
		}
		return nil
	}

	private func switchSessionInput()
	{
		if let session = self.session {
			if let newCamera = nextCamera() {
				if let newCameraInput = try? AVCaptureDeviceInput.init(device: newCamera) {
					if let currentCameraInput = session.inputs.first as? AVCaptureDeviceInput {
						session.beginConfiguration()
						session.removeInput(currentCameraInput)
						if session.canAddInput(newCameraInput) {
							session.addInput(newCameraInput)
						} else {
							session.addInput(currentCameraInput)
							updateLogMessage("Cannot switch camera with current configuration.")
							DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1) { [weak self] in
								self?.updateLogMessage("")
							}
						}
						session.commitConfiguration()
					}
				}
			}
		}
	}

	@IBAction func switchCamera()
	{
		switchSessionInput();
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

		if let service = dataCaptureService {
			service.add(sampleBuffer)
		}
	}
}

extension RTRViewController: RTRDataCaptureServiceDelegate
{
	func onBufferProcessed(with dataScheme: RTRDataScheme, dataFields: [RTRDataField], resultStatus: RTRResultStabilityStatus)
	{
		if !isRunning {
			return
		}

		if let progress = progressIndicatorView {
			progress.setProgress(resultStatus.rawValue, progressColor(resultStatus))
		}

		if resultStatus == .stable {
			isRunning = false
			captureButton.isSelected = false
			whiteBackgroundView.isHidden = false
			if let service = dataCaptureService {
				service.stopTasks()
			}
		}

		drawDataFields(dataFields, resultStatus)
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
