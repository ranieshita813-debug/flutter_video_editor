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

    fun getInterpolatedKeyframeValue(
        clip: ClipSpec,
        property: String,
        relativeTimeMs: Long,
        defaultValue: Double
    ): Double {
        val ks = clip.keyframes.filter { it.property == property }.sortedBy { it.timeMs }
        if (ks.isEmpty()) return defaultValue

        if (relativeTimeMs <= ks.first().timeMs) return ks.first().value
        if (relativeTimeMs >= ks.last().timeMs) return ks.last().value

        for (i in 0 until ks.size - 1) {
            val a = ks[i]
            val b = ks[i + 1]
            if (relativeTimeMs >= a.timeMs && relativeTimeMs <= b.timeMs) {
                val span = b.timeMs - a.timeMs
                if (span <= 0) return b.value
                var t = (relativeTimeMs - a.timeMs).toDouble() / span.toDouble()

                t = when (a.curveType) {
                    "easeIn" -> t * t
                    "easeOut" -> 1.0 - (1.0 - t) * (1.0 - t)
                    "cubicBezier" -> t * t * (3.0 - 2.0 * t)
                    else -> t
                }
                return a.value + (b.value - a.value) * t
            }
        }
        return ks.last().value
    }

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

        val lines = text.split("\n")
        val fontMetrics = textPaint.fontMetrics
        val lineHeight = fontMetrics.descent - fontMetrics.ascent
        var maxLineWidth = 0f
        for (line in lines) {
            val lw = textPaint.measureText(line)
            if (lw > maxLineWidth) maxLineWidth = lw
        }

        val pad = bgPaddingPx * u
        val totalTextHeight = lineHeight * lines.size
        val bmpW = (maxLineWidth + pad * 2f).toInt().coerceAtLeast(16)
        val bmpH = (totalTextHeight + pad * 2f).toInt().coerceAtLeast(16)

        val bitmap = Bitmap.createBitmap(bmpW, bmpH, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        if (bgColorInt != Color.TRANSPARENT) {
            val bgRect = RectF(0f, 0f, bmpW.toFloat(), bmpH.toFloat())
            val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = bgColorInt
                style = Paint.Style.FILL
            }
            canvas.drawRoundRect(bgRect, 4f * u, 4f * u, bgPaint)
        }

        var startY = pad - fontMetrics.ascent
        for (line in lines) {
            val lw = textPaint.measureText(line)
            val lineX = when (textAlignStr.lowercase()) {
                "right" -> bmpW - pad - lw
                "center" -> (bmpW - lw) / 2f
                else -> pad
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
                canvas.drawText(line, lineX, startY, strokePaint)
            }

            canvas.drawText(line, lineX, startY, textPaint)
            startY += lineHeight
        }

        return bitmap
    }

    /**
     * ফন্ট লোড করে (অ্যাসেট, ড্রাইভ ফাইল অথবা ডিফল্ট)
     */
    private fun loadTypeface(context: Context, fontFamily: String): Typeface {
        if (fontFamily.isEmpty()) return Typeface.DEFAULT_BOLD
        val fontFile = File(fontFamily)
        if (fontFile.exists()) {
            try {
                return Typeface.createFromFile(fontFile)
            } catch (_: Exception) {}
        }
        val candidates = listOf(
            "flutter_assets/assets/fonts/${fontFamily}-Bold.ttf",
            "flutter_assets/assets/fonts/${fontFamily}-Regular.ttf",
            "flutter_assets/assets/fonts/${fontFamily}-SemiBold.ttf",
            "assets/fonts/${fontFamily}-Bold.ttf",
            "assets/fonts/${fontFamily}-Regular.ttf",
            "fonts/${fontFamily}-Bold.ttf",
            "fonts/${fontFamily}-Regular.ttf"
        )
        for (candidate in candidates) {
            try {
                return Typeface.createFromAsset(context.assets, candidate)
            } catch (_: Exception) {}
        }
        return Typeface.DEFAULT_BOLD
    }

    /**
     * Draws face tracking effects (blur, mosaic, text, sticker) onto frame canvas at relative clip time
     */
    fun drawFaceTrackingEffects(
        context: Context,
        canvas: Canvas,
        clip: ClipSpec,
        width: Int,
        height: Int,
        timelineMs: Long
    ) {
        val ftData = clip.faceTrackingData
        if (!ftData.isProcessed || ftData.persons.isEmpty()) return

        val relTimeMs = timelineMs - clip.timelineStartMs
        if (relTimeMs < 0 || relTimeMs > clip.timelineDurationMs) return

        for (person in ftData.persons) {
            val faceRect = person.rectAt(relTimeMs, margin = 0.25) ?: continue

            val leftPx = (faceRect.left * width).toFloat().coerceIn(0f, width.toFloat() - 1f)
            val topPx = (faceRect.top * height).toFloat().coerceIn(0f, height.toFloat() - 1f)
            val rectW = (faceRect.width * width).toFloat().coerceAtLeast(16f).coerceAtMost(width.toFloat() - leftPx)
            val rectH = (faceRect.height * height).toFloat().coerceAtLeast(16f).coerceAtMost(height.toFloat() - topPx)

            val destRect = RectF(leftPx, topPx, leftPx + rectW, topPx + rectH)

            for (fx in person.effects) {
                when (fx.type.lowercase()) {
                    "blur" -> {
                        val darkPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                            color = Color.argb(200, 20, 20, 20)
                            style = Paint.Style.FILL
                        }
                        canvas.drawRoundRect(destRect, 16f, 16f, darkPaint)
                    }
                    "mosaic" -> {
                        val darkPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                            color = Color.argb(200, 40, 40, 40)
                            style = Paint.Style.FILL
                        }
                        canvas.drawRoundRect(destRect, 8f, 8f, darkPaint)
                    }
                    "text" -> {
                        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                            color = Color.WHITE
                            textSize = (height * 0.035f).coerceAtLeast(18f)
                            typeface = Typeface.DEFAULT_BOLD
                            textAlign = Paint.Align.CENTER
                            setShadowLayer(4f, 2f, 2f, Color.BLACK)
                        }
                        val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                            color = Color.argb(200, 0, 0, 0)
                            style = Paint.Style.FILL
                        }
                        val txt = fx.text
                        val textW = paint.measureText(txt)
                        val textH = paint.textSize
                        val cx = destRect.centerX()
                        val cy = (destRect.top - 8f).coerceAtLeast(textH + 8f)
                        val bgRect = RectF(cx - textW / 2f - 12f, cy - textH - 4f, cx + textW / 2f + 12f, cy + 8f)
                        canvas.drawRoundRect(bgRect, 999f, 999f, bgPaint)
                        canvas.drawText(txt, cx, cy, paint)
                    }
                    "sticker" -> {
                        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                            textSize = Math.min(rectW, rectH) * 0.8f
                            textAlign = Paint.Align.CENTER
                        }
                        canvas.drawText(fx.stickerAsset, destRect.centerX(), destRect.centerY() + paint.textSize / 3f, paint)
                    }
                }
            }
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
        spill: Double,
        outputMode: String = "composite"
    ): Bitmap {
        val w = bitmap.width
        val h = bitmap.height
        if (w <= 0 || h <= 0) return bitmap

        if (outputMode == "source") return bitmap

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

            if (outputMode == "matte") {
                val mVal = (factor * 255).toInt().coerceIn(0, 255)
                pixels[i] = (255 shl 24) or (mVal shl 16) or (mVal shl 8) or mVal
                continue
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

    private fun applyBoxBlur(bitmap: Bitmap, blurRadius: Float): Bitmap {
        val r = blurRadius.toInt().coerceIn(1, 25)
        val w = bitmap.width
        val h = bitmap.height
        if (w <= 0 || h <= 0) return bitmap

        val scaled = Bitmap.createScaledBitmap(
            bitmap,
            (w / (r * 0.5f + 1f)).toInt().coerceAtLeast(8),
            (h / (r * 0.5f + 1f)).toInt().coerceAtLeast(8),
            true
        )
        val output = Bitmap.createScaledBitmap(scaled, w, h, true)
        if (scaled != bitmap && scaled != output) scaled.recycle()
        return output
    }

    private fun applyPixelate(bitmap: Bitmap, pixelSize: Float): Bitmap {
        val pSize = pixelSize.toInt().coerceIn(2, 64)
        val w = bitmap.width
        val h = bitmap.height
        if (w <= 0 || h <= 0) return bitmap

        val smallW = (w / pSize).coerceAtLeast(2)
        val smallH = (h / pSize).coerceAtLeast(2)
        val small = Bitmap.createScaledBitmap(bitmap, smallW, smallH, false)
        val output = Bitmap.createScaledBitmap(small, w, h, false)
        if (small != bitmap && small != output) small.recycle()
        return output
    }

    private fun applyFilmGrain(bitmap: Bitmap, amount: Float): Bitmap {
        val w = bitmap.width
        val h = bitmap.height
        if (w <= 0 || h <= 0) return bitmap

        val output = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        canvas.drawBitmap(bitmap, 0f, 0f, null)

        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            alpha = (amount * 40f).toInt().coerceIn(5, 100)
        }
        val random = java.util.Random()
        val numDots = ((w * h) * 0.005f * amount).toInt().coerceIn(100, 5000)
        for (i in 0 until numDots) {
            val x = random.nextInt(w).toFloat()
            val y = random.nextInt(h).toFloat()
            canvas.drawCircle(x, y, 1.5f, paint)
        }
        return output
    }

    private fun applyRgbSplit(bitmap: Bitmap, amount: Float): Bitmap {
        val w = bitmap.width
        val h = bitmap.height
        if (w <= 0 || h <= 0) return bitmap

        val output = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val shift = (amount * 10f).coerceIn(2f, 30f)

        val redPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            colorFilter = ColorMatrixColorFilter(ColorMatrix(floatArrayOf(
                1f, 0f, 0f, 0f, 0f,
                0f, 0f, 0f, 0f, 0f,
                0f, 0f, 0f, 0f, 0f,
                0f, 0f, 0f, 1f, 0f
            )))
        }
        val cyanPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            colorFilter = ColorMatrixColorFilter(ColorMatrix(floatArrayOf(
                0f, 0f, 0f, 0f, 0f,
                0f, 1f, 0f, 0f, 0f,
                0f, 0f, 1f, 0f, 0f,
                0f, 0f, 0f, 0.7f, 0f
            )))
        }
        canvas.drawBitmap(bitmap, -shift, 0f, redPaint)
        canvas.drawBitmap(bitmap, shift, 0f, cyanPaint)
        return output
    }

    /**
     * বিটম্যাপে ভিডিও ইফেক্ট ফিল্টার প্রয়োগ করে
     */
    fun applyVideoEffect(
        bitmap: Bitmap,
        effect: String,
        parameters: Map<String, Double> = emptyMap()
    ): Bitmap {
        if (effect.lowercase() == "none") return bitmap
        val w = bitmap.width
        val h = bitmap.height
        if (w <= 0 || h <= 0) return bitmap

        val effName = effect.lowercase()
        val intensity = (parameters["intensity"] ?: parameters["amount"] ?: parameters["strength"] ?: 1.0).toFloat()

        when {
            effName.contains("blur") -> {
                val blurAmt = (parameters["blurAmount"] ?: parameters["blur"] ?: (intensity * 5.0)).toFloat()
                return applyBoxBlur(bitmap, blurAmt)
            }
            effName.contains("pixelate") || effName.contains("mosaic") -> {
                val pSize = (parameters["sizePx"] ?: (intensity * 12.0)).toFloat()
                return applyPixelate(bitmap, pSize)
            }
            effName.contains("grain") -> {
                return applyFilmGrain(bitmap, intensity)
            }
            effName.contains("chromatic") || effName.contains("aberration") || effName.contains("rgbsplit") -> {
                return applyRgbSplit(bitmap, intensity)
            }
        }

        val output = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val cm = ColorMatrix()

        when {
            effName == "warm" || effName.contains("warm") -> {
                cm.set(floatArrayOf(
                    1.2f * intensity, 0f, 0f, 0f, 10f * intensity,
                    0f, 1.05f * intensity, 0f, 0f, 5f * intensity,
                    0f, 0f, 0.85f, 0f, 0f,
                    0f, 0f, 0f, 1f, 0f
                ))
            }
            effName == "cinematic" || effName.contains("cinematic") -> {
                cm.setSaturation(0.8f)
                val cCm = ColorMatrix(floatArrayOf(
                    0.9f, 0f, 0f, 0f, 5f,
                    0f, 1.0f, 0f, 0f, 0f,
                    0f, 0f, 1.2f, 0f, 10f,
                    0f, 0f, 0f, 1f, 0f
                ))
                cm.postConcat(cCm)
            }
            effName == "noir" || effName.contains("noir") || effName.contains("monochrome") || effName.contains("blackandwhite") || effName == "bw" -> {
                cm.setSaturation(0f)
                val cCm = ColorMatrix(floatArrayOf(
                    1.3f, 0f, 0f, 0f, -20f,
                    0f, 1.3f, 0f, 0f, -20f,
                    0f, 0f, 1.3f, 0f, -20f,
                    0f, 0f, 0f, 1f, 0f
                ))
                cm.postConcat(cCm)
            }
            effName == "vibrant" || effName.contains("vibrant") -> {
                cm.setSaturation(1.5f * intensity)
            }
            effName == "vintage" || effName == "retro" || effName.contains("vintage") || effName.contains("retro") || effName.contains("sepia") -> {
                cm.setSaturation(0.75f)
                val vCm = ColorMatrix(floatArrayOf(
                    1.1f, 0f, 0f, 0f, 15f,
                    0f, 0.95f, 0f, 0f, 5f,
                    0f, 0f, 0.8f, 0f, -10f,
                    0f, 0f, 0f, 1f, 0f
                ))
                cm.postConcat(vCm)
            }
            effName.contains("glitch") || effName.contains("vhs") -> {
                cm.set(floatArrayOf(
                    1.15f * intensity, 0f, 0.1f, 0f, 10f * intensity,
                    0f, 0.95f, 0f, 0f, 0f,
                    0.1f, 0f, 1.2f * intensity, 0f, 15f * intensity,
                    0f, 0f, 0f, 1f, 0f
                ))
            }
            effName == "matrix" || effName.contains("matrix") -> {
                cm.set(floatArrayOf(
                    0.3f, 0f, 0f, 0f, 0f,
                    0f, 1.4f * intensity, 0f, 0f, 20f * intensity,
                    0f, 0f, 0.3f, 0f, 0f,
                    0f, 0f, 0f, 1f, 0f
                ))
            }
            effName.contains("flame") || effName.contains("leak") || effName.contains("fire") -> {
                cm.set(floatArrayOf(
                    1.3f * intensity, 0f, 0f, 0f, 25f * intensity,
                    0f, 1.1f * intensity, 0f, 0f, 10f * intensity,
                    0f, 0f, 0.8f, 0f, 0f,
                    0f, 0f, 0f, 1f, 0f
                ))
            }
            effName.contains("glow") || effName.contains("bloom") -> {
                cm.setSaturation(1.3f * intensity)
                val gCm = ColorMatrix(floatArrayOf(
                    1.1f, 0f, 0f, 0f, 15f * intensity,
                    0f, 1.1f, 0f, 0f, 15f * intensity,
                    0f, 0f, 1.1f, 0f, 15f * intensity,
                    0f, 0f, 0f, 1f, 0f
                ))
                cm.postConcat(gCm)
            }
            effName.contains("sharpen") -> {
                cm.set(floatArrayOf(
                    1.2f * intensity, -0.1f, -0.1f, 0f, 0f,
                    -0.1f, 1.2f * intensity, -0.1f, 0f, 0f,
                    -0.1f, -0.1f, 1.2f * intensity, 0f, 0f,
                    0f, 0f, 0f, 1f, 0f
                ))
            }
            effName.contains("vignette") -> {
                cm.setSaturation(0.9f)
            }
            else -> {
                cm.setSaturation(1.1f * intensity)
            }
        }

        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
            colorFilter = ColorMatrixColorFilter(cm)
        }
        canvas.drawBitmap(bitmap, 0f, 0f, paint)

        if (effName.contains("vignette")) {
            val radiusVal = (parameters["radius"] ?: parameters["strength"] ?: 0.8).toFloat().coerceIn(0.2f, 1.0f)
            val cx = w / 2f
            val cy = h / 2f
            val radius = kotlin.math.sqrt((cx * cx + cy * cy).toDouble()).toFloat() * radiusVal
            val shader = RadialGradient(
                cx, cy, radius,
                intArrayOf(Color.TRANSPARENT, Color.argb(180, 0, 0, 0)),
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
            "${clip.id}_${clip.clipType}_${clip.label}_${clip.scale}_${width}x${height}"
        } else null

        var baseBmp: Bitmap? = if (cacheKey != null) clipBitmapCache[cacheKey] else null

        if (baseBmp == null) {
            when (clip.clipType) {
            "drawing" -> {
                if (clip.strokes.isNotEmpty()) {
                    val size = (120 * clip.scale * u).toInt().coerceAtLeast(16)
                    baseBmp = renderDrawingOverlay(clip.strokes, size, size)
                }
            }
            "element" -> {
                val size = (80 * clip.scale * u).toInt().coerceAtLeast(16)
                val svgStr = clip.elementProperties.svgPath ?: clip.svgPath ?: clip.sourcePath
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
                                    color = if (clip.elementProperties.fillColor != 0xFFFFFFFFL) {
                                        clip.elementProperties.fillColor.toInt()
                                    } else Color.WHITE
                                    style = Paint.Style.FILL
                                }
                                elCanvas.drawPath(path, elPaint)
                                baseBmp = elBmp
                            }
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to parse SVG element path", e)
                    }
                }

                if (baseBmp == null) {
                    val elBmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
                    val elCanvas = Canvas(elBmp)
                    val fillColor = clip.elementProperties.fillColor.toInt()
                    val strokeColor = clip.elementProperties.strokeColor.toInt()
                    val strokeWidth = (clip.elementProperties.strokeWidth * u).toFloat()

                    val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        color = if (fillColor != 0) fillColor else Color.WHITE
                        style = Paint.Style.FILL
                    }
                    val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        color = strokeColor
                        style = Paint.Style.STROKE
                        this.strokeWidth = strokeWidth
                    }

                    val shape = clip.elementProperties.shape.lowercase()
                    val sF = size.toFloat()

                    when (shape) {
                        "circle" -> {
                            elCanvas.drawCircle(sF / 2f, sF / 2f, sF / 2f - strokeWidth, fillPaint)
                            if (strokeColor != 0 && strokeWidth > 0) {
                                elCanvas.drawCircle(sF / 2f, sF / 2f, sF / 2f - strokeWidth / 2f, strokePaint)
                            }
                        }
                        "triangle" -> {
                            val path = Path().apply {
                                moveTo(sF / 2f, 0f)
                                lineTo(sF, sF)
                                lineTo(0f, sF)
                                close()
                            }
                            elCanvas.drawPath(path, fillPaint)
                            if (strokeColor != 0 && strokeWidth > 0) {
                                elCanvas.drawPath(path, strokePaint)
                            }
                        }
                        "star" -> {
                            val path = Path()
                            val cx = sF / 2f
                            val cy = sF / 2f
                            val outer = sF / 2f
                            val inner = outer * 0.4f
                            for (i in 0 until 10) {
                                val r = if (i % 2 == 0) outer else inner
                                val angle = i * Math.PI / 5 - Math.PI / 2
                                val x = (cx + r * Math.cos(angle)).toFloat()
                                val y = (cy + r * Math.sin(angle)).toFloat()
                                if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
                            }
                            path.close()
                            elCanvas.drawPath(path, fillPaint)
                            if (strokeColor != 0 && strokeWidth > 0) {
                                elCanvas.drawPath(path, strokePaint)
                            }
                        }
                        "arrow" -> {
                            val path = Path().apply {
                                moveTo(0f, sF * 0.35f)
                                lineTo(sF * 0.6f, sF * 0.35f)
                                lineTo(sF * 0.6f, sF * 0.1f)
                                lineTo(sF, sF * 0.5f)
                                lineTo(sF * 0.6f, sF * 0.9f)
                                lineTo(sF * 0.6f, sF * 0.65f)
                                lineTo(0f, sF * 0.65f)
                                close()
                            }
                            elCanvas.drawPath(path, fillPaint)
                            if (strokeColor != 0 && strokeWidth > 0) {
                                elCanvas.drawPath(path, strokePaint)
                            }
                        }
                        "line" -> {
                            val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                                color = if (fillColor != 0) fillColor else Color.WHITE
                                style = Paint.Style.STROKE
                                this.strokeWidth = strokeWidth.coerceAtLeast(4f * u)
                            }
                            elCanvas.drawLine(0f, sF / 2f, sF, sF / 2f, linePaint)
                        }
                        else -> { // rectangle
                            val rect = RectF(0f, 0f, sF, sF)
                            elCanvas.drawRoundRect(rect, 8f * u, 8f * u, fillPaint)
                            if (strokeColor != 0 && strokeWidth > 0) {
                                elCanvas.drawRoundRect(rect, 8f * u, 8f * u, strokePaint)
                            }
                        }
                    }
                    baseBmp = elBmp
                }
            }
            "sticker" -> {
                val path = clip.stickerAssetPath?.takeIf { it.isNotEmpty() } ?: clip.sourcePath
                if (path != null) {
                    baseBmp = loadBitmap(context, path, (150 * clip.scale * u).toInt().coerceAtLeast(16), (150 * clip.scale * u).toInt().coerceAtLeast(16))
                }
            }
            "text", "caption" -> {
                baseBmp = renderTextOverlay(
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
                    baseBmp = loadBitmap(context, path, (180 * clip.scale * u).toInt().coerceAtLeast(16), (180 * clip.scale * u).toInt().coerceAtLeast(16))
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
                            baseBmp = Bitmap.createScaledBitmap(frame, (180 * clip.scale * u).toInt().coerceAtLeast(16), (180 * clip.scale * u).toInt().coerceAtLeast(16), true)
                            if (baseBmp != frame) frame.recycle()
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to extract video frame for overlay", e)
                    } finally {
                        try { retriever.release() } catch (_: Exception) {}
                    }
                }
            }
            else -> {
                baseBmp = renderTextOverlay(context, clip.label, width, height, scaleMultiplier = clip.scale.toFloat())
            }
        }

            if (cacheKey != null && baseBmp != null) {
                clipBitmapCache[cacheKey] = baseBmp
            }
        }

        val rawBase = baseBmp ?: return
        var processedBmp: Bitmap = rawBase.copy(Bitmap.Config.ARGB_8888, true)

        if (clip.chromaKey.enabled) {
            val keyed = applyChromaKey(
                bitmap = processedBmp,
                keyColor = clip.chromaKey.keyColor,
                similarity = clip.chromaKey.similarity,
                smoothness = clip.chromaKey.smoothness,
                spill = clip.chromaKey.spill,
                outputMode = clip.chromaKey.output
            )
            if (keyed != processedBmp && !processedBmp.isRecycled) {
                processedBmp.recycle()
            }
            processedBmp = keyed
        }

        if (clip.colorGrading.brightness != 0.0 || clip.colorGrading.contrast != 1.0 ||
            clip.colorGrading.saturation != 1.0 || clip.colorGrading.temperature != 0.0 ||
            clip.colorGrading.exposure != 0.0 || clip.colorGrading.vignette != 0.0) {
            val graded = applyColorGrading(processedBmp, clip.colorGrading)
            if (graded != processedBmp && !processedBmp.isRecycled) {
                processedBmp.recycle()
            }
            processedBmp = graded
        }

        if (clip.effect != "none") {
            val fxBmp = applyVideoEffect(processedBmp, clip.effect, clip.effectParameters)
            if (fxBmp != processedBmp && !processedBmp.isRecycled) {
                processedBmp.recycle()
            }
            processedBmp = fxBmp
        }

        if (clip.shaderEffects.isNotEmpty()) {
            val clipRelMs = timelineMs - clip.timelineStartMs
            for (shaderFx in clip.shaderEffects) {
                if (shaderFx.isEnabled && clipRelMs >= shaderFx.startMs && clipRelMs <= shaderFx.endMs) {
                    val activeParams = shaderFx.getInterpolatedParameters(clipRelMs)
                    val fxBmp = applyVideoEffect(processedBmp, shaderFx.effectId, activeParams)
                    if (fxBmp != processedBmp && !processedBmp.isRecycled) {
                        processedBmp.recycle()
                    }
                    processedBmp = fxBmp
                }
            }
        }

        val relTimeMs = timelineMs - clip.timelineStartMs
        val posX = getInterpolatedKeyframeValue(clip, "positionX", relTimeMs, clip.positionX)
        val posY = getInterpolatedKeyframeValue(clip, "positionY", relTimeMs, clip.positionY)
        val rot = getInterpolatedKeyframeValue(clip, "rotation", relTimeMs, clip.rotation)
        val opacity = getInterpolatedKeyframeValue(clip, "opacity", relTimeMs, clip.opacity)

        canvas.save()
        val matrix = Matrix()
        matrix.postRotate(rot.toFloat())
        matrix.postTranslate((posX * u).toFloat(), (posY * u).toFloat())

        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        val finalOpacity = opacity.coerceIn(0.0, 1.0)
        if (finalOpacity < 1.0) {
            paint.alpha = (finalOpacity * 255).toInt().coerceIn(0, 255)
        }

        canvas.drawBitmap(processedBmp, matrix, paint)
        canvas.restore()

        if (!processedBmp.isRecycled) {
            processedBmp.recycle()
        }

        if (cacheKey == null && !rawBase.isRecycled) {
            rawBase.recycle()
        }
    }
}
