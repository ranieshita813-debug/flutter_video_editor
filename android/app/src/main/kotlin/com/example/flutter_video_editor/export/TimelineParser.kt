package com.example.flutter_video_editor.export

import org.json.JSONObject

data class ExportSettingsSpec(
    val width: Int,
    val height: Int,
    val fps: Int,
    val quality: String,
    val format: String,
    val codec: String,
    val bitrateKbps: Int,
    val audioBitrateKbps: Int
)

data class ColorGradingSpec(
    val brightness: Double,
    val contrast: Double,
    val saturation: Double,
    val temperature: Double,
    val tint: Double,
    val exposure: Double,
    val vignette: Double
)

data class ChromaKeySpec(
    val enabled: Boolean,
    val color: Long,
    val distance: Double,
    val softness: Double
)

data class TextStyleSpec(
    val fontSize: Double,
    val lineHeight: Double,
    val textColor: Long,
    val textEffect: String,
    val strokeColor: Long,
    val strokeWidth: Double,
    val shadowColor: Long,
    val shadowBlurRadius: Double,
    val shadowOffsetX: Double,
    val shadowOffsetY: Double,
    val backgroundColor: Long,
    val backgroundPadding: Double,
    val textAlign: String
)

data class AudioPropertiesSpec(
    val volume: Double,
    val speed: Double,
    val pitch: Double,
    val fadeInMs: Long,
    val fadeOutMs: Long,
    val equalizerPreset: String
)

data class DrawingPointSpec(
    val x: Double,
    val y: Double
)

data class DrawingStrokeSpec(
    val id: String,
    val color: Long,
    val strokeWidth: Double,
    val points: List<DrawingPointSpec>
)

data class ClipSpec(
    val id: String,
    val label: String,
    val clipType: String,
    val sourcePath: String?,
    val sourceInMs: Long,
    val sourceOutMs: Long,
    val timelineStartMs: Long,
    val timelineDurationMs: Long,
    val layerIndex: Int,
    val isVisible: Boolean,
    val volume: Double,
    val speed: Double,
    val opacity: Double,
    val scale: Double,
    val rotation: Double,
    val positionX: Double,
    val positionY: Double,
    val colorGrading: ColorGradingSpec,
    val audioProperties: AudioPropertiesSpec,
    val fontFamily: String,
    val textAnimationStyle: String,
    val textStyle: TextStyleSpec,
    val inAnimation: String,
    val outAnimation: String,
    val strokes: List<DrawingStrokeSpec>,
    val stickerAssetPath: String?,
    val effect: String,
    val chromaKey: ChromaKeySpec
)

data class TimelineSpec(
    val version: Int,
    val projectName: String,
    val durationMs: Long,
    val settings: ExportSettingsSpec,
    val clips: List<ClipSpec>
)

