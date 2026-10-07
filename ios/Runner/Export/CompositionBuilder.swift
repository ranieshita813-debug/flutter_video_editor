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

        return BuiltComposition(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: nil
        )
    }
}
