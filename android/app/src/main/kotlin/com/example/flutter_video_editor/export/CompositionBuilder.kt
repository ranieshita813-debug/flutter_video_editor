package com.example.flutter_video_editor.export

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.SonicAudioProcessor
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.Presentation
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.effect.TextureOverlay
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import com.google.common.collect.ImmutableList
import java.io.File

object CompositionBuilder {

    fun buildComposition(
        context: Context,
        timeline: TimelineSpec
    ): Composition {
        val videoItems = mutableListOf<EditedMediaItem>()

        for (clip in timeline.clips) {
            if (!clip.isVisible) continue

            val effectsList = mutableListOf<Effect>()

            // Scale & Presentation effect
            val presentation = Presentation.createForWidthAndHeight(
                timeline.settings.width,
                timeline.settings.height,
                Presentation.LAYOUT_SCALE_TO_FIT
            )
            effectsList.add(presentation)

            if (clip.scale != 1.0 || clip.rotation != 0.0) {
                val transform = ScaleAndRotateTransformation.Builder()
                    .setScale(clip.scale.toFloat(), clip.scale.toFloat())
                    .setRotationDegrees(clip.rotation.toFloat())
                    .build()
                effectsList.add(transform)
            }

            // Overlay rendering (text with styles or drawing)
            if (clip.clipType == "text" || clip.clipType == "caption") {
                val ts = clip.textStyle
                val bitmap = OverlayRenderer.renderTextOverlay(
                    text = clip.label,
                    width = timeline.settings.width,
                    height = timeline.settings.height,
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
                val bitmapOverlay = BitmapOverlay.createStaticBitmapOverlay(bitmap) as TextureOverlay
                effectsList.add(OverlayEffect(listOf(bitmapOverlay)))
            } else if (clip.clipType == "drawing" && clip.strokes.isNotEmpty()) {
                val bitmap = OverlayRenderer.renderDrawingOverlay(
                    clip.strokes,
                    timeline.settings.width,
                    timeline.settings.height
                )
                val bitmapOverlay = BitmapOverlay.createStaticBitmapOverlay(bitmap) as TextureOverlay
                effectsList.add(OverlayEffect(listOf(bitmapOverlay)))
            }

            val sourceUri = if (clip.sourcePath != null && File(clip.sourcePath).exists()) {
                Uri.fromFile(File(clip.sourcePath))
            } else {
                Uri.parse("file:///android_asset/placeholder.mp4")
            }

            val mediaItemBuilder = MediaItem.Builder().setUri(sourceUri)

            if (clip.sourceOutMs > clip.sourceInMs) {
                mediaItemBuilder.setClippingConfiguration(
                    MediaItem.ClippingConfiguration.Builder()
                        .setStartPositionMs(clip.sourceInMs)
                        .setEndPositionMs(clip.sourceOutMs)
                        .build()
                )
            }

            val audioProcessors = mutableListOf<AudioProcessor>()
            if (clip.speed != 1.0) {
                val sonic = SonicAudioProcessor().apply {
                    setSpeed(clip.speed.toFloat())
                }
                audioProcessors.add(sonic)
            }

            val editedMediaItem = EditedMediaItem.Builder(mediaItemBuilder.build())
                .setEffects(
                    Effects(
                        ImmutableList.copyOf(audioProcessors),
                        ImmutableList.copyOf(effectsList)
                    )
                )
                .setRemoveAudio(clip.volume == 0.0)
                .build()

            videoItems.add(editedMediaItem)
        }

        val sequenceBuilder = EditedMediaItemSequence.Builder()
        for (item in videoItems) {
            sequenceBuilder.addItem(item)
        }

        return Composition.Builder(listOf(sequenceBuilder.build())).build()
    }
}
