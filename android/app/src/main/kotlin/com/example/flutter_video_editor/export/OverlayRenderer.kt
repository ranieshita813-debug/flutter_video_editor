package com.example.flutter_video_editor.export

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface

object OverlayRenderer {

    fun renderTextOverlay(
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

        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = textColorInt
            textSize = textSizeCalculated
            typeface = Typeface.create(fontFamily, Typeface.BOLD)
            textAlign = align
            if (shadowColorInt != Color.TRANSPARENT && shadowBlurPx > 0f) {
                setShadowLayer(shadowBlurPx * scale, shadowOffsetX * scale, shadowOffsetY * scale, shadowColorInt)
            } else {
                setShadowLayer(8f * scale, 0f, 4f * scale, Color.BLACK)
            }
        }

        val x = when (align) {
            Paint.Align.LEFT -> width * 0.1f
            Paint.Align.RIGHT -> width * 0.9f
            else -> width / 2f
        }
        val y = height * 0.8f

        // Optional background box
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

        // Stroke rendering
        if (strokeColorInt != Color.TRANSPARENT && strokeWidthPx > 0f) {
            val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = strokeColorInt
                textSize = textSizeCalculated
                typeface = Typeface.create(fontFamily, Typeface.BOLD)
                textAlign = align
                style = Paint.Style.STROKE
                strokeWidth = strokeWidthPx * scale
            }
            canvas.drawText(text, x, y, strokePaint)
        }

        canvas.drawText(text, x, y, textPaint)
        return bitmap
    }

    fun renderWatermarkOverlay(
        width: Int,
        height: Int,
        text: String = "motionGr"
    ): Bitmap {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val scale = height / 720f

        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(180, 255, 255, 255)
            textSize = 24f * scale
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            textAlign = Paint.Align.RIGHT
            setShadowLayer(4f * scale, 1f * scale, 1f * scale, Color.argb(150, 0, 0, 0))
        }

        val x = width - (24f * scale)
        val y = height - (24f * scale)
        canvas.drawText(text, x, y, paint)
        return bitmap
    }

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
}
