/// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
/// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.


import AVFoundation
import AbbyyRtrSDK

// MARK: -

class RTRViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {

	/// Open Photo Library button.
	@IBOutlet weak var selectImageButton: UIButton!

	@IBOutlet weak var actionsButton: UIBarButtonItem!
	/// Table with settings.
	@IBOutlet weak var tableView: UITableView!
	/// Button for show / hide table with settings.
	@IBOutlet weak var showSettingsButton: UIBarButtonItem!

	/// Label for error or warning info.
	@IBOutlet weak var infoLabel: UILabel!

	/// Text view for recognized text.
	@IBOutlet weak var textView: UITextView!
	/// Recognition progress view.
	@IBOutlet weak var progressView: UIProgressView!

	/// Stores selected image for re-recognition on languages changing.
	var selectedImage: UIImage!

	/// Engine for AbbyyRtrSDK.
	private var engine: RTREngine?
	/// Instance for core functionality.
	private var coreAPI: RTRCoreAPI?
	private var lastTaskNumber = 0
	/// Selected recognition languages.
	private var selectedRecognitionLanguages = Set([RTRLanguageName.english])

	/// Available recognition languages.
	private let recognitionLanguages: [RTRLanguageName] = [
		.chineseSimplified,
		.chineseTraditional,
		.english,
		.french,
		.german,
		.italian,
		.japanese,
		.korean,
		.polish,
		.portugueseBrazilian,
		.russian,
		.spanish
	]
	
	let avaliableScenarios = [
		"Text",
		"BusinessCards"
	]
	
	enum TableState {
		case scenarios
		case languages
		case none
	}
	
	private var currentCoreAPIScenario = "Text"
	private var currentTableState: TableState = .none {
		willSet {
			if currentTableState != .none {
				tryToCloseSettingsTable()
			}
		}
		didSet {
			DispatchQueue.main.async { [weak self] in
				self?.changeTableVisibilty()
			}
		}
	}
	
	private var tableContent: [String] = []

// MARK: - LifeCycle

	override func viewDidLoad()
	{
		super.viewDidLoad()

		actionsButton.isEnabled = true
		
		tableView.tableFooterView = UIView(frame: CGRect.zero)
		tableView.isHidden = true

		showSettingsButton.title = settingsButtonTitle()
		textView.text = ""

		progressView.setProgress(0, animated: false)

		let licensePath = (Bundle.main.bundlePath as NSString).appendingPathComponent("license")
		let licenseUrl = URL.init(fileURLWithPath: licensePath)
		if let data = try? Data(contentsOf: licenseUrl) {
			engine = RTREngine.sharedEngine(withLicense: data)
		}

		guard let _ = engine else {
			selectImageButton.isEnabled = false;
			updateLogMessage("Invalid License")
			return
		}
	}

	override var prefersStatusBarHidden: Bool
	{
		return true
	}

// MARK: - Private

	private func settingsButtonTitle() -> String
	{
		if self.selectedRecognitionLanguages.count == 1 {
			return self.selectedRecognitionLanguages.first!.rawValue
		}

		var languageCodes = [String]()

		for language in self.selectedRecognitionLanguages {
			let index = language.rawValue.index(language.rawValue.startIndex, offsetBy: 2)
			languageCodes.append(String(language.rawValue[..<index]))
		}

		return languageCodes.joined(separator: " ")
	}

	private func changeTableVisibilty()
	{
		switch currentTableState {
		case .scenarios:
			tableContent = avaliableScenarios
		case .languages:
			tableContent = recognitionLanguages.map{ $0.rawValue }
		default:
			tableContent = []
		}
		
		tableView.reloadData()
		tableView.isHidden = currentTableState == .none
	}

	private func tryToCloseSettingsTable()
	{
		if selectedRecognitionLanguages.isEmpty {
			selectedRecognitionLanguages.insert(.english)
		}

		showSettingsTable(show: false);
		showSettingsButton.title = settingsButtonTitle()

		if let image = selectedImage {
			recognizeImage(image)
		}
	}

