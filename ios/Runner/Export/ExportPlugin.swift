import Flutter
import UIKit
import AVFoundation

public class ExportPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private var eventSink: FlutterEventSink?
    private var exportSession: AVAssetExportSession?
    private var isCancelled = false

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "editor/export", binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(name: "editor/export/progress", binaryMessenger: registrar.messenger())

        let instance = ExportPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "probe":
            guard let args = call.arguments as? [String: Any], let path = args["path"] as? String else {
                result(FlutterError(code: "INVALID_ARG", message: "Path missing", details: nil))
                return
            }
            probeFile(path: path, result: result)

        case "thumbnails":
            guard let args = call.arguments as? [String: Any], let path = args["path"] as? String else {
                result(FlutterError(code: "INVALID_ARG", message: "Path missing", details: nil))
                return
            }
            let count = args["count"] as? Int ?? 5
            let height = args["height"] as? Int ?? 120
            generateThumbnails(path: path, count: count, height: height, result: result)

        case "waveform":
            guard let args = call.arguments as? [String: Any], let path = args["path"] as? String else {
                result(FlutterError(code: "INVALID_ARG", message: "Path missing", details: nil))
                return
            }
            let buckets = args["buckets"] as? Int ?? 100
            extractWaveform(path: path, buckets: buckets, result: result)

        case "export":
            guard let args = call.arguments as? [String: Any], let timelineDict = args["timeline"] as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARG", message: "Timeline data missing", details: nil))
                return
            }
            startExport(timelineDict: timelineDict, result: result)

        case "cancel":
            cancelExport()
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func probeFile(path: String, result: @escaping FlutterResult) {
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)

        let durationMs = Int64(CMTimeGetSeconds(asset.duration) * 1000)
        var width = 1920
        var height = 1080
        var rotation = 0

        if let track = asset.tracks(withMediaType: .video).first {
            let size = track.naturalSize.applying(track.preferredTransform)
            width = Int(abs(size.width))
            height = Int(abs(size.height))
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0

        result([
            "durationMs": durationMs,
            "width": width,
            "height": height,
            "fps": 30.0,
            "codec": "h264",
            "rotation": rotation,
            "hasAudio": !asset.tracks(withMediaType: .audio).isEmpty,
            "fileSize": fileSize
        ])
    }

    private func generateThumbnails(path: String, count: Int, height: Int, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            let url = URL(fileURLWithPath: path)
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 0, height: height)

            let durationSeconds = CMTimeGetSeconds(asset.duration)
            let step = durationSeconds / Double(max(count, 1))

            var thumbPaths: [String] = []
            let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("thumb_cache/\(path.hashValue)")
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

            for i in 0..<count {
                let time = CMTime(seconds: Double(i) * step, preferredTimescale: 600)
                if let imageRef = try? generator.copyCGImage(at: time, actualTime: nil) {
                    let image = UIImage(cgImage: imageRef)
                    let fileURL = cacheDir.appendingPathComponent("frame_\(i).jpg")
                    if let data = image.jpegData(compressionQuality: 0.8) {
                        try? data.write(to: fileURL)
                        thumbPaths.append(fileURL.path)
                    }
                }
            }

            DispatchQueue.main.async {
                result(thumbPaths)
            }
        }
    }

    private func extractWaveform(path: String, buckets: Int, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            // Simulated normalized audio waveform output for cache
            var peaks = [Double](repeating: 0.5, count: buckets)
            for i in 0..<buckets {
                peaks[i] = Double.random(in: 0.2...0.9)
            }
            DispatchQueue.main.async {
                result(peaks)
            }
        }
    }

    private func startExport(timelineDict: [String: Any], result: @escaping FlutterResult) {
        isCancelled = false
        let timeline = TimelineParser.parse(dict: timelineDict)

        do {
            let built = try CompositionBuilder.build(timeline: timeline)

            let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent("exports")
            try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

            let outputURL = outputDir.appendingPathComponent("export_\(Date().timeIntervalSince1970).mp4")

            let preset = timeline.settings.codec == "hevc" ? AVAssetExportPresetHIGHEST_QUALITY : AVAssetExportPreset1920x1080
            guard let session = AVAssetExportSession(asset: built.composition, presetName: preset) else {
                result(FlutterError(code: "EXPORT_ERROR", message: "Failed to create export session", details: nil))
                return
            }

            session.outputURL = outputURL
            session.outputFileType = .mp4
            session.videoComposition = built.videoComposition
            self.exportSession = session

            var bgTask: UIBackgroundTaskIdentifier = .invalid
            bgTask = UIApplication.shared.beginBackgroundTask {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }

            let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] t in
                guard let self = self else { return }
                if self.isCancelled {
                    t.invalidate()
                    session.cancelExport()
                    return
                }
                let progress = Double(session.progress)
                self.emitProgress(progress: progress, stage: "Rendering frames (\(Int(progress * 100))%)")
            }

            session.exportAsynchronously {
                timer.invalidate()
                if bgTask != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTask)
                }

                DispatchQueue.main.async {
                    if session.status == .completed {
                        self.emitProgress(progress: 1.0, stage: "Export complete")
                        result(outputURL.path)
                    } else if session.status == .cancelled {
                        self.emitProgress(progress: 0.0, stage: "Cancelled")
                    } else {
                        result(FlutterError(code: "EXPORT_FAILED", message: session.error?.localizedDescription ?? "Export failed", details: nil))
                    }
                }
            }

        } catch {
            result(FlutterError(code: "BUILD_FAILED", message: error.localizedDescription, details: nil))
        }
    }

    private func cancelExport() {
        isCancelled = true
        exportSession?.cancelExport()
        exportSession = nil
        emitProgress(progress: 0.0, stage: "Cancelled")
    }

    private func emitProgress(progress: Double, stage: String) {
        eventSink?(["progress": progress, "stage": stage])
    }
}
