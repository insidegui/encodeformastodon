import Cocoa
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins

public final class VideoComposer {

    public static func resizeVideo(with asset: AVAsset, in renderSize: CGSize) async throws -> AVMutableVideoComposition {
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
        let composition = AVMutableVideoComposition(asset: asset, applyingCIFiltersWithHandler: { request in
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

        return composition
    }

}
