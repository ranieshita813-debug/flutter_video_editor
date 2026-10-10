package com.motiongr.videoedit.export

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.net.Uri
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.ChannelMixingAudioProcessor
import androidx.media3.common.audio.ChannelMixingMatrix
import androidx.media3.common.audio.SonicAudioProcessor
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.Brightness
import androidx.media3.effect.Contrast
import androidx.media3.effect.HslAdjustment
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.Presentation
import androidx.media3.effect.RgbAdjustment
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.effect.SpeedChangeEffect
import androidx.media3.effect.TextureOverlay
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import com.google.common.collect.ImmutableList
import java.io.File
import java.io.FileOutputStream
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.pow

/**
 * বিল্ড করে একটি Media3 [Composition] ফ্লাটার টাইমলাইন থেকে।
 *
 * অবৈধ টাইমলাইনের জন্য [IllegalArgumentException] ছুঁড়ে দেয় একটি পড়ার যোগ্য বার্তা সহ।
 * Media3 >= 1.4.0 প্রয়োজন (EditedMediaItemSequence.Builder.addGap /
 * experimentalSetForceAudioTrack; 1.5+ এ এটির নাম পরিবর্তন করে setForceAudioTrack করা হয়েছে)।
 */
@UnstableApi
class DynamicTimelineOverlay(
    private val context: Context,
    private val width: Int,
    private val height: Int,
    private val baseStartMs: Long,
    private val overlayClips: List<ClipSpec>
) : BitmapOverlay() {

    private var cachedFrameBitmap: Bitmap? = null
    private var cachedCanvas: Canvas? = null

    override fun getBitmap(presentationTimeUs: Long): Bitmap {
        val currentTimelineMs = baseStartMs + presentationTimeUs / 1000L
        val activeOverlays = overlayClips.filter { clip ->
            clip.isVisible &&
            currentTimelineMs >= clip.timelineStartMs &&
            currentTimelineMs < (clip.timelineStartMs + clip.timelineDurationMs)
        }.sortedBy { it.layerIndex }

        var frame = cachedFrameBitmap
        if (frame == null || frame.width != width || frame.height != height || frame.isRecycled) {
            frame = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            cachedFrameBitmap = frame
            cachedCanvas = Canvas(frame)
        } else {
            frame.eraseColor(Color.TRANSPARENT)
        }

        val canvas = cachedCanvas ?: Canvas(frame).also { cachedCanvas = it }

        if (activeOverlays.isNotEmpty()) {
            for (clip in activeOverlays) {
                OverlayRenderer.drawOverlayClip(
                    context = context,
                    canvas = canvas,
                    clip = clip,
                    width = width,
                    height = height,
                    timelineMs = currentTimelineMs
                )
            }
        }

        OverlayRenderer.drawWatermarkOverlayOnCanvas(canvas, width, height, "motionGr")

        return frame
    }
}

@UnstableApi
object CompositionBuilder {

    private const val DEFAULT_FPS = 30
    private const val DEFAULT_CARD_DURATION_MS = 3000L
    private const val MIN_SPEED = 0.1
    private const val MAX_SPEED = 8.0
    private const val MAX_VOLUME = 4.0
    private const val EPS = 1e-3

    private val OVERLAY_TYPES = setOf("text", "caption", "drawing", "element", "sticker")
    private val IMAGE_EXT = setOf("jpg", "jpeg", "png", "webp", "heic", "heif", "bmp")
    private val AUDIO_EXT = setOf("mp3", "m4a", "aac", "wav", "ogg", "oga", "opus", "flac", "amr")

    private enum class Kind { VIDEO, IMAGE, AUDIO }

    // ---------------------------------------------------------------------------------------
    // হেল্পার ফাংশন
    // ---------------------------------------------------------------------------------------

    /** H.264/H.265 এনকোডারের জন্য জোড় সংখ্যার ডাইমেনশন প্রয়োজন। */
    private fun even(v: Int): Int = max(v, 2) and 1.inv()

    private fun isContentUri(path: String) = path.startsWith("content://")

    private fun isAssetPath(path: String): Boolean =
        path.startsWith("assets/") || path.startsWith("asset/") || 
        path.startsWith("asset://") || path.startsWith("file:///android_asset/")

    private fun rawAssetPath(path: String): String =
        path.removePrefix("asset:///")
            .removePrefix("asset://")
            .removePrefix("file:///android_asset/")
            .removePrefix("/")

