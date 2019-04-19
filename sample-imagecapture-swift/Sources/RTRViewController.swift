/// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
/// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

import AVFoundation
import AbbyyRtrSDK

/// Info about a document to be captured.
class RTRDocument : Equatable {
	static func == (lhs: RTRDocument, rhs: RTRDocument) -> Bool {
		return lhs.name == rhs.name
	}

	/// Display name.
	let name : String
	/// Physical size, mm.
	let size : CGSize
	/// Description.
	let description : String

	init(name: String, size: CGSize, description: String)
	{
		self.name = name
		self.size = size
		self.description = description
	}

	/// Are boundaries required, wait while a boundaries will be found.
	func areBoundariesRequired() -> Bool
	{
		return !size.equalTo(CGSize.zero)
	}

	/// If size is known we can specify it in crop operation.
	func isSizeKnown() -> Bool
	{
		return !size.equalTo(CGSize.zero)
			&& !size.equalTo(CGSize(width: Int.max, height: Int.max))
	}
}

// MARK: -

class RTRViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {

	/// View with video preview layer.
	@IBOutlet weak var previewView: UIView!
	/// Stop/Start capture button.
	@IBOutlet weak var captureButton: UIButton!

	/// Table with settings.
	@IBOutlet weak var tableView: UITableView!
	/// Button for show / hide table with settings.
	@IBOutlet weak var showSettingsButton: UIBarButtonItem!
	/// View for highlight results.
	@IBOutlet weak var blackBackgroundView: UIView!
	/// View for displaying current status.
	@IBOutlet weak var overlayView: RTRDrawResultsView!

	/// Label for error or warning info.
	@IBOutlet weak var infoLabel: UILabel!

	/// Label with description of current settings.
	@IBOutlet weak var descriptionLabel: UILabel!

	/// View to display captured image.
	@IBOutlet weak var capturedImageView: UIImageView!

	/// Camera session.
	private var session: AVCaptureSession?
	/// Video preview layer.
	private var previewLayer: AVCaptureVideoPreviewLayer?
	/// Engine for AbbyyRtrSDK.
	private var engine: RTREngine?
	/// Service for image capture.
	private var imageCaptureService: RTRImageCaptureService?
	// Recommended session preset.
	private let sessionPreset = AVCaptureSession.Preset.hd1920x1080
	private var imageBufferSize = CGSize(width: 1080, height: 1920)  {
		didSet {
			overlayView.imageBufferSize = imageBufferSize
		}
	}
	
	/// Is service running.
	private var isRunning = true

	/// Area of interest in view coordinates.
	private var selectedArea: CGRect = CGRect.zero

	private var _documentPresets: Array<RTRDocument>?
	private var documentPresets: Array<RTRDocument> {
		get {
			if _documentPresets == nil {
				/// Unknown size but require boundaries
				let documentWithBoundaries = RTRDocument(name: "DocumentWithBoundaries", size: CGSize(width: Int.max, height: Int.max), description: "Unknown size / Require boundaries" )
				/// A4 paper size for office documents (ISO)
				let a4 = RTRDocument(name: "A4", size: CGSize(width: 210, height: 297), description: "210×297 mm (ISO A4)" )
				/// Letter paper size for office documents (US Letter)
				let letter = RTRDocument(name: "Letter", size: CGSize(width: 215.9, height: 279.4), description: "215.9×279.4 mm (US Letter)" )
				/// International Business Card
				let businessCard = RTRDocument(name: "BusinessCard", size: CGSize(width: 53.98, height: 85.6), description: "53.98×85.6 mm (International)" )
				/// Unknown size / Optional boundaries
				let auto = RTRDocument(name: "Auto", size: CGSize.zero, description: "Unknown size / Optional boundaries" )

				_documentPresets = [documentWithBoundaries, a4, letter, businessCard, auto]
			}
			return _documentPresets!
		}
	}

	/// Document settings for capture.
	private var _selectedDocument: RTRDocument?
	private var selectedDocument: RTRDocument {
		get {
			if _selectedDocument == nil {
				_selectedDocument = documentPresets.first
			}
			return _selectedDocument!
		}
	}

// MARK: - LifeCycle
	
	deinit
	{
		NotificationCenter.default.removeObserver(self)
	}

