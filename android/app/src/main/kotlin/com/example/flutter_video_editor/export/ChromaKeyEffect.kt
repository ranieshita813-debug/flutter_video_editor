package com.example.flutter_video_editor.export

import android.content.Context
import androidx.media3.effect.GlEffect
import androidx.media3.effect.GlShaderProgram

class ChromaKeyEffect(
    private val keyColor: Int = 0x00FF00,
    private val similarity: Float = 0.4f,
    private val smoothness: Float = 0.1f,
    private val spillSuppress: Float = 0.5f
) : GlEffect {

    override fun toGlShaderProgram(context: Context, useHdr: Boolean): GlShaderProgram {
        return object : GlShaderProgram {
            override fun use() = Unit

            override fun setFloat(name: String, value: Float) = Unit

            override fun setFloat2(name: String, value0: Float, value1: Float) = Unit

            override fun setFloat3(name: String, value0: Float, value1: Float, value2: Float) = Unit

            override fun setFloat4(
                name: String,
                value0: Float,
                value1: Float,
                value2: Float,
                value3: Float
            ) = Unit

            override fun setTexture2D(name: String, textureId: Int) = Unit

            override fun release() = Unit
        }
    }

    override fun release() = Unit
}
