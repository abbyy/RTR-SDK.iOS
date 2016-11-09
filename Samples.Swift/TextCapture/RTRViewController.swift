// Copyright (C) ABBYY (BIT Software), 1993 - 2014. All rights reserved.
// Author: Sasha Mertvetsov

import UIKit
import AVFoundation


class RTRViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, AVCaptureVideoDataOutputSampleBufferDelegate, RTRRecognitionServiceDelegate {
    
    /// Cell ID for languagesTableView
    private let AFTVideoScreenCellName = "VideoScreenCell"
    private let AFTTextRegionsLayerName = "TextRegionsLayer"
    
    /// View with video preview layer
    @IBOutlet weak var previewView: UIView!
    /// Stop/Start capture button
    @IBOutlet weak var captureButton: UIButton!
    
    /// Recognition languages table
    @IBOutlet weak var languagesTableView: UITableView!
    @IBOutlet weak var recognizeLanguageButton: UIBarButtonItem!
    
    @IBOutlet weak var whiteBackgroundView: UIView!
    @IBOutlet weak var overlayView: RTRSelectedAreaView!
    
    private var session: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var engine: RTREngine?
    private var textCaptureService: RTRRecognitionService?
    private var selectedRecognitionLanguages = Set(["English"])
    
    private let SessionPreset = AVCaptureSessionPreset1280x720
    private let ImageBufferSize = CGSize(width: 720, height: 1280)
    
    private let RecognitionLanguages = ["English",
                                        "French",
                                        "German",
                                        "Italian",
                                        "Polish",
                                        "PortugueseBrazilian",
                                        "Russian",
                                        "Spanish",
                                        "ChineseSimplified",
                                        "ChineseTraditional",
                                        "Japanese",
                                        "Korean"]
    
    private var selectedArea: CGRect = CGRect.zero {
        didSet {
            self.overlayView.selectedArea = selectedArea
        }
    }

//# MARK: - LifeCycle

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let licensePath = (Bundle.main.bundlePath as NSString).appendingPathComponent("license")

        self.engine = RTREngine.sharedEngine(withLicense: NSData(contentsOfFile: licensePath) as Data!)
        assert(self.engine != nil)
        
        self.textCaptureService = self.engine?.createTextCaptureService(with: self)
        self.textCaptureService?.setRecognitionLanguages(selectedRecognitionLanguages)
        
        self.languagesTableView.register(UITableViewCell.self, forCellReuseIdentifier: AFTVideoScreenCellName)
        self.languagesTableView.tableFooterView = UIView(frame: CGRect.zero)
        self.languagesTableView.isHidden = true
        
        self.captureButton.isSelected = false
        self.captureButton.setTitle("Stop", for: UIControlState.selected)
        self.captureButton.setTitle("Start", for: UIControlState.normal)
        
        let recognizeLanguageButtonTitle = self.languagesButtonTitle()
        self.recognizeLanguageButton.title = recognizeLanguageButtonTitle
        
        let status = AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo)
        
        switch status {
        case AVAuthorizationStatus.authorized:
            self.configureCompletionAccess(true)
            break
        
        case AVAuthorizationStatus.notDetermined:
            AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo, completionHandler: { (granted) in
                DispatchQueue.main.async {
                    self.configureCompletionAccess(granted)
                }
            })
            break
            
        case AVAuthorizationStatus.restricted,
             AVAuthorizationStatus.denied:
            self.configureCompletionAccess(false)
            break
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        self.session?.stopRunning()
        self.captureButton.isSelected = false
        
        super.viewWillDisappear(animated)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        self.updatePreviewLayerFrame()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }

