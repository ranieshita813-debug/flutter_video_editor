package com.example.flutter_video_editor.export

import android.content.Context
import android.graphics.*
import android.net.Uri
import android.util.Log
import androidx.core.content.res.ResourcesCompat
import java.io.File

object OverlayRenderer {

    private const val TAG = "OverlayRenderer"

    /**
     * বিটম্যাপ লোড করে নির্দিষ্ট সাইজে রিসাইজ করে
     */
    fun loadBitmap(context: Context, path: String, width: Int, height: Int): Bitmap? {
        return try {
            val inputStream = when {
                // কন্টেন্ট URI (গ্যালারি/ক্যামেরা)
                path.startsWith("content://") ->
                    context.contentResolver.openInputStream(Uri.parse(path))

                // অ্যাসেট পাথ (ফ্লাটার অ্যাসেট)
                path.startsWith("asset://") || path.startsWith("assets://") ||
                        path.startsWith("asset/") || path.startsWith("assets/") ||
                        path.startsWith("file:///android_asset/") -> {
                    val assetPath = normalizeAssetPath(path)
                    context.assets.open(assetPath)
                }

                // ফাইল সিস্টেম পাথ
                else -> File(path.removePrefix("file://")).inputStream()
            }

            inputStream?.use { stream ->
                val options = BitmapFactory.Options().apply {
                    inPreferredConfig = Bitmap.Config.ARGB_8888
                }

                val raw = BitmapFactory.decodeStream(stream, null, options) ?: return null

                // ইতিমধ্যে কাঙ্ক্ষিত সাইজ হলে রিসাইজ করবেন না
                if (raw.width == width && raw.height == height) {
                    return raw
                }

                val scaled = Bitmap.createScaledBitmap(raw, width, height, true)
                if (scaled != raw) {
                    raw.recycle()
                }
                scaled
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load bitmap from path: $path", e)
            null
        }
    }

    /**
     * অ্যাসেট পাথ নরমালাইজ করে
     */
    private fun normalizeAssetPath(path: String): String {
        var ap = path
            .removePrefix("asset://")
            .removePrefix("assets://")
            .removePrefix("asset/")
            .removePrefix("assets/")
            .removePrefix("file:///android_asset/")
            .removePrefix("/")

        if (!ap.startsWith("flutter_assets/")) {
            ap = "flutter_assets/$ap"
        }

        return ap
    }

    /**
     * টেক্সট ওভারলে বিটম্যাপ তৈরি করে
     */
    fun renderTextOverlay(
        context: Context,
        text: String,
        width: Int,
        height: Int,
        fontSizeSp: Float = 48f,
        fontFamily: String = "Poppins",
        textColorInt: Int = Color.WHITE,
        strokeColorInt: Int = Color.TRANSPARENT,
        strokeWidthPx: Float = 0f,
        shadowColorInt: Int = Color.TRANSPARENT,
        shadowBlurPx: Float = 0f,
        shadowOffsetX: Float = 0f,
        shadowOffsetY: Float = 0f,
        bgColorInt: Int = Color.TRANSPARENT,
        bgPaddingPx: Float = 0f,
        textAlignStr: String = "center"
    ): Bitmap {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val scale = height / 720f
        val textSizeCalculated = fontSizeSp * scale

        val align = when (textAlignStr.lowercase()) {
            "left" -> Paint.Align.LEFT
            "right" -> Paint.Align.RIGHT
            else -> Paint.Align.CENTER
        }

        // ফন্ট লোডিং (অ্যাসেট থেকে অথবা ডিফল্ট)
        val typeface = loadTypeface(context, fontFamily)

        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = textColorInt
            textSize = textSizeCalculated
            this.typeface = typeface
            textAlign = align

            // শ্যাডো শুধুমাত্র ইউজার দিলেই যোগ হবে
            if (shadowColorInt != Color.TRANSPARENT && shadowBlurPx > 0f) {
                setShadowLayer(
                    shadowBlurPx * scale,
                    shadowOffsetX * scale,
                    shadowOffsetY * scale,
                    shadowColorInt
                )
            }
            // অন্যথায় কোনো শ্যাডো নেই (ডিফল্ট কালো শ্যাডো সরানো হয়েছে)
        }

        // টেক্সট পজিশন
        val x = when (align) {
            Paint.Align.LEFT -> width * 0.1f
            Paint.Align.RIGHT -> width * 0.9f
            else -> width / 2f
        }
        val y = height * 0.8f

        // ব্যাকগ্রাউন্ড বক্স (ঐচ্ছিক)
        if (bgColorInt != Color.TRANSPARENT) {
            val textWidth = textPaint.measureText(text)
            val fontMetrics = textPaint.fontMetrics
            val pad = bgPaddingPx * scale

            val left = when (align) {
                Paint.Align.LEFT -> x - pad
                Paint.Align.RIGHT -> x - textWidth - pad
                else -> x - (textWidth / 2f) - pad
            }

            val bgRect = RectF(
                left,
                y + fontMetrics.top - pad,
                left + textWidth + (pad * 2f),
                y + fontMetrics.bottom + pad
            )

            val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = bgColorInt
                style = Paint.Style.FILL
            }

            canvas.drawRoundRect(bgRect, 8f * scale, 8f * scale, bgPaint)
        }