object TimelineParser {
    fun parse(jsonMap: Map<String, Any?>): TimelineSpec {
        val json = JSONObject(jsonMap)
        val version = json.optInt("version", 1)
        val projectName = json.optString("projectName", "Project")
        val durationMs = json.optLong("durationMs", 0L)

        val settingsObj = json.optJSONObject("settings") ?: JSONObject()
        val settings = ExportSettingsSpec(
            width = settingsObj.optInt("width", 1920),
            height = settingsObj.optInt("height", 1080),
            fps = settingsObj.optInt("fps", 30),
            quality = settingsObj.optString("quality", "high"),
            format = settingsObj.optString("format", "mp4"),
            codec = settingsObj.optString("codec", "h264"),
            bitrateKbps = settingsObj.optInt("bitrateKbps", 16000),
            audioBitrateKbps = settingsObj.optInt("audioBitrateKbps", 192)
        )

        val clipsArray = json.optJSONArray("clips")
        val clips = mutableListOf<ClipSpec>()

        if (clipsArray != null) {
            for (i in 0 until clipsArray.length()) {
                val clipObj = clipsArray.getJSONObject(i)

                val cgObj = clipObj.optJSONObject("colorGrading") ?: JSONObject()
                val colorGrading = ColorGradingSpec(
                    brightness = cgObj.optDouble("brightness", 0.0),
                    contrast = cgObj.optDouble("contrast", 1.0),
                    saturation = cgObj.optDouble("saturation", 1.0),
                    temperature = cgObj.optDouble("temperature", 0.0),
                    tint = cgObj.optDouble("tint", 0.0),
                    exposure = cgObj.optDouble("exposure", 0.0),
                    vignette = cgObj.optDouble("vignette", 0.0)
                )

                val tsObj = clipObj.optJSONObject("textStyle") ?: JSONObject()
                val textStyle = TextStyleSpec(
                    fontSize = tsObj.optDouble("fontSize", 28.0),
                    lineHeight = tsObj.optDouble("lineHeight", 1.2),
                    textColor = tsObj.optLong("textColor", 0xFFFFFFFFL),
                    textEffect = tsObj.optString("textEffect", "none"),
                    strokeColor = tsObj.optLong("strokeColor", 0x00000000L),
                    strokeWidth = tsObj.optDouble("strokeWidth", 0.0),
                    shadowColor = tsObj.optLong("shadowColor", 0x00000000L),
                    shadowBlurRadius = tsObj.optDouble("shadowBlurRadius", 0.0),
                    shadowOffsetX = tsObj.optDouble("shadowOffsetX", 0.0),
                    shadowOffsetY = tsObj.optDouble("shadowOffsetY", 0.0),
                    backgroundColor = tsObj.optLong("backgroundColor", 0x00000000L),
                    backgroundPadding = tsObj.optDouble("backgroundPadding", 8.0),
                    textAlign = tsObj.optString("textAlign", "center")
                )

                val ckObj = clipObj.optJSONObject("chromaKey") ?: JSONObject()
                val chromaKey = ChromaKeySpec(
                    enabled = ckObj.optBoolean("enabled", false),
                    color = ckObj.optLong("color", 0xFF00FF00L),
                    distance = ckObj.optDouble("distance", 0.4),
                    softness = ckObj.optDouble("softness", 0.1)
                )

                val apObj = clipObj.optJSONObject("audioProperties") ?: JSONObject()
                val audioProperties = AudioPropertiesSpec(
                    volume = apObj.optDouble("volume", 1.0),
                    speed = apObj.optDouble("speed", 1.0),
                    pitch = apObj.optDouble("pitch", 1.0),
                    fadeInMs = apObj.optLong("fadeInMs", 0L),
                    fadeOutMs = apObj.optLong("fadeOutMs", 0L),
                    equalizerPreset = apObj.optString("equalizerPreset", "Flat")
                )

                val strokesArray = clipObj.optJSONArray("strokes")
                val strokes = mutableListOf<DrawingStrokeSpec>()
                if (strokesArray != null) {
                    for (j in 0 until strokesArray.length()) {
                        val strokeObj = strokesArray.getJSONObject(j)
                        val pointsArray = strokeObj.optJSONArray("points")
                        val points = mutableListOf<DrawingPointSpec>()
                        if (pointsArray != null) {
                            for (k in 0 until pointsArray.length()) {
                                val ptObj = pointsArray.getJSONObject(k)
                                points.add(
                                    DrawingPointSpec(
                                        x = ptObj.optDouble("x", 0.0),
                                        y = ptObj.optDouble("y", 0.0)
                                    )
                                )
                            }
                        }
                        strokes.add(
                            DrawingStrokeSpec(
                                id = strokeObj.optString("id", ""),
                                color = strokeObj.optLong("color", 0xFFFFFFFFL),
                                strokeWidth = strokeObj.optDouble("strokeWidth", 4.0),
                                points = points
                            )
                        )
                    }
                }

                clips.add(
                    ClipSpec(
                        id = clipObj.optString("id", ""),
                        label = clipObj.optString("label", ""),
                        clipType = clipObj.optString("clipType", "video"),
                        sourcePath = if (clipObj.has("sourcePath") && !clipObj.isNull("sourcePath")) clipObj.getString("sourcePath") else null,
                        sourceInMs = clipObj.optLong("sourceInMs", 0L),
                        sourceOutMs = clipObj.optLong("sourceOutMs", 0L),
                        timelineStartMs = clipObj.optLong("timelineStartMs", 0L),
                        timelineDurationMs = clipObj.optLong("timelineDurationMs", 0L),
                        layerIndex = clipObj.optInt("layerIndex", 0),
                        isVisible = clipObj.optBoolean("isVisible", true),
                        volume = clipObj.optDouble("volume", 1.0),
                        speed = clipObj.optDouble("speed", 1.0),
                        opacity = clipObj.optDouble("opacity", 1.0),
                        scale = clipObj.optDouble("scale", 1.0),
                        rotation = clipObj.optDouble("rotation", 0.0),
                        positionX = clipObj.optDouble("positionX", 0.0),
                        positionY = clipObj.optDouble("positionY", 0.0),
                        colorGrading = colorGrading,
                        audioProperties = audioProperties,
                        fontFamily = clipObj.optString("fontFamily", "Poppins"),
                        textAnimationStyle = clipObj.optString("textAnimationStyle", "none"),
                        textStyle = textStyle,
                        inAnimation = clipObj.optString("inAnimation", "none"),
                        outAnimation = clipObj.optString("outAnimation", "none"),
                        strokes = strokes,
                        stickerAssetPath = if (clipObj.has("stickerAssetPath") && !clipObj.isNull("stickerAssetPath")) clipObj.getString("stickerAssetPath") else null,
                        effect = clipObj.optString("effect", "none"),
                        chromaKey = chromaKey
                    )
                )
            }
        }

        return TimelineSpec(
            version = version,
            projectName = projectName,
            durationMs = durationMs,
            settings = settings,
            clips = clips
        )
    }
}
