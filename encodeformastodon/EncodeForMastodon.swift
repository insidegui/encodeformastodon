import Cocoa
import ArgumentParser
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins

private var progressTimer = Timer.publish(every: 0.1, on: .main, in: .common)

@main
struct EncodeForMastodon: AsyncParsableCommand {

    static let configuration = CommandConfiguration(commandName: "encodeformastodon", abstract: "Encodes and resizes any input video in a format suitable for publishing to Mastodon.")

    @Argument(help: "Path to the video file that will be encoded")
    var path: String

    var renderSize: CGSize { CGSize(width: 1920, height: 1080) }

    func run() async throws {
        let inputURL = URL(filePath: path)
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

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw CocoaError(.coderValueNotFound, userInfo: [NSLocalizedDescriptionKey: "Couldn't find video track in input file"])
        }

        /// We'll need the size of the video track in order to reposition it within the rendered video's bounds.
        let videoSize = try await videoTrack.load(.naturalSize)

        /// Figure out the pixels per point resolution of the machine, since the `NSImage` below
        /// will be using it as a multiplier, but we actually need the correct size in pixels.
        let bgScale = NSScreen.main?.backingScaleFactor ?? 1

        /// Create a black background image to be composed behind the video in the rendered output.
        let background = NSImage(size: NSSize(width: renderSize.width / bgScale, height: renderSize.height / bgScale), flipped: true) { rect in
            NSColor.black.setFill()
            rect.fill()
            return true
        }

        /// Get the corresponding `CGImage` from the background image, which we'll use to initialize a `CIImage`.
        guard let backgroundImage = background.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw CocoaError(.coderReadCorrupt, userInfo: [NSLocalizedDescriptionKey: "Unable to create black background image"])
        }

        /// Create a composition based on the input video asset that uses a CoreImage filter pipeline to render each frame.
        let composition = try await AVMutableVideoComposition.videoComposition(with: asset, applyingCIFiltersWithHandler: { request in
            /// Grab the input video frame from the render request.
            let videoFrame = request.sourceImage
            /// Create a `CIImage` for the black background.
            let background = CIImage(cgImage: backgroundImage)

            /// Create an affine transform filter for centering the rendered video frame within the background, creating a pillar box effect.
            guard let transformFilter = CIFilter(name: "CIAffineTransform") else {
                request.finish(with: CocoaError(.coderInvalidValue, userInfo: [NSLocalizedDescriptionKey: "Couldn't get CIAffineTransform"]))
                return
            }

            transformFilter.setDefaults()
            transformFilter.setValue(videoFrame, forKey: kCIInputImageKey)

            /// Calculate the amount of translation needed in order to center the video within the rendered output.
            let transform = CGAffineTransform(
                translationX: request.renderSize.width / 2 - videoSize.width / 2,
                y: request.renderSize.height / 2 - videoSize.height / 2
            )
            transformFilter.setValue(transform, forKey: kCIInputTransformKey)

            /// Grab the transformed image.
            guard let transformedImage = transformFilter.outputImage else {
                request.finish(with: CocoaError(.coderInvalidValue, userInfo: [NSLocalizedDescriptionKey: "Couldn't transform image"]))
                return
            }

            /// Compose the video frame on top of the black background image.
            let compositeFilter = CIFilter.sourceAtopCompositing()
            compositeFilter.backgroundImage = background
            compositeFilter.inputImage = transformedImage

            /// Grab the final rendered video frame and feed it into the request for this frame.
            guard let outputImage = compositeFilter.outputImage else {
                request.finish(with: CocoaError(.coderInvalidValue, userInfo: [NSLocalizedDescriptionKey: "Couldn't get output image"]))
                return
            }

            request.finish(with: outputImage.clampedToExtent(), context: nil)
        })

        /// Ensure the composition will render at the specified size (currently 1920x1080).
        composition.renderSize = renderSize

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
            /// Clear line.
            fputs("\u{001B}[2K", stderr)
            /// Move cursor to beginning of the line.
            fputs("\u{001B}[G", stderr)

            fputs(String(format: "Exporting… %02d%%", Int(session.progress * 100)), stderr)

            if session.progress >= 1 { break }
        }
    }

}
