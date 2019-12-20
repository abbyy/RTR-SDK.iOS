// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

import UIKit
import AbbyyRtrSDK
import AbbyyUI

class DataLoadOperation: Operation {
	var image: UIImage?
	var loadingBlock: (() -> UIImage?)
	var loadingCompleteHandler: ((UIImage?) -> Void)?

	init(loadingBlock: @escaping (() -> UIImage?))
	{
		self.loadingBlock = loadingBlock
	}

	override func main()
	{
		if isCancelled { return }

		image = loadingBlock()
		if isCancelled { return }

		DispatchQueue.main.async { [self] in
			self.loadingCompleteHandler?(self.image)
		}
	}
}

//MARK: Utility class for working with image export using Mobile Capture SDK
class ImageExporter {
	enum ExportError: Error {
		case invalidLicense
		case writingFailure
		case cleanFailure
		case internalError
	}

	struct PdfExportStatus {
		enum Action: String {
			case fetching
			case writing
		}
		let pagesProcessed: Int
		let pagesCount: Int
		let currentAction: Action
	}

	var tmpDirectory = FileManager.default.temporaryDirectory

	func exportPdf(
		filename: String,
		pages: AUIMultiPageImageCaptureResult,
		progress: ((PdfExportStatus) -> Void)?) throws
	{
		do {
			let cache = try FileManager.default.contentsOfDirectory(atPath: tmpDirectory.path)
			for filename in cache {
				let filepath = tmpDirectory.appendingPathComponent(filename)
				try FileManager.default.removeItem(atPath: filepath.path)
			}
		} catch {
			throw ExportError.cleanFailure
		}

		guard let coreApi = RecognitionEngine.shared?.createCoreAPI() else {
			throw ExportError.invalidLicense
		}

		let tmpUrl = tmpDirectory.appendingPathComponent(filename)
		let stream = RTRFileOutputStream(filePath: tmpUrl.path)
		if let error = stream.error {
			throw error
		}
		let exportOperation = coreApi.createExport(toPdfOperation: stream)

		let ids = try pages.pages()

		for (index, id) in ids.enumerated() {
			var status = PdfExportStatus(pagesProcessed: index, pagesCount: ids.count, currentAction: .fetching)
			progress?(status)
			let image = try pages.loadImage(withId: id)

			status = PdfExportStatus(pagesProcessed: index, pagesCount: ids.count, currentAction: .writing)
			progress?(status)
			guard exportOperation.addPage(with: image) else {
				throw ExportError.writingFailure
			}
		}
		guard exportOperation.close() else {
			throw ExportError.writingFailure
		}
	}
}

//MARK: Utility class for working with captured documents
class DataStorage {
	let loadingQueue = OperationQueue()
	let exporter = ImageExporter()
	var loadingOperations: [Int: DataLoadOperation] = [:]
	var capturedImages: AUIMultiPageImageCaptureResult? {
		didSet {
			_imagesIdentifiers = nil
		}
	}

	var errorHandler: ((Error) -> Void)?

	var imagesIdentifiers: [String] {
		if _imagesIdentifiers == nil {
			if let capturedImages = capturedImages {
				do {
					_imagesIdentifiers = try capturedImages.pages()
				} catch {
					DispatchQueue.main.async { [weak self] in
						self?.errorHandler?(error)
					}
				}
			}
		}
		return _imagesIdentifiers ?? []
	}
	private var _imagesIdentifiers: [String]?

	fileprivate lazy var directory: URL = {
		return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
	}()

	var directoryPath: String {
		return directory.path
	}

	var directoryURL: URL {
		return directory
	}

	var itemsCount: Int {
		return imagesIdentifiers.count
	}

	func remove(at index: Int) -> Operation
	{
		let operation = BlockOperation {
			do {
				if let capturedImages = self.capturedImages {
					if (0 ..< self.imagesIdentifiers.count).contains(index) {
						try capturedImages.delete(withId: self.imagesIdentifiers[index])
						self._imagesIdentifiers?.remove(at: index)
					}
				}

			} catch {
				DispatchQueue.main.async { [weak self] in
					self?.errorHandler?(error)
				}
			}
		}
		return operation
	}

	func fetchThumbnail(at index: Int) -> DataLoadOperation
	{
		return fetchImage(at: index, fullSize: false)
	}

	func fetchResultImage(at index: Int) -> DataLoadOperation
	{
		return fetchImage(at: index, fullSize: true)
	}

	private func fetchImage(at index: Int, fullSize: Bool) -> DataLoadOperation
	{
		return DataLoadOperation(loadingBlock: { [weak self] () -> UIImage? in
			do {
				if let self = self {
					if let capturedImages = self.capturedImages {
						if (0 ..< self.imagesIdentifiers.count).contains(index) {
							var image: UIImage
							if fullSize {
								image = try capturedImages.loadImage(withId: self.imagesIdentifiers[index])
							} else {
								image = try capturedImages.loadThumbnail(withId: self.imagesIdentifiers[index])
							}
							return image
						}
					}
				}
				return .none
			} catch {
				if let self = self {
					DispatchQueue.main.async { [weak self] in
						self?.errorHandler?(error)
					}
				}
				return .none
			}
		})
	}

	func exportAsPdf(filename: String, progress: ((ImageExporter.PdfExportStatus) -> Void)?) throws
	{
		try exporter.exportPdf(filename: filename, pages: capturedImages!, progress: progress)
	}
}
