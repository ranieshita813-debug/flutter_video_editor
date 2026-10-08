package com.example.flutter_video_editor.export

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
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.Presentation
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.effect.SpeedChangeEffect
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import com.google.common.collect.ImmutableList
import java.io.File
import java.io.FileOutputStream
import kotlin.math.abs
import kotlin.math.max

/**
 * Builds a Media3 [Composition] from the Flutter timeline.
 *
 * Throws [IllegalArgumentException] with a readable message for invalid timelines
 * (missing files, empty timeline). ExportPlugin turns that into an EXPORT_FAILED error.
 *
 * Tested against the Media3 1.4.x API surface.
 */
@UnstableApi
object CompositionBuilder {

    private const val DEFAULT_FPS = 30
    private const val DEFAULT_CARD_DURATION_MS = 3000L
    private const val MIN_SPEED = 0.1
    private const val MAX_SPEED = 8.0
    private const val MAX_VOLUME = 4.0

    private val OVERLAY_TYPES = setOf("text", "caption", "drawing")
    private val IMAGE_EXT = setOf("jpg", "jpeg", "png", "webp", "heic", "heif", "bmp")
    private val AUDIO_EXT = setOf("mp3", "m4a", "aac", "wav", "ogg", "oga", "opus", "flac", "amr")

    // ---------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------

    /** H.264/H.265 encoders require even dimensions. */
    private fun even(v: Int): Int = max(v, 2) and 1.inv()

    private fun isContentUri(path: String) = path.startsWith("content://")

    private fun sourceExists(path: String): Boolean =
        isContentUri(path) || File(path.removePrefix("file://")).exists()

    private fun toUri(path: String): Uri =
        if (isContentUri(path)) Uri.parse(path) else Uri.fromFile(File(path.removePrefix("file://")))

    private fun extensionOf(path: String): String =
        if (isContentUri(path)) "" else path.substringAfterLast('.', "").lowercase()

    /** Black image used as the background of text / drawing "title cards". One file per resolution. */
    private fun blackFrame(context: Context, width: Int, height: Int): File {
        val file = File(context.cacheDir, "black_${width}x$height.png")
        if (!file.exists() || file.length() == 0L) {
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            try {
                Canvas(bitmap).drawColor(Color.BLACK)
                FileOutputStream(file).use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            } finally {
                bitmap.recycle()
            }
        }
        return file
    }

    private fun audioProcessors(speed: Double, volume: Double): List<AudioProcessor> {
        val list = mutableListOf<AudioProcessor>()
        if (abs(speed - 1.0) > 1e-3) {
            list += SonicAudioProcessor().apply { setSpeed(speed.toFloat()) }
        }
        // volume == 0 is handled by removing the audio track; here only real gain changes.
        if (volume > 0.0 && abs(volume - 1.0) > 1e-3) {
            val gain = volume.toFloat()
            list += ChannelMixingAudioProcessor().apply {
                putChannelMixingMatrix(ChannelMixingMatrix.create(1, 1).scaleBy(gain))
                putChannelMixingMatrix(ChannelMixingMatrix.create(2, 2).scaleBy(gain))
            }
        }
        return list
    }

    private fun overlayEffect(bitmap: Bitmap): Effect =
        OverlayEffect(ImmutableList.of(BitmapOverlay.createStaticBitmapOverlay(bitmap)))

    // ---------------------------------------------------------------------------------------
    // Main entry
    // ---------------------------------------------------------------------------------------

