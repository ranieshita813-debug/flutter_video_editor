import Foundation
import AVFoundation
import UIKit
import CoreImage

class CompositionBuilder {

    struct BuiltComposition {
        let composition: AVMutableComposition
        let videoComposition: AVMutableVideoComposition?
        let audioMix: AVMutableAudioMix?
    }

    static func applyImageEffects(image: UIImage, effect: String, parameters: [String: Double], shaderEffects: [ShaderEffectSpec]) -> UIImage {
        guard var ciImage = CIImage(image: image) else { return image }
        let context = CIContext(options: nil)

        func processEffect(effName: String, params: [String: Double]) {
            let eff = effName.lowercased()
            let intensity = params["intensity"] ?? params["amount"] ?? params["strength"] ?? 1.0

            if eff.contains("sepia") || eff.contains("vintage") || eff.contains("retro") {
                if let filter = CIFilter(name: "CISepiaTone") {
                    filter.setValue(ciImage, forKey: kCIInputImageKey)
                    filter.setValue(intensity, forKey: kCIInputIntensityKey)
                    if let output = filter.outputImage { ciImage = output }
                }
            } else if eff.contains("noir") || eff.contains("monochrome") || eff.contains("bw") {
                if let filter = CIFilter(name: "CIPhotoEffectNoir") {
                    filter.setValue(ciImage, forKey: kCIInputImageKey)
                    if let output = filter.outputImage { ciImage = output }
                }
            } else if eff.contains("blur") {
                let blurRadius = params["blurAmount"] ?? params["blur"] ?? (intensity * 5.0)
                if let filter = CIFilter(name: "CIGaussianBlur") {
                    filter.setValue(ciImage, forKey: kCIInputImageKey)
                    filter.setValue(blurRadius, forKey: kCIInputRadiusKey)
                    if let output = filter.outputImage { ciImage = output }
                }
            } else if eff.contains("vibrant") || eff.contains("vibrance") {
                if let filter = CIFilter(name: "CIVibrance") {
                    filter.setValue(ciImage, forKey: kCIInputImageKey)
                    filter.setValue(intensity * 1.5, forKey: "inputAmount")
                    if let output = filter.outputImage { ciImage = output }
                }
            } else if eff.contains("glow") || eff.contains("bloom") {
                if let filter = CIFilter(name: "CIBloom") {
                    filter.setValue(ciImage, forKey: kCIInputImageKey)
                    filter.setValue(intensity * 10.0, forKey: kCIInputRadiusKey)
                    filter.setValue(intensity * 0.8, forKey: kCIInputIntensityKey)
                    if let output = filter.outputImage { ciImage = output }
                }
            } else if eff.contains("vignette") {
                if let filter = CIFilter(name: "CIVignette") {
                    filter.setValue(ciImage, forKey: kCIInputImageKey)
                    filter.setValue(intensity * 2.0, forKey: kCIInputIntensityKey)
                    filter.setValue(intensity * 3.0, forKey: kCIInputRadiusKey)
                    if let output = filter.outputImage { ciImage = output }
                }
            } else if eff.contains("pixelate") || eff.contains("mosaic") {
                let scaleVal = params["sizePx"] ?? (intensity * 10.0)
                if let filter = CIFilter(name: "CIPixellate") {
                    filter.setValue(ciImage, forKey: kCIInputImageKey)
                    filter.setValue(scaleVal, forKey: kCIInputScaleKey)
                    if let output = filter.outputImage { ciImage = output }
                }
            } else if eff.contains("chromatic") || eff.contains("glitch") || eff.contains("vhs") {
                if let filter = CIFilter(name: "CIColorControls") {
                    filter.setValue(ciImage, forKey: kCIInputImageKey)
                    filter.setValue(intensity * 1.2, forKey: kCIInputContrastKey)
                    filter.setValue(intensity * 1.3, forKey: kCIInputSaturationKey)
                    if let output = filter.outputImage { ciImage = output }
                }
            }
        }

        if effect != "none" {
            processEffect(effName: effect, params: parameters)
        }

        for shaderFx in shaderEffects {
            if shaderFx.isEnabled {
                processEffect(effName: shaderFx.effectId, params: shaderFx.parameterValues)
            }
        }

        if let cgImg = context.createCGImage(ciImage, from: ciImage.extent) {
            return UIImage(cgImage: cgImg)
        }
        return image
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
                let fontName = clip.fontFamily.isEmpty ? "Helvetica-Bold" : clip.fontFamily
                textLayer.font = CTFontCreateWithName(fontName as CFString, CGFloat(clip.textStyle.fontSize) * sy, nil)

                let textColor = UIColor(
                    red: CGFloat((clip.textStyle.textColor >> 16) & 0xFF) / 255.0,
                    green: CGFloat((clip.textStyle.textColor >> 8) & 0xFF) / 255.0,
                    blue: CGFloat(clip.textStyle.textColor & 0xFF) / 255.0,
                    alpha: CGFloat((clip.textStyle.textColor >> 24) & 0xFF) / 255.0
                )
                textLayer.foregroundColor = textColor.cgColor
                textLayer.alignmentMode = .center
                textLayer.frame = layer.bounds

                if clip.textStyle.backgroundColor != 0 {
                    let bgColor = UIColor(
                        red: CGFloat((clip.textStyle.backgroundColor >> 16) & 0xFF) / 255.0,
                        green: CGFloat((clip.textStyle.backgroundColor >> 8) & 0xFF) / 255.0,
                        blue: CGFloat(clip.textStyle.backgroundColor & 0xFF) / 255.0,
                        alpha: CGFloat((clip.textStyle.backgroundColor >> 24) & 0xFF) / 255.0
                    )
                    textLayer.backgroundColor = bgColor.cgColor
                    textLayer.cornerRadius = 4 * sy
                }

                layer.addSublayer(textLayer)
            } else if let src = clip.stickerAssetPath ?? clip.sourcePath, var img = UIImage(contentsOfFile: src) {
                if clip.effect != "none" || !clip.shaderEffects.isEmpty {
                    img = applyImageEffects(image: img, effect: clip.effect, parameters: clip.effectParameters, shaderEffects: clip.shaderEffects)
                }
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