    private fun toAssetPath(path: String): String {
        val p = rawAssetPath(path)
        return if (p.startsWith("flutter_assets/")) p else "flutter_assets/$p"
    }

    private fun sourceExists(context: Context, path: String): Boolean {
        if (isContentUri(path) || path.startsWith("http://") || path.startsWith("https://")) return true
        if (isAssetPath(path)) {
            for (candidate in listOf(toAssetPath(path), rawAssetPath(path))) {
                try {
                    context.assets.open(candidate).use { it.close() }
                    return true
                } catch (_: Exception) {
                    // ফাইল না থাকলে পরের ক্যান্ডিডেট চেষ্টা করুন
                }
            }
            return false
        }
        return File(path.removePrefix("file://")).exists()
    }

    private fun toUri(path: String): Uri {
        if (isContentUri(path) || path.startsWith("http://") || path.startsWith("https://")) {
            return Uri.parse(path)
        }
        if (isAssetPath(path)) {
            return Uri.parse("asset:///${toAssetPath(path)}")
        }
        return Uri.fromFile(File(path.removePrefix("file://")))
    }

    /** content:// URI-এর এক্সটেনশন নেই, তাই MIME টাইপ জিজ্ঞাসা করুন। */
    private fun kindOf(context: Context, path: String): Kind {
        if (isContentUri(path)) {
            val mime = try {
                context.contentResolver.getType(Uri.parse(path))
            } catch (_: Exception) {
                null
            }
            return when {
                mime?.startsWith("audio/") == true -> Kind.AUDIO
                mime?.startsWith("image/") == true -> Kind.IMAGE
                else -> Kind.VIDEO
            }
        }
        val ext = path.substringBefore('?').substringAfterLast('.', "").lowercase()
        return when (ext) {
            in AUDIO_EXT -> Kind.AUDIO
            in IMAGE_EXT -> Kind.IMAGE
            else -> Kind.VIDEO
        }
    }

