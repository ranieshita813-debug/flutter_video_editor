package com.example.flutter_video_editor.export

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Typeface

object OverlayRenderer {

    fun renderTextOverlay(
        text: String,
        width: Int,
        height: Int,
        fontSizeSp: Float = 48f,
        fontFamily: String = "Poppins"
    ): Bitmap {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = fontSizeSp * (height / 720f)
            typeface = Typeface.create(fontFamily, Typeface.BOLD)
            textAlign = Paint.Align.CENTER
            setShadowLayer(8f, 0f, 4f, Color.BLACK)
        }

        val x = width / 2f
        val y = height * 0.8f
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
