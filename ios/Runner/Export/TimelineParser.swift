import Foundation

struct ExportSettingsSpec {
    let width: Int
    let height: Int
    let fps: Int
    let quality: String
    let format: String
    let codec: String
    let bitrateKbps: Int
    let audioBitrateKbps: Int
}

struct ColorGradingSpec {
    let brightness: Double
    let contrast: Double
    let saturation: Double
    let temperature: Double
    let tint: Double
    let exposure: Double
    let vignette: Double
}

struct TextStyleSpec {
    let fontSize: Double
    let lineHeight: Double
    let textColor: Int64
    let textEffect: String
    let strokeColor: Int64
    let strokeWidth: Double
    let shadowColor: Int64
    let shadowBlurRadius: Double
    let shadowOffsetX: Double
    let shadowOffsetY: Double
    let backgroundColor: Int64
    let backgroundPadding: Double
    let textAlign: String
}

struct AudioPropertiesSpec {
    let volume: Double
    let speed: Double
    let pitch: Double
    let fadeInMs: Int64
    let fadeOutMs: Int64
    let equalizerPreset: String
}

struct ChromaKeySpec {
    let enabled: Bool
    let keyColor: Int64
    let similarity: Double
    let smoothness: Double
    let spill: Double
    let output: String
}

struct DrawingPointSpec {
    let x: Double
    let y: Double
}

struct DrawingStrokeSpec {
    let id: String
    let color: Int64
    let strokeWidth: Double
    let points: [DrawingPointSpec]
}

struct ClipSpec {
    let id: String
    let label: String
    let clipType: String
    let sourcePath: String?
    let sourceInMs: Int64
    let sourceOutMs: Int64
    let timelineStartMs: Int64
    let timelineDurationMs: Int64
    let layerIndex: Int
    let isVisible: Bool
    let volume: Double
    let speed: Double
    let opacity: Double
    let scale: Double
    let rotation: Double
    let positionX: Double
    let positionY: Double
    let colorGrading: ColorGradingSpec
    let audioProperties: AudioPropertiesSpec
    let chromaKey: ChromaKeySpec
    let fontFamily: String
    let textAnimationStyle: String
    let textStyle: TextStyleSpec
    let inAnimation: String
    let outAnimation: String
    let strokes: [DrawingStrokeSpec]
    let stickerAssetPath: String?
    let effect: String
}

struct TimelineSpec {
    let version: Int
    let projectName: String
    let durationMs: Int64
    let settings: ExportSettingsSpec
    let clips: [ClipSpec]
}

