import Cocoa
import ArgumentParser
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import VideoComposer

private var progressTimer = Timer.publish(every: 0.1, on: .main, in: .common)

@main
struct EncodeForMastodonCommand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "encodeformastodon",
        abstract: "Encodes and resizes any input video in a format suitable for publishing to Mastodon."
    )

    @Argument(help: "Path to the video file that will be encoded")
    var path: String

    var renderSize: CGSize { CGSize(width: 1920, height: 1080) }

    func run() async throws {
        let inputURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw ValidationError("Input file doesn't exist at \(inputURL.path)")
        }

        let filename = inputURL.deletingPathExtension().lastPathComponent
        let outputURL = inputURL
            .deletingLastPathComponent()
            .appendingPathComponent(filename + "-Mastodon")
            .appendingPathExtension("mov")

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let asset = AVAsset(url: inputURL)

        let composition = try await VideoComposer.resizeVideo(with: asset, in: renderSize)

        /// Create the export session and configure it with the composition, output URL and video file format.
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080) else {
            throw CocoaError(.coderValueNotFound, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"])
        }

        session.videoComposition = composition
        session.outputURL = outputURL
        session.outputFileType = .mov

        fputs("Exporting…", stderr)

        /// Detach a new task to stream the export session's progress to the terminal.
        Task.detached {
            await showProgress(for: session)
        }

        /// Actually begin exporting.
        /// This will block until the export has finished or failed.
        await session.export()

        /// Check for errors within the export session.
        if let error = session.error {
            throw CocoaError(.coderInvalidValue, userInfo: [NSLocalizedDescriptionKey: "Export session failed", NSUnderlyingErrorKey: error])
        }

        print("")
        print("Done!")
    }

    private func showProgress(for session: AVAssetExportSession) async {
        for await _ in progressTimer.autoconnect().values {
            let message = String(format: "Exporting… %02d%%", Int(session.progress * 100))

            if canPrintEscapeCodes {
                /// Clear line.
                fputs("\u{001B}[2K", stderr)
                /// Move cursor to beginning of the line.
                fputs("\u{001B}[G", stderr)
                fputs(message, stderr)
            } else {
                fputs(message + "\n", stderr)
            }

            if session.progress >= 1 { break }
        }
    }

    private var canPrintEscapeCodes: Bool { !isRunningInXcode }

    /// Set environment variable `XCODE` to `1` to prevent escape codes from being used by the command,
    /// since Xcode's console can't handle them.
    private var isRunningInXcode: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["XCODE"] == "1"
        #else
        return false
        #endif
    }

}