    /** টেক্সট/ড্রয়িং/স্টিকার "কার্ড"-এর ব্যাকগ্রাউন্ড হিসেবে ব্যবহৃত কালো ইমেজ। */
    private fun blackFrame(context: Context, width: Int, height: Int): File {
        val fileName = "black_${width}x$height.png"
        val file = File(context.cacheDir, fileName)
        
        // ফাইল আগে থেকে থাকলে এবং অকার্যকর না হলে পুনরায় তৈরি করবেন না
        if (file.exists() && file.length() > 0L) {
            return file
        }

        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        try {
            Canvas(bitmap).drawColor(Color.BLACK)
            FileOutputStream(file).use { 
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) 
            }
        } finally {
            if (!bitmap.isRecycled) {
                bitmap.recycle()
            }
        }
        return file
    }

    private fun audioProcessors(speed: Double, pitch: Double, volume: Double): List<AudioProcessor> {
        val list = mutableListOf<AudioProcessor>()
        val pitchChanged = abs(pitch - 1.0) > EPS
        
        if (abs(speed - 1.0) > EPS || pitchChanged) {
            list += SonicAudioProcessor().apply {
                setSpeed(speed.toFloat())
                if (pitchChanged) {
                    setPitch(pitch.coerceIn(0.5, 2.0).toFloat())
                }
            }
        }
        
        // volume == 0 হ্যান্ডেল করা হয় অডিও ট্র্যাক সরিয়ে; এখানে শুধু রিয়েল গেইন পরিবর্তন।
        if (volume > 0.0 && abs(volume - 1.0) > EPS) {
            val gain = volume.toFloat()
            list += ChannelMixingAudioProcessor().apply {
                putChannelMixingMatrix(ChannelMixingMatrix.create(1, 1).scaleBy(gain))
                putChannelMixingMatrix(ChannelMixingMatrix.create(2, 2).scaleBy(gain))
            }
        }
        return list
    }

    /**
     * রিয়েল কালার গ্রেডিং (পুরনো ColorGradingEffect একটি আইডেন্টিটি ম্যাট্রিক্স রিটার্ন করত = নো-অপ)।
     * অনুমানকৃত রেঞ্জ: brightness -1..1, contrast 1.0 = নিউট্রাল, saturation 1.0 = নিউট্রাল,
     * temperature/tint -1..1, exposure EV স্টপে। Vignette সমর্থিত নয় (কাস্টম শেডার প্রয়োজন)।
     */
    private fun colorEffects(cg: ColorGradingSpec): List<Effect> {
        val out = mutableListOf<Effect>()
        
        if (abs(cg.brightness) > EPS) {
            out += Brightness(cg.brightness.coerceIn(-1.0, 1.0).toFloat())
        }
        
        if (abs(cg.contrast - 1.0) > EPS) {
            out += Contrast((cg.contrast - 1.0).coerceIn(-1.0, 1.0).toFloat())
        }
        
        if (abs(cg.saturation - 1.0) > EPS) {
            out += HslAdjustment.Builder()
                .adjustSaturation(((cg.saturation - 1.0) * 100.0).coerceIn(-100.0, 100.0).toFloat())
                .build()
        }
        
        val gain = 2.0.pow(cg.exposure)
        val r = (gain * (1.0 + 0.25 * cg.temperature)).coerceAtLeast(0.0)
        val g = (gain * (1.0 - 0.25 * cg.tint)).coerceAtLeast(0.0)
        val b = (gain * (1.0 - 0.25 * cg.temperature)).coerceAtLeast(0.0)
        
        if (abs(r - 1.0) > EPS || abs(g - 1.0) > EPS || abs(b - 1.0) > EPS) {
            out += RgbAdjustment.Builder()
                .setRedScale(r.toFloat())
                .setGreenScale(g.toFloat())
                .setBlueScale(b.toFloat())
                .build()
        }
        return out
    }

    private fun overlayEffect(bitmap: Bitmap): Effect =
        OverlayEffect(
            ImmutableList.builder<TextureOverlay>()
                .add(BitmapOverlay.createStaticBitmapOverlay(bitmap))
                .build()
        )

    private fun textOverlay(clip: ClipSpec, width: Int, height: Int, context: Context): Effect {
        val ts = clip.textStyle
        return overlayEffect(
            OverlayRenderer.renderTextOverlay(
                context = context,
                text = clip.label,
                width = width,
                height = height,
                fontSizeSp = ts.fontSize.toFloat(),
                fontFamily = clip.fontFamily,
                textColorInt = ts.textColor.toInt(),
                strokeColorInt = ts.strokeColor.toInt(),
                strokeWidthPx = ts.strokeWidth.toFloat(),
                shadowColorInt = ts.shadowColor.toInt(),
                shadowBlurPx = ts.shadowBlurRadius.toFloat(),
                shadowOffsetX = ts.shadowOffsetX.toFloat(),
                shadowOffsetY = ts.shadowOffsetY.toFloat(),
                bgColorInt = ts.backgroundColor.toInt(),
                bgPaddingPx = ts.backgroundPadding.toFloat(),
                textAlignStr = ts.textAlign
            )
        )
    }

    /** টাইমলাইনে একটি ক্লিপের ডিউরেশন (স্পিডের পরে), 0 যদি অজানা হয়। */
    private fun clipDurationMs(c: ClipSpec, speed: Double): Long = when {
        c.timelineDurationMs > 0 -> c.timelineDurationMs
        c.sourceOutMs > c.sourceInMs -> ((c.sourceOutMs - c.sourceInMs) / speed).toLong()
        else -> 0L
    }

    private fun clipping(clip: ClipSpec): MediaItem.ClippingConfiguration =
        MediaItem.ClippingConfiguration.Builder()
            .setStartPositionMs(clip.sourceInMs)
            .setEndPositionMs(clip.sourceOutMs)
            .build()

    /** একটি অডিও "লেন" = একটি সিকোয়েন্স। ওভারল্যাপিং অডিও ক্লিপের জন্য আলাদা লেন প্রয়োজন। */
    private class AudioLane {
        var cursorMs = 0L
        val parts = mutableListOf<Pair<Long, EditedMediaItem>>() // (gapBeforeUs, item)
    }

    // ---------------------------------------------------------------------------------------
    // মূল এন্ট্রি পয়েন্ট
    // ---------------------------------------------------------------------------------------

    fun buildComposition(context: Context, timeline: TimelineSpec): Composition {
        val width = even(timeline.settings.width)
        val height = even(timeline.settings.height)

        // ক্লিপগুলো টাইমলাইন অর্ডারে প্লে করতে হবে, লিস্ট অর্ডারে নয়।
        val visibleClips = timeline.clips
            .filter { it.isVisible }
            .sortedBy { it.timelineStartMs }

        val missing = visibleClips
            .filter { it.clipType !in OVERLAY_TYPES && !it.sourcePath.isNullOrEmpty() }
            .mapNotNull { it.sourcePath }
            .filter { !sourceExists(context, it) }
        
        require(missing.isEmpty()) { 
            "সোর্স ফাইল(গুলো) পাওয়া যায়নি: ${missing.joinToString()}" 
        }

        val videoItems = mutableListOf<EditedMediaItem>()
        val audioLanes = mutableListOf<AudioLane>()

        val audioOnlyClips = visibleClips.filter { clip ->
            val src = clip.sourcePath?.takeIf { it.isNotEmpty() }
            clip.clipType == "audio" || (src != null && clip.clipType !in OVERLAY_TYPES && kindOf(context, src) == Kind.AUDIO)
        }

        val overlayClips = visibleClips.filter { clip ->
            clip !in audioOnlyClips && (clip.layerIndex > 0 || clip.clipType in OVERLAY_TYPES)
        }

        var baseClips = visibleClips.filter { clip ->
            clip !in audioOnlyClips && clip !in overlayClips
        }

        if (baseClips.isEmpty() && (overlayClips.isNotEmpty() || visibleClips.isNotEmpty())) {
            val maxDur = maxOf(
                timeline.durationMs,
                overlayClips.maxOfOrNull { it.timelineStartMs + it.timelineDurationMs } ?: 5000L
            ).coerceAtLeast(1000L)

            baseClips = listOf(
                ClipSpec(
                    id = "base_card",
                    label = "Background",
                    clipType = "video",
                    sourcePath = null,
                    sourceInMs = 0L,
                    sourceOutMs = maxDur,
                    timelineStartMs = 0L,
                    timelineDurationMs = maxDur,
                    layerIndex = 0,
                    isVisible = true,
                    volume = 0.0,
                    speed = 1.0,
                    opacity = 1.0,
                    scale = 1.0,
                    rotation = 0.0,
                    positionX = 0.0,
                    positionY = 0.0,
                    colorGrading = ColorGradingSpec(0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0),
                    audioProperties = AudioPropertiesSpec(0.0, 1.0, 1.0, 0L, 0L, "Flat"),
                    fontFamily = "Poppins",
                    textAnimationStyle = "none",
                    textStyle = TextStyleSpec(28.0, 1.2, 0xFFFFFFFFL, "none", 0L, 0.0, 0L, 0.0, 0.0, 0.0, 0L, 0.0, "center"),
                    inAnimation = "none",
                    outAnimation = "none",
                    strokes = emptyList(),
                    stickerAssetPath = null,
                    effect = "none"
                )
            )
        }

        // Process audio clips into audio lanes
        for (clip in audioOnlyClips) {
            val src = clip.sourcePath?.takeIf { it.isNotEmpty() } ?: continue
            val speed = clip.speed.coerceIn(MIN_SPEED, MAX_SPEED)
            val volume = clip.volume.coerceIn(0.0, MAX_VOLUME)
            if (volume <= 0.0) continue
            val pitch = clip.audioProperties.pitch

            val builder = MediaItem.Builder().setUri(toUri(src))
            if (clip.sourceOutMs > clip.sourceInMs) {
                builder.setClippingConfiguration(clipping(clip))
            }

            val item = EditedMediaItem.Builder(builder.build())
                .setEffects(
                    Effects(
                        ImmutableList.copyOf(audioProcessors(speed, pitch, volume)),
                        ImmutableList.of()
                    )
                )
                .build()

            val lane = audioLanes.firstOrNull { it.cursorMs <= clip.timelineStartMs }
                ?: AudioLane().also { audioLanes += it }

            val gapMs = (clip.timelineStartMs - lane.cursorMs).coerceAtLeast(0L)
            lane.parts += (gapMs * 1000L) to item
            lane.cursorMs = clip.timelineStartMs + clipDurationMs(clip, speed)
        }

        // Process base track clips and apply dynamic overlay effect
        for (clip in baseClips) {
            val src = clip.sourcePath?.takeIf { it.isNotEmpty() }
            val isCard = src == null
            val kind = if (!isCard) kindOf(context, src!!) else Kind.VIDEO
            val isImage = !isCard && kind == Kind.IMAGE

            val speed = clip.speed.coerceIn(MIN_SPEED, MAX_SPEED)
            val volume = clip.volume.coerceIn(0.0, MAX_VOLUME)
            val speedChanged = abs(speed - 1.0) > EPS

            val videoEffects = mutableListOf<Effect>()

            if (speedChanged && !isImage && !isCard) {
                videoEffects += SpeedChangeEffect(speed.toFloat())
            }

            videoEffects += Presentation.createForWidthAndHeight(
                width,
                height,
                Presentation.LAYOUT_SCALE_TO_FIT
            )

            if (!isCard) {
                videoEffects += colorEffects(clip.colorGrading)
            }

            if (!isCard && clip.scale > 0.0 && (clip.scale != 1.0 || clip.rotation != 0.0)) {
                videoEffects += ScaleAndRotateTransformation.Builder()
                    .setScale(clip.scale.toFloat(), clip.scale.toFloat())
                    .setRotationDegrees(clip.rotation.toFloat())
                    .build()
            }

            // Apply transition / animation effects for base track clips
            if (!isCard && clip.inAnimation != "none") {
                when (clip.inAnimation) {
                    "zoomIn" -> {
                        videoEffects += ScaleAndRotateTransformation.Builder()
                            .setScale(1.15f, 1.15f)
                            .build()
                    }
                    "zoomOut" -> {
                        videoEffects += ScaleAndRotateTransformation.Builder()
                            .setScale(0.85f, 0.85f)
                            .build()
                    }
                }
            }

            // Dynamic Overlay containing all active overlay clips & watermark
            val dynamicOverlay = DynamicTimelineOverlay(
                context = context,
                width = width,
                height = height,
                baseStartMs = clip.timelineStartMs,
                overlayClips = overlayClips
            )
            videoEffects += OverlayEffect(ImmutableList.of<TextureOverlay>(dynamicOverlay))

            val uri = if (isCard) {
                Uri.fromFile(blackFrame(context, width, height))
            } else {
                toUri(src!!)
            }

            val mediaItemBuilder = MediaItem.Builder().setUri(uri)

            if (!isImage && !isCard && clip.sourceOutMs > clip.sourceInMs) {
                mediaItemBuilder.setClippingConfiguration(clipping(clip))
            }

            val editedBuilder = EditedMediaItem.Builder(mediaItemBuilder.build())
                .setEffects(
                    Effects(
                        ImmutableList.copyOf(audioProcessors(speed, clip.audioProperties.pitch, volume)),
                        ImmutableList.copyOf(videoEffects)
                    )
                )
                .setRemoveAudio(volume <= 0.0 || isImage || isCard)

            if (isImage || isCard) {
                val durationMs = (if (isCard) clip.timelineDurationMs else clipDurationMs(clip, 1.0))
                    .takeIf { it > 0 }
                    ?: clipDurationMs(clip, 1.0).takeIf { it > 0 }
                    ?: DEFAULT_CARD_DURATION_MS

                editedBuilder
                    .setDurationUs(durationMs * 1000L)
                    .setFrameRate(DEFAULT_FPS)
            }

            videoItems += editedBuilder.build()
        }

        require(videoItems.isNotEmpty() || audioLanes.isNotEmpty()) {
            "টাইমলাইন খালি: এক্সপোর্ট করার আগে অন্তত একটি দৃশ্যমান ক্লিপ যোগ করুন"
        }

        val sequences = mutableListOf<EditedMediaItemSequence>()
        
        if (videoItems.isNotEmpty()) {
            sequences += EditedMediaItemSequence.Builder()
                // মিক্সড আইটেম (ইমেজ/কার্ডে অডিও নেই) অন্যথায় অডিও ট্র্যাক ড্রপ বা ভেঙে যায়।
                .experimentalSetForceAudioTrack(true)
                .apply { 
                    videoItems.forEach { addItem(it) } 
                }
                .build()
        }
        
        for (lane in audioLanes) {
            sequences += EditedMediaItemSequence.Builder().apply {
                for ((gapUs, item) in lane.parts) {
                    if (gapUs > 0) addGap(gapUs)
                    addItem(item)
                }
            }.build()
        }

        return Composition.Builder(sequences).build()
    }
}