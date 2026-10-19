package com.motiongr.videoedit.export

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

data class ChromaKeySpec(
    val enabled: Boolean = false,
    val keyColor: Long = 0xFF00FF00L,
    val similarity: Double = 40.0,
    val smoothness: Double = 10.0,
    val spill: Double = 50.0,
    val output: String = "composite"
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

data class ElementPropertiesSpec(
    val shape: String = "rectangle",
    val fillColor: Long = 0xFFFFFFFFL,
    val strokeColor: Long = 0x00000000L,
    val strokeWidth: Double = 2.0,
    val size: Double = 100.0,
    val svgPath: String? = null
)

data class WordSpec(
    val word: String,
    val startMs: Long,
    val endMs: Long
)

data class KeyframeSpec(
    val id: String,
    val timeMs: Long,
    val property: String,
    val value: Double,
    val curveType: String = "linear"
)

data class ShaderKeyframeSpec(
    val id: String = "",
    val timeMs: Long = 0L,
    val value: Double = 0.0,
    val easing: String = "linear"
)

data class KeyframeAnimationSpec(
    val id: String = "",
    val parameterId: String = "",
    val keyframes: List<ShaderKeyframeSpec> = emptyList()
)

data class ShaderEffectSpec(
    val id: String = "",
    val effectId: String = "",
    val name: String = "",
    val startMs: Long = 0L,
    val endMs: Long = 0L,
    val isEnabled: Boolean = true,
    val zIndex: Int = 0,
    val parameterValues: Map<String, Double> = emptyMap(),
    val keyframeAnimations: List<KeyframeAnimationSpec> = emptyList()
) {
    fun getInterpolatedParameters(clipRelativeTimeMs: Long): Map<String, Double> {
        val result = parameterValues.toMutableMap()
        for (anim in keyframeAnimations) {
            val ks = anim.keyframes.sortedBy { it.timeMs }
            if (ks.isEmpty()) continue
            val evaluatedValue = if (clipRelativeTimeMs <= ks.first().timeMs) {
                ks.first().value
            } else if (clipRelativeTimeMs >= ks.last().timeMs) {
                ks.last().value
            } else {
                var interpolated = ks.last().value
                for (idx in 0 until ks.size - 1) {
                    val k1 = ks[idx]
                    val k2 = ks[idx + 1]
                    if (clipRelativeTimeMs >= k1.timeMs && clipRelativeTimeMs <= k2.timeMs) {
                        val span = k2.timeMs - k1.timeMs
                        if (span <= 0) {
                            interpolated = k1.value
                        } else {
                            var t = (clipRelativeTimeMs - k1.timeMs).toDouble() / span.toDouble()
                            t = when (k2.easing) {
                                "easeIn" -> t * t
                                "easeOut" -> t * (2.0 - t)
                                "easeInOut" -> if (t < 0.5) 2.0 * t * t else -1.0 + (4.0 - 2.0 * t) * t
                                else -> t
                            }
                            interpolated = k1.value + (k2.value - k1.value) * t
                        }
                        break
                    }
                }
                interpolated
            }
            result[anim.parameterId] = evaluatedValue
        }
        return result
    }
}

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
    val chromaKey: ChromaKeySpec = ChromaKeySpec(),
    val elementProperties: ElementPropertiesSpec = ElementPropertiesSpec(),
    val effectParameters: Map<String, Double> = emptyMap(),
    val fontFamily: String,
    val textAnimationStyle: String,
    val textStyle: TextStyleSpec,
    val inAnimation: String,
    val outAnimation: String,
    val transitionType: String = "none",
    val transitionDurationMs: Long = 500L,
    val strokes: List<DrawingStrokeSpec>,
    val stickerAssetPath: String?,
    val effect: String,
    val svgPath: String? = null,
    val keyframes: List<KeyframeSpec> = emptyList(),
    val words: List<WordSpec> = emptyList(),
    val shaderEffects: List<ShaderEffectSpec> = emptyList()
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

                val apObj = clipObj.optJSONObject("audioProperties") ?: JSONObject()
                val audioProperties = AudioPropertiesSpec(
                    volume = apObj.optDouble("volume", 1.0),
                    speed = apObj.optDouble("speed", 1.0),
                    pitch = apObj.optDouble("pitch", 1.0),
                    fadeInMs = apObj.optLong("fadeInMs", 0L),
                    fadeOutMs = apObj.optLong("fadeOutMs", 0L),
                    equalizerPreset = apObj.optString("equalizerPreset", "Flat")
                )

                val ckObj = clipObj.optJSONObject("chromaKey") ?: JSONObject()
                val chromaKey = ChromaKeySpec(
                    enabled = ckObj.optBoolean("enabled", false),
                    keyColor = ckObj.optLong("keyColor", 0xFF00FF00L),
                    similarity = ckObj.optDouble("similarity", 40.0),
                    smoothness = ckObj.optDouble("smoothness", 10.0),
                    spill = ckObj.optDouble("spill", 50.0),
                    output = ckObj.optString("output", "composite")
                )

                val elemObj = clipObj.optJSONObject("elementProperties") ?: JSONObject()
                val elementProperties = ElementPropertiesSpec(
                    shape = elemObj.optString("shape", "rectangle"),
                    fillColor = elemObj.optLong("fillColor", 0xFFFFFFFFL),
                    strokeColor = elemObj.optLong("strokeColor", 0x00000000L),
                    strokeWidth = elemObj.optDouble("strokeWidth", 2.0),
                    size = elemObj.optDouble("size", 100.0),
                    svgPath = if (elemObj.has("svgPath") && !elemObj.isNull("svgPath")) elemObj.getString("svgPath") else null
                )

                val effParamsObj = clipObj.optJSONObject("effectParameters")
                val effectParameters = mutableMapOf<String, Double>()
                if (effParamsObj != null) {
                    val keys = effParamsObj.keys()
                    while (keys.hasNext()) {
                        val k = keys.next()
                        effectParameters[k] = effParamsObj.optDouble(k, 0.0)
                    }
                }

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

                val shaderFxArray = clipObj.optJSONArray("shaderEffects")
                val shaderEffects = mutableListOf<ShaderEffectSpec>()
                if (shaderFxArray != null) {
                    for (sIdx in 0 until shaderFxArray.length()) {
                        val sObj = shaderFxArray.getJSONObject(sIdx)
                        val paramValuesObj = sObj.optJSONObject("parameterValues")
                        val paramValuesMap = mutableMapOf<String, Double>()
                        if (paramValuesObj != null) {
                            val pKeys = paramValuesObj.keys()
                            while (pKeys.hasNext()) {
                                val pk = pKeys.next()
                                paramValuesMap[pk] = paramValuesObj.optDouble(pk, 0.0)
                            }
                        }

                        val kfAnimArray = sObj.optJSONArray("keyframeAnimations")
                        val kfAnimList = mutableListOf<KeyframeAnimationSpec>()
                        if (kfAnimArray != null) {
                            for (kaIdx in 0 until kfAnimArray.length()) {
                                val kaObj = kfAnimArray.getJSONObject(kaIdx)
                                val skfArray = kaObj.optJSONArray("keyframes")
                                val skfList = mutableListOf<ShaderKeyframeSpec>()
                                if (skfArray != null) {
                                    for (skfIdx in 0 until skfArray.length()) {
                                        val skfObj = skfArray.getJSONObject(skfIdx)
                                        skfList.add(
                                            ShaderKeyframeSpec(
                                                id = skfObj.optString("id", ""),
                                                timeMs = skfObj.optLong("timeMs", 0L),
                                                value = skfObj.optDouble("value", 0.0),
                                                easing = skfObj.optString("easing", "linear")
                                            )
                                        )
                                    }
                                }
                                kfAnimList.add(
                                    KeyframeAnimationSpec(
                                        id = kaObj.optString("id", ""),
                                        parameterId = kaObj.optString("parameterId", ""),
                                        keyframes = skfList
                                    )
                                )
                            }
                        }

                        shaderEffects.add(
                            ShaderEffectSpec(
                                id = sObj.optString("id", ""),
                                effectId = sObj.optString("effectId", ""),
                                name = sObj.optString("name", ""),
                                startMs = sObj.optLong("startMs", 0L),
                                endMs = sObj.optLong("endMs", 0L),
                                isEnabled = sObj.optBoolean("isEnabled", true),
                                zIndex = sObj.optInt("zIndex", 0),
                                parameterValues = paramValuesMap,
                                keyframeAnimations = kfAnimList
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
                        chromaKey = chromaKey,
                        elementProperties = elementProperties,
                        effectParameters = effectParameters,
                        fontFamily = clipObj.optString("fontFamily", "Poppins"),
                        textAnimationStyle = clipObj.optString("textAnimationStyle", "none"),
                        textStyle = textStyle,
                        inAnimation = clipObj.optString("inAnimation", "none"),
                        outAnimation = clipObj.optString("outAnimation", "none"),
                        transitionType = clipObj.optString("transitionType", "none"),
                        transitionDurationMs = clipObj.optLong("transitionDurationMs", 500L),
                        strokes = strokes,
                        stickerAssetPath = if (clipObj.has("stickerAssetPath") && !clipObj.isNull("stickerAssetPath")) clipObj.getString("stickerAssetPath") else null,
                        effect = clipObj.optString("effect", "none"),
                        svgPath = if (clipObj.has("svgPath") && !clipObj.isNull("svgPath")) clipObj.getString("svgPath") else null,
                        keyframes = run {
                            val kfArray = clipObj.optJSONArray("keyframes")
                            val kfList = mutableListOf<KeyframeSpec>()
                            if (kfArray != null) {
                                for (k in 0 until kfArray.length()) {
                                    val kfObj = kfArray.getJSONObject(k)
                                    kfList.add(
                                        KeyframeSpec(
                                            id = kfObj.optString("id", ""),
                                            timeMs = kfObj.optLong("timeMs", 0L),
                                            property = kfObj.optString("property", "positionX"),
                                            value = kfObj.optDouble("value", 0.0),
                                            curveType = kfObj.optString("curveType", "linear")
                                        )
                                    )
                                }
                            }
                            kfList
                        },
                        words = run {
                            val wordsArray = clipObj.optJSONArray("words")
                            val wordList = mutableListOf<WordSpec>()
                            if (wordsArray != null) {
                                for (w in 0 until wordsArray.length()) {
                                    val wObj = wordsArray.getJSONObject(w)
                                    wordList.add(
                                        WordSpec(
                                            word = wObj.optString("word", ""),
                                            startMs = wObj.optLong("startMs", 0L),
                                            endMs = wObj.optLong("endMs", 0L)
                                        )
                                    )
                                }
                            }
                            wordList
                        },
                        shaderEffects = shaderEffects
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