class TimelineParser {
    static func parse(dict: [String: Any]) -> TimelineSpec {
        let version = dict["version"] as? Int ?? 1
        let projectName = dict["projectName"] as? String ?? "Project"
        let durationMs = dict["durationMs"] as? Int64 ?? 0

        let settingsDict = dict["settings"] as? [String: Any] ?? [:]
        let settings = ExportSettingsSpec(
            width: settingsDict["width"] as? Int ?? 1920,
            height: settingsDict["height"] as? Int ?? 1080,
            fps: settingsDict["fps"] as? Int ?? 30,
            quality: settingsDict["quality"] as? String ?? "high",
            format: settingsDict["format"] as? String ?? "mp4",
            codec: settingsDict["codec"] as? String ?? "h264",
            bitrateKbps: settingsDict["bitrateKbps"] as? Int ?? 16000,
            audioBitrateKbps: settingsDict["audioBitrateKbps"] as? Int ?? 192
        )

        var clips: [ClipSpec] = []
        if let clipsArray = dict["clips"] as? [[String: Any]] {
            for clipDict in clipsArray {
                let cgDict = clipDict["colorGrading"] as? [String: Any] ?? [:]
                let colorGrading = ColorGradingSpec(
                    brightness: cgDict["brightness"] as? Double ?? 0.0,
                    contrast: cgDict["contrast"] as? Double ?? 1.0,
                    saturation: cgDict["saturation"] as? Double ?? 1.0,
                    temperature: cgDict["temperature"] as? Double ?? 0.0,
                    tint: cgDict["tint"] as? Double ?? 0.0,
                    exposure: cgDict["exposure"] as? Double ?? 0.0,
                    vignette: cgDict["vignette"] as? Double ?? 0.0
                )

                let tsDict = clipDict["textStyle"] as? [String: Any] ?? [:]
                let textStyle = TextStyleSpec(
                    fontSize: tsDict["fontSize"] as? Double ?? 28.0,
                    lineHeight: tsDict["lineHeight"] as? Double ?? 1.2,
                    textColor: tsDict["textColor"] as? Int64 ?? 0xFFFFFFFF,
                    textEffect: tsDict["textEffect"] as? String ?? "none",
                    strokeColor: tsDict["strokeColor"] as? Int64 ?? 0x00000000,
                    strokeWidth: tsDict["strokeWidth"] as? Double ?? 0.0,
                    shadowColor: tsDict["shadowColor"] as? Int64 ?? 0x00000000,
                    shadowBlurRadius: tsDict["shadowBlurRadius"] as? Double ?? 0.0,
                    shadowOffsetX: tsDict["shadowOffsetX"] as? Double ?? 0.0,
                    shadowOffsetY: tsDict["shadowOffsetY"] as? Double ?? 0.0,
                    backgroundColor: tsDict["backgroundColor"] as? Int64 ?? 0x00000000,
                    backgroundPadding: tsDict["backgroundPadding"] as? Double ?? 8.0,
                    textAlign: tsDict["textAlign"] as? String ?? "center"
                )

                let apDict = clipDict["audioProperties"] as? [String: Any] ?? [:]
                let audioProperties = AudioPropertiesSpec(
                    volume: apDict["volume"] as? Double ?? 1.0,
                    speed: apDict["speed"] as? Double ?? 1.0,
                    pitch: apDict["pitch"] as? Double ?? 1.0,
                    fadeInMs: apDict["fadeInMs"] as? Int64 ?? 0,
                    fadeOutMs: apDict["fadeOutMs"] as? Int64 ?? 0,
                    equalizerPreset: apDict["equalizerPreset"] as? String ?? "Flat"
                )

                let ckDict = clipDict["chromaKey"] as? [String: Any] ?? [:]
                let chromaKey = ChromaKeySpec(
                    enabled: ckDict["enabled"] as? Bool ?? false,
                    keyColor: ckDict["keyColor"] as? Int64 ?? 0xFF00FF00,
                    similarity: ckDict["similarity"] as? Double ?? 40.0,
                    smoothness: ckDict["smoothness"] as? Double ?? 10.0,
                    spill: ckDict["spill"] as? Double ?? 50.0,
                    output: ckDict["output"] as? String ?? "composite"
                )

                var strokes: [DrawingStrokeSpec] = []
                if let strokesArray = clipDict["strokes"] as? [[String: Any]] {
                    for strokeDict in strokesArray {
                        var points: [DrawingPointSpec] = []
                        if let pointsArray = strokeDict["points"] as? [[String: Any]] {
                            for ptDict in pointsArray {
                                points.append(DrawingPointSpec(
                                    x: ptDict["x"] as? Double ?? 0.0,
                                    y: ptDict["y"] as? Double ?? 0.0
                                ))
                            }
                        }
                        strokes.append(DrawingStrokeSpec(
                            id: strokeDict["id"] as? String ?? "",
                            color: strokeDict["color"] as? Int64 ?? 0xFFFFFFFF,
                            strokeWidth: strokeDict["strokeWidth"] as? Double ?? 4.0,
                            points: points
                        ))
                    }
                }

                clips.append(ClipSpec(
                    id: clipDict["id"] as? String ?? "",
                    label: clipDict["label"] as? String ?? "",
                    clipType: clipDict["clipType"] as? String ?? "video",
                    sourcePath: clipDict["sourcePath"] as? String,
                    sourceInMs: clipDict["sourceInMs"] as? Int64 ?? 0,
                    sourceOutMs: clipDict["sourceOutMs"] as? Int64 ?? 0,
                    timelineStartMs: clipDict["timelineStartMs"] as? Int64 ?? 0,
                    timelineDurationMs: clipDict["timelineDurationMs"] as? Int64 ?? 0,
                    layerIndex: clipDict["layerIndex"] as? Int ?? 0,
                    isVisible: clipDict["isVisible"] as? Bool ?? true,
                    volume: clipDict["volume"] as? Double ?? 1.0,
                    speed: clipDict["speed"] as? Double ?? 1.0,
                    opacity: clipDict["opacity"] as? Double ?? 1.0,
                    scale: clipDict["scale"] as? Double ?? 1.0,
                    rotation: clipDict["rotation"] as? Double ?? 0.0,
                    positionX: clipDict["positionX"] as? Double ?? 0.0,
                    positionY: clipDict["positionY"] as? Double ?? 0.0,
                    colorGrading: colorGrading,
                    audioProperties: audioProperties,
                    chromaKey: chromaKey,
                    fontFamily: clipDict["fontFamily"] as? String ?? "Poppins",
                    textAnimationStyle: clipDict["textAnimationStyle"] as? String ?? "none",
                    textStyle: textStyle,
                    inAnimation: clipDict["inAnimation"] as? String ?? "none",
                    outAnimation: clipDict["outAnimation"] as? String ?? "none",
                    strokes: strokes,
                    stickerAssetPath: clipDict["stickerAssetPath"] as? String,
                    effect: clipDict["effect"] as? String ?? "none"
                ))
            }
        }

        return TimelineSpec(
            version: version,
            projectName: projectName,
            durationMs: durationMs,
            settings: settings,
            clips: clips
        )
    }
}
