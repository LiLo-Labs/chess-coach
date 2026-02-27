import Foundation

/// Manages downloading and updating the on-device LLM model (GGUF).
/// Instead of bundling the ~3GB model in the app binary, this service downloads
/// it on demand when the user unlocks an AI tier.
@Observable
@MainActor
final class ModelDownloadService {
    enum DownloadState: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
        case failed(String)
    }

    private(set) var state: DownloadState = .notDownloaded
    private var downloadTask: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?

    /// Whether the model file exists in the Documents directory (downloaded) or app bundle.
    var isModelAvailable: Bool {
        Self.downloadedModelPath != nil || Self.bundledModelPath != nil
    }

    /// Path to the model file — prefers downloaded (Documents) over bundled.
    var modelPath: String? {
        Self.downloadedModelPath ?? Self.bundledModelPath
    }

    init() {
        // Check initial state
        if Self.downloadedModelPath != nil || Self.bundledModelPath != nil {
            state = .downloaded
        }
    }

    // MARK: - Download

    func startDownload() {
        guard case .notDownloaded = state else { return }
        guard let url = URL(string: AppConfig.modelDownload.remoteURL) else {
            state = .failed("Invalid download URL")
            return
        }

        state = .downloading(progress: 0)

        let session = URLSession(configuration: .default)
        let task = session.downloadTask(with: url) { [weak self] tempURL, response, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let error {
                    self.state = .failed(error.localizedDescription)
                    return
                }

                guard let tempURL, let response = response as? HTTPURLResponse,
                      response.statusCode == 200 else {
                    self.state = .failed("Download failed — server returned an error")
                    return
                }

                // Move to Documents
                do {
                    let dest = Self.documentsModelURL
                    let fm = FileManager.default
                    if fm.fileExists(atPath: dest.path) {
                        try fm.removeItem(at: dest)
                    }
                    try fm.moveItem(at: tempURL, to: dest)
                    self.state = .downloaded
                    #if DEBUG
                    print("[ChessCoach] Model downloaded to \(dest.path)")
                    #endif
                } catch {
                    self.state = .failed("Failed to save model: \(error.localizedDescription)")
                }
            }
        }

        // Observe progress
        progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            Task { @MainActor [weak self] in
                self?.state = .downloading(progress: progress.fractionCompleted)
            }
        }

        task.resume()
        downloadTask = task
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        progressObservation?.invalidate()
        progressObservation = nil
        state = .notDownloaded
    }

    /// Delete the downloaded model to free disk space.
    func deleteDownloadedModel() {
        let fm = FileManager.default
        let url = Self.documentsModelURL
        if fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: url)
        }
        // If bundled model exists, still show as downloaded
        if Self.bundledModelPath != nil {
            state = .downloaded
        } else {
            state = .notDownloaded
        }
    }

    /// Size of the downloaded model file in bytes, or nil if not downloaded.
    var downloadedModelSize: Int64? {
        guard let path = Self.downloadedModelPath else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return attrs?[.size] as? Int64
    }

    // MARK: - Paths (nonisolated for cross-actor access)

    private nonisolated static let modelFilename = AppConfig.llm.onDeviceModelFilename
    private nonisolated static let modelExtension = "gguf"

    nonisolated static var documentsModelURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("\(modelFilename).\(modelExtension)")
    }

    /// Path to model in Documents directory, if it exists.
    nonisolated static var downloadedModelPath: String? {
        let path = documentsModelURL.path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    /// Path to model in app bundle, if it exists.
    nonisolated static var bundledModelPath: String? {
        Bundle.main.path(forResource: modelFilename, ofType: modelExtension)
    }
}
