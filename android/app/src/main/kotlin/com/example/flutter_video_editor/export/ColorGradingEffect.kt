package com.example.flutter_video_editor.export

import androidx.media3.effect.GlMatrixTransformation

class ColorGradingEffect(
    private val brightness: Float = 0f,
    private val contrast: Float = 1f,
    private val saturation: Float = 1f,
    private val temperature: Float = 0f,
    private val exposure: Float = 0f
) : GlMatrixTransformation {

    override fun getGlMatrixArray(presentationTimeUs: Long): FloatArray {
        val matrix = FloatArray(16)
        android.opengl.Matrix.setIdentityM(matrix, 0)
        return matrix
    }
}