	private func showSettingsTable(show: Bool)
	{
		tableView.isHidden = !show
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

// MARK: - UITableViewDelegate

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
	{
		switch currentTableState {
		case .languages:
			updateEnabledLanguages(with: RTRLanguageName(tableContent[indexPath.row]), indexPath: indexPath)
		case .scenarios:
			updateScenario(with: tableContent[indexPath.row])
		default:
			break
		}
	}
	
	private func updateEnabledLanguages(with language: RTRLanguageName, indexPath: IndexPath) {
		if !selectedRecognitionLanguages.contains(language) {
			selectedRecognitionLanguages.insert(language)
		} else {
			selectedRecognitionLanguages.remove(language)
		}
		showSettingsButton.title = settingsButtonTitle()
		tableView.reloadRows(at: [indexPath], with: .automatic)
	}
	
	private func updateScenario(with scenario: String) {
		currentCoreAPIScenario = scenario
		actionsButton.title = scenario
		tableView.reloadData()
		currentTableState = .none
	}

// MARK: - UITableViewDatasource

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
	{
		return tableContent.count
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
	{
		let cellId = "cell id"
		var cell: UITableViewCell! = tableView.dequeueReusableCell(withIdentifier: cellId)
		if cell == nil {
			cell = UITableViewCell(style: UITableViewCell.CellStyle.subtitle, reuseIdentifier: cellId)
		}

		let title = tableContent[indexPath.row]
		cell.textLabel?.text = title
		
		switch currentTableState {
		case .languages:
			cell.accessoryType = selectedRecognitionLanguages.contains(RTRLanguageName(title)) ? .checkmark : .none
		case .scenarios:
			cell.accessoryType = title == currentCoreAPIScenario ? .checkmark : .none
		default:
			break
		}
		cell.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.4)
		cell.textLabel?.textColor = .white
		cell.tintColor = .white
		return cell
	}

// MARK: - Actions

	@IBAction func onSettingsButtonPressed()
	{
		if currentTableState == .languages {
			currentTableState = .none
		} else {
			currentTableState = .languages
		}
	}
	
	
	@IBAction func onChangeAction(_ sender: Any)
	{
		if currentTableState == .scenarios {
			currentTableState = .none
		} else {
			currentTableState = .scenarios
		}
	}
	
	@IBAction func onSelectImageButtonPressed()
	{
		if !selectImageButton.isEnabled {
			return
		}

		let imagePicker: UIImagePickerController = UIImagePickerController.init()
		imagePicker.sourceType = .savedPhotosAlbum
		imagePicker.delegate = self
		imagePicker.modalPresentationStyle = .fullScreen

		present(imagePicker, animated: true, completion: nil)
	}

// MARK: -

	func recognizeImage(_ image: UIImage)
	{
		textView.text = ""
		infoLabel.text = ""
		
		guard let engine = engine else { return }
		coreAPI = engine.createCoreAPI()
		lastTaskNumber += 1
		let currentTaskNumber = lastTaskNumber

		weak var weakSelf = self
		let progressBlock: (NSInteger, RTRCallbackWarningCode) -> Bool = { percentage, warningCode in
			guard currentTaskNumber == weakSelf?.lastTaskNumber else {
				return false
			}
			DispatchQueue.main.async {
				if let strongSelf = weakSelf {
					strongSelf.progressView.setProgress(Float(percentage) / 100.0, animated: true)
					strongSelf.onWarning(warningCode)
				}
			}
			return true;
		};
		
		let textActionBlock = {
			guard let coreAPI = weakSelf?.coreAPI else { return }
			do {
				let result = try coreAPI.recognizeText(on: image, onProgress: progressBlock, onTextOrientationDetected: nil)
				
				DispatchQueue.main.async {
					if let strongSelf = weakSelf, strongSelf.lastTaskNumber == currentTaskNumber {
						strongSelf.showTextBlocks(result);
						strongSelf.progressView.setProgress(1, animated: true)
						strongSelf.progressView.setProgress(0, animated: false)
					}
				}
			} catch let error as NSError {
				DispatchQueue.main.async {
					if let strongSelf = weakSelf {
						strongSelf.onError(error)
					}
				}
			}
		}
		
		let bcrActionBlock = {
			guard let coreAPI = weakSelf?.coreAPI else { return }
			do {
				let result = try coreAPI.extractData(from: image, onProgress: progressBlock, onTextOrientationDetected: nil)
				
				DispatchQueue.main.async {
					if let strongSelf = weakSelf, strongSelf.lastTaskNumber == currentTaskNumber {
						strongSelf.showDataFields(dataFields: result)
						strongSelf.progressView.setProgress(1, animated: true)
						strongSelf.progressView.setProgress(0, animated: false)
					}
					
				}
			} catch let error as NSError {
				DispatchQueue.main.async {
					if let strongSelf = weakSelf {
						strongSelf.onError(error)
					}
				}
			}
		}

		DispatchQueue.global(qos: .default).async {
			guard let strongSelf = weakSelf else { return }
			let selectedLanguages = strongSelf.selectedRecognitionLanguages
			switch strongSelf.currentCoreAPIScenario {
			case "Text":
				strongSelf.coreAPI?.textRecognitionSettings.setRecognitionLanguages(Set(selectedLanguages.map{ $0.rawValue }))
				textActionBlock()
			case "BusinessCards":
				_ = strongSelf.coreAPI?.dataCaptureSettings.configureDataCaptureProfile()?.setRecognitionLanguages(Set(selectedLanguages.map{ $0.rawValue }))
				bcrActionBlock()
			default:
				break
			}
		}
	}

	func onError(_ error: Error)
	{
		print(error.localizedDescription)

		var description = error.localizedDescription
		if description.contains("ChineseJapanese.rom") {
			description = "Chineze, Japanese and Korean are available in EXTENDED version only. Contact us for more information."
		} else if description.contains("KoreanSpecific.rom") {
			description = "Chineze, Japanese and Korean are available in EXTENDED version only. Contact us for more information."
		} else if description.contains("Russian.edc") {
			description = "Cyrillic script languages are available in EXTENDED version only. Contact us for more information."
		}

		updateLogMessage(description)
	}

	func onWarning(_ warningCode: RTRCallbackWarningCode)
	{
		let message = stringFromWarningCode(warningCode);
		updateLogMessage(message);
	}

	func showTextBlocks(_ textBlocks: [RTRTextBlock])
	{
		var text = ""
		for block in textBlocks {
			for textLine in block.textLines {
				text += textLine.text + "\n"
			}
		}
		textView.text = text
	}
	
	func showDataFields(dataFields: [RTRDataField])
	{
		textView.text = dataFields.map { "\($0.name ?? ""): \($0.text)" }.joined(separator: "\n")
	}

	/// Human-readable descriptions for the RTRCallbackWarningCode constants.
	func stringFromWarningCode(_ warningCode: RTRCallbackWarningCode) -> String
	{
		var warningString = ""
		switch warningCode {
		case .textTooSmall:
			warningString = "Text is too small."

		case .recognitionIsSlow:
			warningString = "The image is being recognized too slowly, perhaps something is going wrong."

		case .probablyLowQualityImage:
			warningString = "The image probably has low quality."

		case .probablyWrongLanguage:
			warningString = "The chosen recognition language is probably wrong."

		case .wrongLanguage:
			warningString = "The chosen recognition language is wrong."

		case .noWarning:
			break
		}
		return warningString
	}
}

// MARK: -

extension RTRViewController: UINavigationControllerDelegate
{
}

// MARK: -

extension RTRViewController: UIImagePickerControllerDelegate
{
	func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any])
	{
		if let image = info[UIImagePickerController.InfoKey.originalImage] {
			selectedImage = image as? UIImage

			weak var weakSelf = self

			let completion:() -> Void = {
				picker.presentingViewController?.dismiss(animated: true) {
					if let strongSelf = weakSelf {
						strongSelf.recognizeImage(strongSelf.selectedImage)
					}
				}
			}

			if(Thread.isMainThread) {
				completion();
			} else {
				DispatchQueue.main.async {
					completion()
				}
			}
		}
	}

	func imagePickerControllerDidCancel(_ picker: UIImagePickerController)
	{
		picker.presentingViewController?.dismiss(animated: true, completion: nil)
	}
}
