package com.motiongr.videoedit.export

import android.content.Context
import android.graphics.*
import android.net.Uri
import android.util.Log
import androidx.core.graphics.PathParser
import java.io.File
import kotlin.math.pow

object OverlayRenderer {

    private const val TAG = "OverlayRenderer"
    private val clipBitmapCache = HashMap<String, Bitmap>()

    fun clearCache() {
        for (bmp in clipBitmapCache.values) {
            if (!bmp.isRecycled) {
                bmp.recycle()
            }
        }
        clipBitmapCache.clear()
    }

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
        fontSizeSp: Float = 28f,
        fontFamily: String = "Poppins",
        textColorInt: Int = Color.WHITE,
        strokeColorInt: Int = Color.TRANSPARENT,
        strokeWidthPx: Float = 0f,
        shadowColorInt: Int = Color.TRANSPARENT,
        shadowBlurPx: Float = 0f,
        shadowOffsetX: Float = 0f,
        shadowOffsetY: Float = 0f,
        bgColorInt: Int = Color.TRANSPARENT,
        bgPaddingPx: Float = 8f,
        textAlignStr: String = "center",
        scaleMultiplier: Float = 1.0f
    ): Bitmap {
        val u = width / 375f
        val textSizeCalculated = fontSizeSp * scaleMultiplier * u

        val typeface = loadTypeface(context, fontFamily)

        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = textColorInt
            textSize = textSizeCalculated
            this.typeface = typeface
            textAlign = Paint.Align.LEFT

            if (shadowColorInt != Color.TRANSPARENT && shadowBlurPx > 0f) {
                setShadowLayer(
                    shadowBlurPx * u,
                    shadowOffsetX * u,
                    shadowOffsetY * u,
                    shadowColorInt
                )
            }
        }

        val textWidth = textPaint.measureText(text)
        val fontMetrics = textPaint.fontMetrics
        val textHeight = fontMetrics.descent - fontMetrics.ascent
        val pad = bgPaddingPx * u

        val bmpW = (textWidth + pad * 2f).toInt().coerceAtLeast(16)
        val bmpH = (textHeight + pad * 2f).toInt().coerceAtLeast(16)

        val bitmap = Bitmap.createBitmap(bmpW, bmpH, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val x = pad
        val y = pad - fontMetrics.ascent

        if (bgColorInt != Color.TRANSPARENT) {
            val bgRect = RectF(0f, 0f, bmpW.toFloat(), bmpH.toFloat())
            val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = bgColorInt
                style = Paint.Style.FILL
            }
            canvas.drawRoundRect(bgRect, 4f * u, 4f * u, bgPaint)
        }

        if (strokeColorInt != Color.TRANSPARENT && strokeWidthPx > 0f) {
            val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = strokeColorInt
                textSize = textSizeCalculated
                this.typeface = typeface
                textAlign = Paint.Align.LEFT
                style = Paint.Style.STROKE
                strokeWidth = strokeWidthPx * u
            }
            canvas.drawText(text, x, y, strokePaint)
        }

        canvas.drawText(text, x, y, textPaint)

        return bitmap
    }

    /**
     * ফন্ট লোড করে (অ্যাসেট থেকে অথবা ডিফল্ট)
     */
    private fun loadTypeface(context: Context, fontFamily: String): Typeface {
        return try {
            val assetPath = "fonts/${fontFamily}-Bold.ttf"
            Typeface.createFromAsset(context.assets, assetPath)
        } catch (e: Exception) {
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
        val logoSize = 32f * scale
        val margin = 16f * scale
        val x = width - logoSize - margin
        val y = height - logoSize - margin

        try {
            val pathData = "M 256 278 L 256 767 L 566 278 L 566 766 L 819 279 L 819 740"
            val path = PathParser.createPathFromPathData(pathData)
            val matrix = Matrix()
            val s = logoSize / 1080f
            matrix.postScale(s, s)
            matrix.postTranslate(x, y)
            path.transform(matrix)

            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.argb(220, 255, 255, 255)
                style = Paint.Style.STROKE
                strokeWidth = 108f * s
                strokeCap = Paint.Cap.BUTT
                strokeJoin = Paint.Join.BEVEL
                setShadowLayer(
                    6f * scale,
                    2f * scale,
                    2f * scale,
                    Color.argb(180, 0, 0, 0)
                )
            }
            canvas.drawPath(path, paint)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to render SVG logo watermark, fallback to text", e)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.argb(220, 255, 255, 255)
                textSize = 36f * scale
                typeface = Typeface.DEFAULT_BOLD
                textAlign = Paint.Align.RIGHT
            }
            canvas.drawText("motionGr", width - margin, height - margin, paint)
        }
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
     * বিটম্যাপে কালার গ্রেডিং এবং ভিনিয়েট ফিল্টার প্রয়োগ করে
     */
    fun applyColorGrading(
        bitmap: Bitmap,
        cg: ColorGradingSpec
    ): Bitmap {
        if (cg.brightness == 0.0 && cg.contrast == 1.0 && cg.saturation == 1.0 &&
            cg.temperature == 0.0 && cg.exposure == 0.0 && cg.vignette == 0.0) {
            return bitmap
        }

        val w = bitmap.width
        val h = bitmap.height
        if (w <= 0 || h <= 0) return bitmap

        val output = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)

        val cm = ColorMatrix()
        cm.setSaturation(cg.saturation.toFloat().coerceIn(0f, 2f))

        val contrastScale = cg.contrast.toFloat().coerceIn(0.5f, 2f)
        val contrastTranslate = (-0.5f * contrastScale + 0.5f) * 255f
        val contrastCm = ColorMatrix(floatArrayOf(
            contrastScale, 0f, 0f, 0f, contrastTranslate,
            0f, contrastScale, 0f, 0f, contrastTranslate,
            0f, 0f, contrastScale, 0f, contrastTranslate,
            0f, 0f, 0f, 1f, 0f
        ))
        cm.postConcat(contrastCm)

        val gain = 2.0.pow(cg.exposure).toFloat()
        val tempR = (gain * (1.0f + 0.25f * cg.temperature.toFloat())).coerceAtLeast(0f)
        val tempB = (gain * (1.0f - 0.25f * cg.temperature.toFloat())).coerceAtLeast(0f)
        val bOffset = (cg.brightness * 255.0).toFloat().coerceIn(-128f, 128f)

        val colorScaleCm = ColorMatrix(floatArrayOf(
            tempR, 0f, 0f, 0f, bOffset,
            0f, gain, 0f, 0f, bOffset,
            0f, 0f, tempB, 0f, bOffset,
            0f, 0f, 0f, 1f, 0f
        ))
        cm.postConcat(colorScaleCm)

        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
            colorFilter = ColorMatrixColorFilter(cm)
        }
        canvas.drawBitmap(bitmap, 0f, 0f, paint)

        if (cg.vignette > 0.0) {
            val vigVal = cg.vignette.toFloat().coerceIn(0f, 1f)
            val cx = w / 2f
            val cy = h / 2f
            val radius = kotlin.math.sqrt((cx * cx + cy * cy).toDouble()).toFloat()
            val shader = RadialGradient(
                cx, cy, radius,
                intArrayOf(Color.TRANSPARENT, Color.argb((vigVal * 200).toInt(), 0, 0, 0)),
                floatArrayOf(0.4f, 1.0f),
                Shader.TileMode.CLAMP
            )
            val vigPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                this.shader = shader
            }
            canvas.drawRect(0f, 0f, w.toFloat(), h.toFloat(), vigPaint)
        }

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
        val u = width / 375f

        val cacheKey = if (clip.clipType != "video") {
            "${clip.id}_${clip.clipType}_${clip.label}_${clip.scale}_${clip.rotation}_${clip.opacity}_${clip.colorGrading.hashCode()}_${clip.chromaKey.hashCode()}_${width}x${height}"
        } else null

        var overlayBmp: Bitmap? = if (cacheKey != null) clipBitmapCache[cacheKey] else null
        val isCached = overlayBmp != null

        if (overlayBmp == null) {
            when (clip.clipType) {
            "drawing" -> {
                if (clip.strokes.isNotEmpty()) {
                    val size = (120 * clip.scale * u).toInt().coerceAtLeast(16)
                    overlayBmp = renderDrawingOverlay(clip.strokes, size, size)
                }
            }
            "element" -> {
                val size = (80 * clip.scale * u).toInt().coerceAtLeast(16)
                val svgStr = clip.svgPath ?: clip.sourcePath
                if (svgStr != null && svgStr.contains("d=")) {
                    try {
                        val dMatch = Regex("""d="([^"]+)"""").find(svgStr)
                        if (dMatch != null) {
                            val pathData = dMatch.groupValues[1]
                            val path = PathParser.createPathFromPathData(pathData)
                            val bounds = RectF()
                            path.computeBounds(bounds, true)
                            if (bounds.width() > 0 && bounds.height() > 0) {
                                val s = size.toFloat() / maxOf(bounds.width(), bounds.height())
                                val m = Matrix()
                                m.postTranslate(-bounds.left, -bounds.top)
                                m.postScale(s, s)
                                path.transform(m)

                                val elBmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
                                val elCanvas = Canvas(elBmp)
                                val elPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                                    color = if (clip.textStyle.textColor != 0L && clip.textStyle.textColor != 0xFFFFFFFFL) {
                                        clip.textStyle.textColor.toInt()
                                    } else Color.WHITE
                                    style = Paint.Style.FILL
                                }
                                elCanvas.drawPath(path, elPaint)
                                overlayBmp = elBmp
                            }
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to parse SVG element path", e)
                    }
                }

                if (overlayBmp == null) {
                    val elBmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
                    val elCanvas = Canvas(elBmp)
                    val elPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        color = if (clip.textStyle.backgroundColor != 0L) {
                            clip.textStyle.backgroundColor.toInt()
                        } else Color.WHITE
                        style = Paint.Style.FILL
                    }
                    val rect = RectF(0f, 0f, size.toFloat(), size.toFloat())
                    elCanvas.drawRoundRect(rect, 8f * u, 8f * u, elPaint)
                    overlayBmp = elBmp
                }
            }
            "sticker" -> {
                val path = clip.stickerAssetPath?.takeIf { it.isNotEmpty() } ?: clip.sourcePath
                if (path != null) {
                    overlayBmp = loadBitmap(context, path, (150 * clip.scale * u).toInt().coerceAtLeast(16), (150 * clip.scale * u).toInt().coerceAtLeast(16))
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
                    textAlignStr = clip.textStyle.textAlign,
                    scaleMultiplier = clip.scale.toFloat()
                )
            }
            "image" -> {
                val path = clip.sourcePath
                if (path != null) {
                    overlayBmp = loadBitmap(context, path, (180 * clip.scale * u).toInt().coerceAtLeast(16), (180 * clip.scale * u).toInt().coerceAtLeast(16))
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
                            overlayBmp = Bitmap.createScaledBitmap(frame, (180 * clip.scale * u).toInt().coerceAtLeast(16), (180 * clip.scale * u).toInt().coerceAtLeast(16), true)
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
                overlayBmp = renderTextOverlay(context, clip.label, width, height, scaleMultiplier = clip.scale.toFloat())
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

        if (clip.colorGrading.brightness != 0.0 || clip.colorGrading.contrast != 1.0 ||
            clip.colorGrading.saturation != 1.0 || clip.colorGrading.temperature != 0.0 ||
            clip.colorGrading.exposure != 0.0 || clip.colorGrading.vignette != 0.0) {
            val graded = applyColorGrading(overlayBmp, clip.colorGrading)
            if (graded != overlayBmp && !overlayBmp.isRecycled) {
                overlayBmp.recycle()
            }
            overlayBmp = graded
        }

            if (cacheKey != null && overlayBmp != null) {
                clipBitmapCache[cacheKey] = overlayBmp
            }
        }

        canvas.save()
        val matrix = Matrix()
        matrix.postRotate(clip.rotation.toFloat())
        matrix.postTranslate((clip.positionX * u).toFloat(), (clip.positionY * u).toFloat())

        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        if (clip.opacity < 1.0) {
            paint.alpha = (clip.opacity * 255).toInt().coerceIn(0, 255)
        }

        canvas.drawBitmap(overlayBmp, matrix, paint)
        canvas.restore()

        if (!isCached && overlayBmp != null && !overlayBmp.isRecycled) {
            overlayBmp.recycle()
        }
    }
}