//# MARK: - Private
    
    func configureCompletionAccess(_ accessGranted: Bool) {
        if !UIImagePickerController.isCameraDeviceAvailable(UIImagePickerControllerCameraDevice.rear) {
            self.captureButton.isEnabled = false
            print("Device has no camera")
            return
        }
        
        if !accessGranted {
            self.captureButton.isEnabled = false
            print("Camera access denied")
            return
        }
        
        self.configureAVCaptureSession()
        self.configurePreviewLayer()
        self.session?.startRunning()
        
        NotificationCenter.default.addObserver(self, selector:#selector(RTRViewController.avSessionFailed(_:)),
                                               name: NSNotification.Name.AVCaptureSessionRuntimeError, object: nil)
        NotificationCenter.default.addObserver(self, selector:#selector(RTRViewController.applicationDidEnterBackground(_:)),
                                               name: NSNotification.Name.UIApplicationDidEnterBackground, object: nil)
        NotificationCenter.default.addObserver(self, selector:#selector(RTRViewController.applicationWillEnterForeground(_:)),
                                               name: NSNotification.Name.UIApplicationWillEnterForeground, object: nil)
        
        self.capturePressed("" as AnyObject)
    }

    private func configureAVCaptureSession() {
        self.session = AVCaptureSession()
        self.session?.sessionPreset = SessionPreset
        
        let device = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeVideo)
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            assert((self.session?.canAddInput(input))!, "impossible to add AVCaptureDeviceInput")
            self.session?.addInput(input)
        } catch let error as NSError {
            print(error.localizedDescription)
        }
        
        let videoDataOutput = AVCaptureVideoDataOutput()
        let videoDataOutputQueue = DispatchQueue(label: "videodataqueue", attributes: .concurrent)
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        
        videoDataOutput.videoSettings = NSDictionary(object: Int(kCVPixelFormatType_32BGRA),
                                                     forKey: kCVPixelBufferPixelFormatTypeKey as! NSCopying) as [NSObject : AnyObject]

        assert((self.session?.canAddOutput(videoDataOutput))!, "impossible to add AVCaptureVideoDataOutput")
        self.session?.addOutput(videoDataOutput)
        
        let connection = videoDataOutput.connection(withMediaType: AVMediaTypeVideo)
        connection?.isEnabled = true
    }
    
    private func configurePreviewLayer() {
        self.previewLayer = AVCaptureVideoPreviewLayer(session: self.session)
        self.previewLayer?.backgroundColor = UIColor.black.cgColor
        self.previewLayer?.videoGravity = AVLayerVideoGravityResize
        let rootLayer = self.previewView.layer
        rootLayer .insertSublayer(self.previewLayer!, at: 0)
        
        self.updatePreviewLayerFrame()
    }
    
    private func updatePreviewLayerFrame() {
        let orientation = UIApplication.shared.statusBarOrientation
        self.previewLayer?.connection.videoOrientation = self.videoOrientation(orientation)
        let viewBounds = self.view.bounds
        self.previewLayer?.frame = viewBounds
        self.selectedArea = viewBounds.insetBy(dx: viewBounds.width/8.0, dy: viewBounds.height/3.0)
        
        self.updateAreaOfInterest()
    }
    
    private func updateAreaOfInterest() {
        let affineTransform = CGAffineTransform(scaleX: self.ImageBufferSize.width * 1.0 / self.overlayView.frame.width, y: self.ImageBufferSize.height * 1.0 / self.overlayView.frame.height)
        let selectedRect = self.selectedArea.applying(affineTransform)
        self.textCaptureService?.setAreaOfInterest(selectedRect)
    }
    
    private func videoOrientation(_ orientation: UIInterfaceOrientation) -> AVCaptureVideoOrientation {
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

    private func languagesButtonTitle() -> String {
        if self.selectedRecognitionLanguages.count == 1 {
            return self.selectedRecognitionLanguages.first!
        }
        
        var languageCodes = [String]()
        
        for language in self.selectedRecognitionLanguages {
            let index = language.index(language.startIndex, offsetBy: 2)
            languageCodes.append(language.substring(to: index))
        }
        
        return languageCodes.joined(separator: " ")
    }
    
    private func tryToCloseLanguagesTable() {
        if self.selectedRecognitionLanguages.isEmpty {
            return
        }
        
        self.textCaptureService?.setRecognitionLanguages(self.selectedRecognitionLanguages)
        self.capturePressed("" as AnyObject)
        self.languagesTableView.isHidden = true
    }
    
//# MARK: - Drawing CMocrAreas
    
    private func processMocr(_ areas: [RTRTextLine], _ mergeStatus:RTRResultStabilityStatus) {
        DispatchQueue.main.async {
            if !self.captureButton.isSelected {
                return
            }
            
            if mergeStatus == RTRResultStabilityStatus.stable {
                self.captureButton.isSelected = false
                self.whiteBackgroundView.isHidden = false
                self.session?.stopRunning()
            }
            
            self.drawMocr(areas, mergeStatus) 
        }
    }
    
    private func drawMocr(_ areas: [RTRTextLine], _ progress:RTRResultStabilityStatus) {
        self.clearScreenFromRegions()
        
        let textRegionsLayer = CALayer()
        textRegionsLayer.frame = self.previewLayer!.frame
        textRegionsLayer.name = AFTTextRegionsLayerName
        
        for textArea in areas {
            self.drawCMocrOnPhoto(textArea, textRegionsLayer, progress)
        }
        
        self.previewView.layer.addSublayer(textRegionsLayer)
    }
    
    ///Drawing rectangle by CMocrTextAreaOnPhoto object and layer with recognized text.
    func drawCMocrOnPhoto(_ textArea: RTRTextLine, _ layer: CALayer, _ progress: RTRResultStabilityStatus) {
        let topLeft = self.scaledPoint(cMocrPoint: textArea.quadrangle[0] as! NSValue) 
        let bottomLeft = self.scaledPoint(cMocrPoint: textArea.quadrangle[1] as! NSValue) 
        let bottomRight = self.scaledPoint(cMocrPoint: textArea.quadrangle[2] as! NSValue) 
        let topRight = self.scaledPoint(cMocrPoint: textArea.quadrangle[3] as! NSValue)
    
        //CMocrTextAreaOnPhoto.quadrangle is a projection of the rectangle in space on the screen plane
        self.drawQuadrangle(topLeft, bottomLeft, bottomRight, topRight, layer, progress) 
        
        let recognizedString = textArea.text 
        if recognizedString == nil {
            //If using findTextAreasOnImage - Don't draw layer with text
            return 
        }
        
        let textLayer = CATextLayer()
        let textWidth = self.distanceBetween(topLeft, topRight) 
        let textHeight = self.distanceBetween(topLeft, bottomLeft) 
        let rectForTextLayer = CGRect(x: bottomLeft.x, y: bottomLeft.y, width: textWidth, height: textHeight) 
        
        //Selecting the initial font size by rectangle
        let textFont = self.font(string: recognizedString!, rect: rectForTextLayer)
        textLayer.font = textFont
        textLayer.fontSize = textFont.pointSize
        textLayer.foregroundColor = self.progressColor(progress).cgColor
        textLayer.alignmentMode = kCAAlignmentCenter
        textLayer.string = recognizedString
        textLayer.frame = rectForTextLayer
        
        //Rotate the text layer
        let angle = asin((bottomRight.y - bottomLeft.y) / self.distanceBetween(bottomLeft, bottomRight))
        textLayer.anchorPoint = CGPoint(x: 0, y: 0)
        textLayer.position = bottomLeft
        textLayer.transform = CATransform3DRotate(CATransform3DIdentity, angle, 0, 0, 1)
        
        layer.addSublayer(textLayer)
    }
    
    func drawQuadrangle(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ layer: CALayer, _ progress: RTRResultStabilityStatus) {
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
    
    func progressColor(_ progress:RTRResultStabilityStatus) -> UIColor {
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
    
    ///  Remove all visible regions
    private func clearScreenFromRegions() {
        // Get all visible regions
        let sublayers = self.previewView.layer.sublayers
        
        // Remove all layers with name - TextRegionsLayer
        for layer in sublayers! {
            if layer.name == AFTTextRegionsLayerName {
                layer.removeFromSuperlayer()
            }
        }
    }
    
    private func scaledPoint(cMocrPoint mocrPoint: NSValue) -> CGPoint {
        let layerWidth = self.previewLayer?.bounds.width
        let layerHeight = self.previewLayer?.bounds.height
        
        let widthScale = layerWidth! / ImageBufferSize.width
        let heightScale = layerHeight! / ImageBufferSize.height
        
        
        var point = mocrPoint.cgPointValue
        point.x *= widthScale
        point.y *= heightScale
        
        return point
    }
    
    private func distanceBetween(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        let vector = CGVector(dx: p2.x - p1.x, dy: p2.y - p1.y) 
        return sqrt(vector.dx * vector.dx + vector.dy * vector.dy) 
    }
    
    private func font(string: String, rect: CGRect) -> UIFont {
        var minFontSize: CGFloat = 0.1
        var maxFontSize: CGFloat = 72.0
        var fontSize: CGFloat = minFontSize
        
        let rectSize = rect.size
        
        while true {
            let attributes = [NSFontAttributeName: UIFont.boldSystemFont(ofSize: fontSize)]
            let labelSize = (string as NSString).size(attributes: attributes)
            
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
    
//# MARK: - RTRRecognitionServiceDelegate
    // - (void)onBufferProcessedWithTextLines:(NSArray*)textLines resultStatus:(RTRResultStabilityStatus)resultStatus;
    func onBufferProcessed(withTextLines textLines: [Any]!, resultStatus: RTRResultStabilityStatus) {
        print("status %i areas %i", resultStatus, textLines.count)
        self.processMocr(textLines as! [RTRTextLine], resultStatus)
    }
    
    func recognitionProgress(_ progress: Int32, warningCode: RTRCallbackWarningCode) {
        switch warningCode {
        case RTRCallbackWarningCode.smallTextSizeInFindText:
            print("Text is too small")
            return
        }
    }
    
    func onError(_ error: Error!) {
        print(error.localizedDescription)
    }

//# MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        if !self.captureButton.isSelected {
            return
        }
        
        // Image is prepared
        let orientation = UIApplication.shared.statusBarOrientation
        connection.videoOrientation = self.videoOrientation(orientation)
        
        self.textCaptureService?.add(sampleBuffer)
    }
    
//# MARK: - UITableViewDelegate
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
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
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return RecognitionLanguages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: UITableViewCellStyle.default, reuseIdentifier: nil) 
        let language = RecognitionLanguages[indexPath.row]
        cell.textLabel?.text = language
        cell.accessoryType = self.selectedRecognitionLanguages.contains(language) ? UITableViewCellAccessoryType.checkmark
                                                                                  : UITableViewCellAccessoryType.none 
        return cell
    }
    
//# MARK: - Notifications
    
    func avSessionFailed(_ notification: NSNotification) {
        let alertView = UIAlertView(title: "AVSession Failed!", message: nil, delegate: nil, cancelButtonTitle:"OK")
        alertView.show()
    }
    
    func applicationDidEnterBackground(_ notification: NSNotification) {
        self.session?.stopRunning()
        self.clearScreenFromRegions()
        self.whiteBackgroundView.isHidden = true
        self.textCaptureService?.stopTasks()
        self.captureButton.isSelected = true
    }
    
    func applicationWillEnterForeground(_ notification: NSNotification) {
        self.session?.startRunning()
    }
    
    
//# MARK: - Actions
    
    @IBAction func onReconitionLanguages(_ sender: AnyObject) {
        if self.languagesTableView.isHidden {
            self.captureButton.isSelected = false
            self.languagesTableView.reloadData()
            self.languagesTableView.isHidden = false
        } else {
            self.tryToCloseLanguagesTable()
        }
    }
    
    @IBAction func capturePressed(_ sender: AnyObject) {
        if !self.captureButton.isEnabled {
            return
        }
        
        self.captureButton.isSelected = !self.captureButton.isSelected
        self.textCaptureService?.stopTasks()
        
        if self.captureButton.isSelected {
            self.clearScreenFromRegions()
            self.whiteBackgroundView.isHidden = true
        } else {
            self.session?.stopRunning()
        }
    }
}
