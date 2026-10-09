import Foundation
import AVFoundation

class CompositionBuilder {

    struct BuiltComposition {
        let composition: AVMutableComposition
        let videoComposition: AVMutableVideoComposition?
        let audioMix: AVMutableAudioMix?
    }

    static func build(timeline: TimelineSpec) throws -> BuiltComposition {
        let composition = AVMutableComposition()

        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw NSError(domain: "Export", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create video track"])
        }

        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var currentTime = CMTime.zero

        for clip in timeline.clips {
            guard clip.isVisible, let sourcePath = clip.sourcePath, FileManager.default.fileExists(atPath: sourcePath) else {
                continue
            }

            let asset = AVURLAsset(url: URL(fileURLWithPath: sourcePath))
            let duration = CMTime(value: clip.timelineDurationMs, timescale: 1000)
            let timeRange = CMTimeRange(start: CMTime(value: clip.sourceInMs, timescale: 1000), duration: duration)

            if let assetVideoTrack = asset.tracks(withMediaType: .video).first {
                try videoTrack.insertTimeRange(timeRange, of: assetVideoTrack, at: currentTime)
            }

            if clip.volume > 0, let assetAudioTrack = asset.tracks(withMediaType: .audio).first, let audioTrack = audioTrack {
                try audioTrack.insertTimeRange(timeRange, of: assetAudioTrack, at: currentTime)
            }

            currentTime = CMTimeAdd(currentTime, duration)
        }

        // Build VideoComposition for size and frame rate
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: timeline.settings.width, height: timeline.settings.height)
        videoComposition.frameDuration = CMTime(value: 1, timescale: Int32(timeline.settings.fps))

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration.seconds > 0 ? composition.duration : CMTime(seconds: 5, preferredTimescale: 600))

        if let track = composition.tracks(withMediaType: .video).first {
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            instruction.layerInstructions = [layerInstruction]
        }

        videoComposition.instructions = [instruction]

        let videoSize = CGSize(width: timeline.settings.width, height: timeline.settings.height)
        let sx = videoSize.width / 375.0
        let sy = videoSize.height / 667.0

        let parentLayer = CALayer()
        let videoLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: videoSize)
        videoLayer.frame = CGRect(origin: .zero, size: videoSize)
        parentLayer.addSublayer(videoLayer)

        let overlayClips = timeline.clips.filter { $0.isVisible && ($0.layerIndex > 0 || ["text", "caption", "drawing", "element", "sticker"].contains($0.clipType)) }

        for clip in overlayClips.sorted(by: { $0.layerIndex < $1.layerIndex }) {
            let layer = CALayer()
            layer.bounds = CGRect(x: 0, y: 0, width: 200 * sx, height: 100 * sy)
            layer.position = CGPoint(x: clip.positionX * sx, y: videoSize.height - (clip.positionY * sy))
            layer.opacity = Float(clip.opacity)

            let startSec = Double(clip.timelineStartMs) / 1000.0
            let durSec = Double(clip.timelineDurationMs) / 1000.0

            let anim = CABasicAnimation(keyPath: "hidden")
            anim.fromValue = true
            anim.toValue = false
            anim.duration = durSec
            anim.beginTime = AVCoreAnimationBeginTimeAtZero + startSec
            anim.fillMode = .both
            anim.isRemovedOnCompletion = false
            layer.add(anim, forKey: "hidden")

            if clip.clipType == "text" || clip.clipType == "caption" {
                let textLayer = CATextLayer()
                textLayer.string = clip.label
                textLayer.fontSize = CGFloat(clip.textStyle.fontSize) * sy
                textLayer.font = CTFontCreateWithName("Helvetica-Bold" as CFString, CGFloat(clip.textStyle.fontSize) * sy, nil)
                textLayer.foregroundColor = UIColor.white.cgColor
                textLayer.alignmentMode = .center
                textLayer.frame = layer.bounds
                layer.addSublayer(textLayer)
            } else if let src = clip.stickerAssetPath ?? clip.sourcePath, let img = UIImage(contentsOfFile: src) {
                layer.contents = img.cgImage
            }

            parentLayer.addSublayer(layer)
        }

        // Add "motionGr" watermark text layer to videoComposition
        let watermarkLayer = CATextLayer()
        watermarkLayer.string = "motionGr"
        watermarkLayer.font = CTFontCreateWithName("Helvetica-Bold" as CFString, 24 * (videoSize.height / 720.0), nil)
        watermarkLayer.fontSize = 24 * (videoSize.height / 720.0)
        watermarkLayer.foregroundColor = UIColor.white.withAlphaComponent(0.7).cgColor
        watermarkLayer.alignmentMode = .right
        watermarkLayer.frame = CGRect(
            x: 0,
            y: 20 * (videoSize.height / 720.0),
            width: videoSize.width - 24 * (videoSize.height / 720.0),
            height: 40 * (videoSize.height / 720.0)
        )
        parentLayer.addSublayer(watermarkLayer)

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        return BuiltComposition(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: nil
        )
    }
}