    fun buildComposition(context: Context, timeline: TimelineSpec): Composition {
        val width = even(timeline.settings.width)
        val height = even(timeline.settings.height)

        val visibleClips = timeline.clips.filter { it.isVisible }

        // Fail loudly instead of silently exporting a black video for a missing file.
        val missing = visibleClips.mapNotNull { it.sourcePath }.filter { !sourceExists(it) }
        require(missing.isEmpty()) { "Source file(s) not found: ${missing.joinToString()}" }

        val videoItems = mutableListOf<EditedMediaItem>()
        val audioItems = mutableListOf<EditedMediaItem>()

        for (clip in visibleClips) {
            val src = clip.sourcePath
            val ext = if (src != null) extensionOf(src) else ""
            val isOverlayClip = clip.clipType in OVERLAY_TYPES
            val isAudioOnly = src != null && ext in AUDIO_EXT
            val isImage = src != null && ext in IMAGE_EXT
            val hasNoMedia = src == null // text / drawing card on black background

            val speed = clip.speed.coerceIn(MIN_SPEED, MAX_SPEED)
            val volume = clip.volume.coerceIn(0.0, MAX_VOLUME)
            val speedChanged = abs(speed - 1.0) > 1e-3

            // ---------------- audio-only clip (music, voice-over) ----------------
            if (isAudioOnly) {
                val builder = MediaItem.Builder().setUri(toUri(src!!))
                if (clip.sourceOutMs > clip.sourceInMs) {
                    builder.setClippingConfiguration(
                        MediaItem.ClippingConfiguration.Builder()
                            .setStartPositionMs(clip.sourceInMs)
                            .setEndPositionMs(clip.sourceOutMs)
                            .build()
                    )
                }
                if (volume > 0.0) {
                    audioItems += EditedMediaItem.Builder(builder.build())
                        .setEffects(Effects(ImmutableList.copyOf(audioProcessors(speed, volume)), ImmutableList.of()))
                        .build()
                }
                continue
            }

            // ---------------- video / image / title-card clip ----------------
            val videoEffects = mutableListOf<Effect>()

            if (speedChanged && !isImage && !hasNoMedia) {
                // Keeps picture in sync with the Sonic audio speed change.
                videoEffects += SpeedChangeEffect(speed.toFloat())
            }

            videoEffects += Presentation.createForWidthAndHeight(width, height, Presentation.LAYOUT_SCALE_TO_FIT)

            if (clip.scale > 0.0 && (clip.scale != 1.0 || clip.rotation != 0.0)) {
                videoEffects += ScaleAndRotateTransformation.Builder()
                    .setScale(clip.scale.toFloat(), clip.scale.toFloat())
                    .setRotationDegrees(clip.rotation.toFloat())
                    .build()
            }

            if (isOverlayClip) {
                if (clip.clipType == "drawing") {
                    if (clip.strokes.isNotEmpty()) {
                        videoEffects += overlayEffect(
                            OverlayRenderer.renderDrawingOverlay(clip.strokes, width, height)
                        )
                    }
                } else {
                    val ts = clip.textStyle
                    videoEffects += overlayEffect(
                        OverlayRenderer.renderTextOverlay(
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
            }

            val uri = if (src != null) toUri(src) else Uri.fromFile(blackFrame(context, width, height))
            val mediaItemBuilder = MediaItem.Builder().setUri(uri)

            // Trimming only makes sense for real video; images / cards use a duration instead.
            if (!isImage && !hasNoMedia && clip.sourceOutMs > clip.sourceInMs) {
                mediaItemBuilder.setClippingConfiguration(
                    MediaItem.ClippingConfiguration.Builder()
                        .setStartPositionMs(clip.sourceInMs)
                        .setEndPositionMs(clip.sourceOutMs)
                        .build()
                )
            }

            val editedBuilder = EditedMediaItem.Builder(mediaItemBuilder.build())
                .setEffects(
                    Effects(
                        ImmutableList.copyOf(audioProcessors(speed, volume)),
                        ImmutableList.copyOf(videoEffects)
                    )
                )
                .setRemoveAudio(volume <= 0.0)

            if (isImage || hasNoMedia) {
                // Still images have no intrinsic duration -> Transformer fails without these two values.
                val durationMs = (clip.sourceOutMs - clip.sourceInMs)
                    .takeIf { it > 0 } ?: DEFAULT_CARD_DURATION_MS
                editedBuilder
                    .setDurationUs(durationMs * 1000L)
                    .setFrameRate(DEFAULT_FPS)
            }

            videoItems += editedBuilder.build()
        }

        require(videoItems.isNotEmpty() || audioItems.isNotEmpty()) {
            "Timeline is empty: add at least one visible clip before exporting"
        }

        val sequences = mutableListOf<EditedMediaItemSequence>()
        if (videoItems.isNotEmpty()) {
            sequences += EditedMediaItemSequence.Builder().apply { videoItems.forEach { addItem(it) } }.build()
        }
        if (audioItems.isNotEmpty()) {
            sequences += EditedMediaItemSequence.Builder().apply { audioItems.forEach { addItem(it) } }.build()
        }

        return Composition.Builder(sequences).build()
    }
}