	override func viewDidLoad()
	{
		super.viewDidLoad()

		tableView.tableFooterView = UIView(frame: CGRect.zero)
		tableView.isHidden = true
		
		prepareUIForStart()

		captureButton.isSelected = false
		captureButton.setTitle("Stop", for: UIControl.State.selected)
		captureButton.setTitle("Start", for: UIControl.State.normal)

		showSettingsButton.title = settingsButtonTitle()
		descriptionLabel.text = selectedDocument.description
		overlayView.imageBufferSize = imageBufferSize

		weak var weakSelf = self
		let completion:(Bool) -> Void = { granted in
			DispatchQueue.main.async {
				weakSelf?.configureCompletionAccess(granted)
			}
		}

		let status = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
		switch status {
			case .authorized:
				completion(true)

			case .notDetermined:
				AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler: { (granted) in
					DispatchQueue.main.async {
						completion(granted)
					}
				})

			case .restricted, .denied:
				completion(false)
		}
	}
	
	override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator)
	{
		let wasRunning = isRunning
		isRunning = false
		if let service = imageCaptureService {
			service.stopTasks()
		}
		overlayView.clear()

		weak var weakSelf = self
		coordinator.animate(alongsideTransition: nil) { (context) in
			if let strongSelf = weakSelf {
				let oldSize = strongSelf.imageBufferSize
				let newSize = CGSize(width:min(oldSize.width, oldSize.height), height:max(oldSize.width, oldSize.height))
				if(UIApplication.shared.statusBarOrientation.isLandscape) {
					strongSelf.imageBufferSize = CGSize(width:newSize.height, height:newSize.width)
				} else {
					strongSelf.imageBufferSize = newSize
				}
				strongSelf.isRunning = wasRunning
			}
		}
	}

	override func viewWillDisappear(_ animated: Bool)
	{
		isRunning = false
		captureButton.isSelected = false
		if let service = imageCaptureService {
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

	override var prefersStatusBarHidden: Bool
	{
		return true
	}

// MARK: - Private

	func configureCompletionAccess(_ accessGranted: Bool)
	{
		if !UIImagePickerController.isCameraDeviceAvailable(.rear) {
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
			captureButton.isEnabled = false
			updateLogMessage("Invalid License")
			return
		}
		
		showSettingsButton.isEnabled = true
		imageCaptureService = rtrEngine.createImageCaptureService(with: self)
		imageCaptureService?.setDocumentSize(selectedDocument.size)
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

		if let _session = session {
			_session.sessionPreset = sessionPreset

			if let device = AVCaptureDevice.default(for: AVMediaType.video) {
				do {
					let input = try AVCaptureDeviceInput(device: device)
					assert((_session.canAddInput(input)), "impossible to add AVCaptureDeviceInput")
					_session.addInput(input)

					if let port = input.ports.first, let format = port.formatDescription {
						let dimensions = CMVideoFormatDescriptionGetDimensions(format)
						imageBufferSize = CGSize.init(width:Int(dimensions.height), height:Int(dimensions.width))
					}
				} catch let error as NSError {
					updateLogMessage(error.localizedDescription)
				}

				do {
					try device.lockForConfiguration()
					if device.isExposureModeSupported(.continuousAutoExposure) {
						device.exposureMode = .continuousAutoExposure
					}

					if device.isFocusModeSupported(.continuousAutoFocus) {
						device.focusMode = .continuousAutoFocus
					}

					device.unlockForConfiguration()
				} catch let error as NSError {
					updateLogMessage(error.localizedDescription)
				}
			} else {
				updateLogMessage("Can't access device for capture video")
				return
			}
			
			let videoDataOutput = AVCaptureVideoDataOutput()
			let videoDataOutputQueue = DispatchQueue(label: "videodataqueue", attributes: .concurrent)
			videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
			videoDataOutput.videoSettings = [String(kCVPixelBufferPixelFormatTypeKey) : Int(kCVPixelFormatType_32BGRA)]
			assert((_session.canAddOutput(videoDataOutput)), "impossible to add AVCaptureVideoDataOutput")
			_session.addOutput(videoDataOutput)
			
			if let connection = videoDataOutput.connection(with: AVMediaType.video) {
				connection.isEnabled = true
				connection.videoOrientation = videoOrientation(UIApplication.shared.statusBarOrientation)
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
		if let previewLayer = previewLayer, let connection = previewLayer.connection {
			connection.videoOrientation = self.videoOrientation(orientation)
			let viewBounds = view.bounds
			previewLayer.frame = viewBounds
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
		return selectedDocument.name
	}

	private func changeSettingsTableVisibilty()
	{
		if tableView.isHidden {
			isRunning = false
			captureButton.isSelected = false
			tableView.reloadData()
			showSettingsTable(show: true)

		} else {
			capturePressed()
			showSettingsTable(show: false)
			showSettingsButton.title = settingsButtonTitle()
			descriptionLabel.text = selectedDocument.description
		}
	}

	private func showSettingsTable(show: Bool)
	{
		tableView.isHidden = !show
		descriptionLabel.isHidden = show
		updateLogMessage("")
	}
	
	private func updateLogMessage(_ message: String?)
	{
		if let _message = message {
			infoLabel.text = _message
		} else {
			infoLabel.text = ""
		}
	}
	
	func prepareUIForStart()
	{
		overlayView.clear()

		overlayView.isHidden = false
		infoLabel.text = ""
		blackBackgroundView.isHidden = true
		capturedImageView.isHidden = true
	}

// MARK: - UITableViewDelegate

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
	{
		_selectedDocument = documentPresets[indexPath.row]
		changeSettingsTableVisibilty()
	}

// MARK: - UITableViewDatasource

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
	{
		return documentPresets.count
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
	{
		let cellId = "cell id"
		var cell: UITableViewCell! = tableView.dequeueReusableCell(withIdentifier: cellId)
		if cell == nil {
			cell = UITableViewCell(style: UITableViewCell.CellStyle.subtitle, reuseIdentifier: cellId)
		}
		let document = documentPresets[indexPath.row]
		cell.textLabel?.text = document.name
		cell.detailTextLabel?.text = document.description
		cell.accessoryType = selectedDocument == document ? UITableViewCell.AccessoryType.checkmark : UITableViewCell.AccessoryType.none
		cell.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.4)
		cell.textLabel?.textColor = UIColor.white
		cell.detailTextLabel?.textColor = UIColor.white
		cell.tintColor = UIColor.white
		return cell
	}

// MARK: - Notifications

	@objc
	func avSessionFailed(_ notification: NSNotification)
	{
		DispatchQueue.main.async {
			var message = "AVSession Failed! "
			if let userInfo = notification.userInfo {
				if let error = userInfo[AVCaptureSessionErrorKey] {
					message = message + (error as! String)
				}
			}
			self.infoLabel.text = message
		}
	}

	@objc
	func applicationDidEnterBackground(_ notification: NSNotification)
	{
		session?.stopRunning()
		imageCaptureService?.stopTasks()
	}

	@objc
	func applicationWillEnterForeground(_ notification: NSNotification)
	{
		session?.startRunning()
	}


// MARK: - Actions

	@IBAction func onSettingsButtonPressed()
	{
		changeSettingsTableVisibilty()
	}

	@IBAction func capturePressed()
	{
		if !captureButton.isEnabled {
			return
		}

		captureButton.isSelected = !captureButton.isSelected
		isRunning = captureButton.isSelected

		if isRunning {
			imageCaptureService?.setDocumentSize(selectedDocument.size)
			prepareUIForStart()
			session?.startRunning()
		} else {
			imageCaptureService?.stopTasks()
		}
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

		let frameOrientation = self.videoOrientation(orientation)
		if connection.videoOrientation != frameOrientation {
			connection.videoOrientation = frameOrientation
			return
		}
		
		imageCaptureService?.add(sampleBuffer)
	}
}

// MARK: -

extension RTRViewController: RTRImageCaptureServiceDelegate
{
	func onBufferProcessed(with status: RTRImageCaptureStatus, result: RTRImageCaptureResult?)
	{
		if !isRunning {
			return
		}

		let capturedImage = result?.image
		let documentBoundary = result?.documentBoundary
		var isReadyForCapturing = capturedImage != nil
		if isReadyForCapturing {
			if selectedDocument.areBoundariesRequired() {
				if let boundary = documentBoundary {
					isReadyForCapturing = boundary.count != 0
				} else {
					isReadyForCapturing = false
				}
			}
		}

		if isReadyForCapturing {
			let isSizeKnown = selectedDocument.isSizeKnown()
			isRunning = false
			captureButton.isSelected = false
			imageCaptureService?.stopTasks()

			overlayView.clear()
			overlayView.isHidden = true
			blackBackgroundView.isHidden = false

			guard let rtrEngine = engine else {
				return
			}
			let capturedImageView = self.capturedImageView

			// 'Peek' feedback
			AudioServicesPlaySystemSound(1519)

			DispatchQueue.global(qos: DispatchQoS.QoSClass.default).async {
				var resultImage: UIImage = capturedImage!
				if let boundary = documentBoundary {
					if boundary.count != 0 {
						let coreAPI = rtrEngine.createCoreAPI()
						do {
							let rtrImage = try coreAPI.load(capturedImage!)
							let cropOperation = coreAPI.createCropOperation()
							cropOperation.documentBoundary = boundary
							if isSizeKnown {
								cropOperation.documentSize = result!.documentSize
							}
							let ok = cropOperation.apply(to: rtrImage)
							if ok {
								if let croppedImage = rtrImage.uiImage() {
									resultImage = croppedImage
								}
							} else {
								print(cropOperation.error?.localizedDescription ?? "")
							}
						} catch let error as NSError {
							print(error.localizedDescription)
						}
					}
				}
				DispatchQueue.main.async {
					capturedImageView?.image = resultImage
					capturedImageView?.isHidden = false
				}
			}
		} else {
			if let blocks = status.qualityAssessmentForOCRBlocks {
				overlayView.documentBoundary = status.documentBoundary
				overlayView.blocks = blocks
				overlayView.setNeedsDisplay()
			}
		}
	}
	
	func onError(_ error: Error)
	{
		print(error.localizedDescription)

		if isRunning {
			let description = error.localizedDescription
			updateLogMessage(description)
			isRunning = false
			captureButton.isSelected = false
		}
	}
}