        // স্ট্রোক রেন্ডারিং (ঐচ্ছিক)
        if (strokeColorInt != Color.TRANSPARENT && strokeWidthPx > 0f) {
            val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = strokeColorInt
                textSize = textSizeCalculated
                this.typeface = typeface
                textAlign = align
                style = Paint.Style.STROKE
                strokeWidth = strokeWidthPx * scale
            }
            canvas.drawText(text, x, y, strokePaint)
        }

        // মূল টেক্সট রেন্ডার
        canvas.drawText(text, x, y, textPaint)

        return bitmap
    }

    /**
     * ফন্ট লোড করে (অ্যাসেট থেকে অথবা ডিফল্ট)
     */
    private fun loadTypeface(context: Context, fontFamily: String): Typeface {
        return try {
            // অ্যাসেট থেকে ফন্ট লোড করার চেষ্টা (fonts/ ফোল্ডারে থাকতে হবে)
            val assetPath = "fonts/${fontFamily}-Bold.ttf"
            Typeface.createFromAsset(context.assets, assetPath)
        } catch (e: Exception) {
            Log.w(TAG, "Font '$fontFamily' not found in assets, using default bold", e)
            Typeface.DEFAULT_BOLD
        }
    }

    /**
     * ওয়াটারমার্ক ওভারলে বিটম্যাপ তৈরি করে
     */
    fun renderWatermarkOverlay(
        width: Int,
        height: Int,
        text: String = "motionGr"
    ): Bitmap {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawWatermarkOverlayOnCanvas(canvas, width, height, text)
        return bitmap
    }

    fun drawWatermarkOverlayOnCanvas(
        canvas: Canvas,
        width: Int,
        height: Int,
        text: String = "motionGr"
    ) {
        val scale = height / 720f
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(220, 255, 255, 255)
            textSize = 42f * scale
            typeface = Typeface.DEFAULT_BOLD
            textAlign = Paint.Align.RIGHT
            setShadowLayer(
                6f * scale,
                2f * scale,
                2f * scale,
                Color.argb(180, 0, 0, 0)
            )
        }
        val x = width - (32f * scale)
        val y = height - (32f * scale)
        canvas.drawText("motionGr", x, y, paint)
    }

    /**
     * ড্রয়িং স্ট্রোক ওভারলে বিটম্যাপ তৈরি করে
     */
    fun renderDrawingOverlay(
        strokes: List<DrawingStrokeSpec>,
        width: Int,
        height: Int
    ): Bitmap {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        for (stroke in strokes) {
            if (stroke.points.size < 2) continue

            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                // Long থেকে Int-এ কনভার্ট (Android color format)
                color = stroke.color.toInt()
                strokeWidth = (stroke.strokeWidth * (height / 720f)).toFloat()
                style = Paint.Style.STROKE
                strokeCap = Paint.Cap.ROUND
                strokeJoin = Paint.Join.ROUND
            }

            val path = Path()
            val first = stroke.points[0]
            path.moveTo((first.x * width).toFloat(), (first.y * height).toFloat())

            for (i in 1 until stroke.points.size) {
                val pt = stroke.points[i]
                path.lineTo((pt.x * width).toFloat(), (pt.y * height).toFloat())
            }

            canvas.drawPath(path, paint)
        }

        return bitmap
    }

    /**
     * বিটম্যাপে ক্রুমা কী ফিল্টারিং প্রয়োগ করে
     */
    fun applyChromaKey(
        bitmap: Bitmap,
        keyColor: Long,
        similarity: Double,
        smoothness: Double,
        spill: Double
    ): Bitmap {
        val w = bitmap.width
        val h = bitmap.height
        if (w <= 0 || h <= 0) return bitmap

        val pixels = IntArray(w * h)
        bitmap.getPixels(pixels, 0, w, 0, 0, w, h)

        val keyInt = keyColor.toInt()
        val keyR = (keyInt shr 16) and 0xFF
        val keyG = (keyInt shr 8) and 0xFF
        val keyB = keyInt and 0xFF

        val sim = (similarity / 100.0).toFloat().coerceIn(0.01f, 1.0f)
        val smooth = (smoothness / 100.0).toFloat().coerceIn(0.001f, 1.0f)
        val minThresh = sim * 0.7f
        val maxThresh = minThresh + smooth
        val spillFactor = (spill / 100.0).toFloat().coerceIn(0.0f, 1.0f)

        for (i in pixels.indices) {
            val px = pixels[i]
            val a = (px ushr 24) and 0xFF
            if (a == 0) continue

            var r = (px shr 16) and 0xFF
            var g = (px shr 8) and 0xFF
            var b = px and 0xFF

            val dr = (r - keyR).toFloat()
            val dg = (g - keyG).toFloat()
            val db = (b - keyB).toFloat()
            val dist = kotlin.math.sqrt(dr * dr + dg * dg + db * db) / 441.67f

            val factor = when {
                dist <= minThresh -> 0f
                dist >= maxThresh -> 1f
                else -> (dist - minThresh) / (maxThresh - minThresh)
            }

            if (spillFactor > 0f) {
                val maxOther = maxOf(r, b)
                if (g > maxOther) {
                    val greenSpill = (g - maxOther).toFloat()
                    g = (g - greenSpill * spillFactor).toInt().coerceIn(0, 255)
                }
            }

            val finalA = (a * factor).toInt().coerceIn(0, 255)
            pixels[i] = (finalA shl 24) or (r shl 16) or (g shl 8) or b
        }

        val output = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        output.setPixels(pixels, 0, w, 0, 0, w, h)
        return output
    }

    /**
     * ক্যানভাসে নির্দিষ্ট ওভারলে ক্লিপ আঁকে
     */
    fun drawOverlayClip(
        context: Context,
        canvas: Canvas,
        clip: ClipSpec,
        width: Int,
        height: Int,
        timelineMs: Long
    ) {
        val sx = width / 375f
        val sy = height / 667f

        var overlayBmp: Bitmap? = null

        when (clip.clipType) {
            "drawing" -> {
                if (clip.strokes.isNotEmpty()) {
                    overlayBmp = renderDrawingOverlay(clip.strokes, width, height)
                }
            }
            "sticker" -> {
                val path = clip.stickerAssetPath?.takeIf { it.isNotEmpty() } ?: clip.sourcePath
                if (path != null) {
                    overlayBmp = loadBitmap(context, path, (150 * sx).toInt(), (150 * sy).toInt())
                }
            }
            "text", "caption" -> {
                overlayBmp = renderTextOverlay(
                    context = context,
                    text = clip.label,
                    width = width,
                    height = height,
                    fontSizeSp = clip.textStyle.fontSize.toFloat(),
                    fontFamily = clip.fontFamily,
                    textColorInt = clip.textStyle.textColor.toInt(),
                    strokeColorInt = clip.textStyle.strokeColor.toInt(),
                    strokeWidthPx = clip.textStyle.strokeWidth.toFloat(),
                    shadowColorInt = clip.textStyle.shadowColor.toInt(),
                    shadowBlurPx = clip.textStyle.shadowBlurRadius.toFloat(),
                    shadowOffsetX = clip.textStyle.shadowOffsetX.toFloat(),
                    shadowOffsetY = clip.textStyle.shadowOffsetY.toFloat(),
                    bgColorInt = clip.textStyle.backgroundColor.toInt(),
                    bgPaddingPx = clip.textStyle.backgroundPadding.toFloat(),
                    textAlignStr = clip.textStyle.textAlign
                )
            }
            "image" -> {
                val path = clip.sourcePath
                if (path != null) {
                    overlayBmp = loadBitmap(context, path, (200 * sx).toInt(), (200 * sy).toInt())
                }
            }
            "video" -> {
                val path = clip.sourcePath
                if (path != null) {
                    val frameMs = (timelineMs - clip.timelineStartMs + clip.sourceInMs).coerceAtLeast(0L)
                    val retriever = android.media.MediaMetadataRetriever()
                    try {
                        if (path.startsWith("content://")) {
                            retriever.setDataSource(context, Uri.parse(path))
                        } else {
                            retriever.setDataSource(path.removePrefix("file://"))
                        }
                        val frame = retriever.getFrameAtTime(frameMs * 1000L, android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                        if (frame != null) {
                            overlayBmp = Bitmap.createScaledBitmap(frame, (200 * sx).toInt().coerceAtLeast(16), (200 * sy).toInt().coerceAtLeast(16), true)
                            if (overlayBmp != frame) frame.recycle()
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to extract video frame for overlay", e)
                    } finally {
                        try { retriever.release() } catch (_: Exception) {}
                    }
                }
            }
            else -> {
                overlayBmp = renderTextOverlay(context, clip.label, width, height)
            }
        }

        if (overlayBmp == null) return

        if (clip.chromaKey.enabled) {
            val keyed = applyChromaKey(
                bitmap = overlayBmp,
                keyColor = clip.chromaKey.keyColor,
                similarity = clip.chromaKey.similarity,
                smoothness = clip.chromaKey.smoothness,
                spill = clip.chromaKey.spill
            )
            if (keyed != overlayBmp && !overlayBmp.isRecycled) {
                overlayBmp.recycle()
            }
            overlayBmp = keyed
        }

        canvas.save()
        val matrix = Matrix()
        matrix.postScale(clip.scale.toFloat(), clip.scale.toFloat())
        matrix.postRotate(clip.rotation.toFloat())
        matrix.postTranslate((clip.positionX * sx).toFloat(), (clip.positionY * sy).toFloat())

        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        if (clip.opacity < 1.0) {
            paint.alpha = (clip.opacity * 255).toInt().coerceIn(0, 255)
        }

        canvas.drawBitmap(overlayBmp, matrix, paint)
        canvas.restore()

        if (!overlayBmp.isRecycled) {
            overlayBmp.recycle()
        }
    }
}