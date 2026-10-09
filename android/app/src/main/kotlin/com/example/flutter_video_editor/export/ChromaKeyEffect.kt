package com.example.flutter_video_editor.export

import android.content.Context
import androidx.media3.effect.BaseGlShaderProgram
import androidx.media3.effect.GlEffect
import androidx.media3.effect.GlShaderProgram

class ChromaKeyEffect(
    private val keyColor: Int = 0x00FF00,
    private val similarity: Float = 0.4f,
    private val smoothness: Float = 0.1f,
    private val spillSuppress: Float = 0.5f
) : GlEffect {

    override fun toGlShaderProgram(context: Context, useHdr: Boolean): GlShaderProgram {
        return object : BaseGlShaderProgram(useHdr, 1) {
            override fun configure(inputWidth: Int, inputHeight: Int): androidx.media3.common.util.Size {
                return androidx.media3.common.util.Size(inputWidth, inputHeight)
            }

            override fun drawFrame(inputTextureId: Int, presentationTimeUs: Long) = Unit
        }
    }
}
