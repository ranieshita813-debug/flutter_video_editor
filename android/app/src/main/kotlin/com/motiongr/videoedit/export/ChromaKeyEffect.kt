package com.motiongr.videoedit.export

import android.content.Context
import android.opengl.GLES20
import androidx.media3.common.VideoFrameProcessingException
import androidx.media3.common.util.GlProgram
import androidx.media3.common.util.GlUtil
import androidx.media3.common.util.Size
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
        return ChromaKeyShaderProgram(useHdr, keyColor, similarity, smoothness, spillSuppress)
    }

    private class ChromaKeyShaderProgram(
        useHdr: Boolean,
        keyColorInt: Int,
        similarityVal: Float,
        smoothnessVal: Float,
        spillVal: Float
    ) : BaseGlShaderProgram(useHdr, 1) {

        private val glProgram: GlProgram

        init {
            val vertexShader = """
                attribute vec4 aFramePosition;
                attribute vec4 aTexCoords;
                varying vec2 vTexCoords;
                void main() {
                    gl_Position = aFramePosition;
                    vTexCoords = aTexCoords.xy;
                }
            """.trimIndent()

            val fragmentShader = """
                precision mediump float;
                uniform sampler2D uTexSampler;
                uniform vec3 uKeyColor;
                uniform float uSimilarity;
                uniform float uSmoothness;
                uniform float uSpill;
                varying vec2 vTexCoords;

                void main() {
                    vec4 texColor = texture2D(uTexSampler, vTexCoords);
                    vec3 color = texColor.rgb;

                    vec3 diff = color - uKeyColor;
                    float dist = length(diff) / 1.732051;

                    float minThresh = uSimilarity * 0.7;
                    float maxThresh = minThresh + uSmoothness;

                    float alpha = smoothstep(minThresh, maxThresh, dist);

                    float maxOther = max(color.r, color.b);
                    if (color.g > maxOther) {
                        float greenSpill = color.g - maxOther;
                        color.g -= greenSpill * uSpill;
                    }

                    gl_FragColor = vec4(color, texColor.a * alpha);
                }
            """.trimIndent()

            try {
                glProgram = GlProgram(vertexShader, fragmentShader)
                val r = ((keyColorInt shr 16) and 0xFF) / 255.0f
                val g = ((keyColorInt shr 8) and 0xFF) / 255.0f
                val b = (keyColorInt and 0xFF) / 255.0f

                glProgram.setBufferAttribute(
                    "aFramePosition",
                    GlUtil.getNormalizedCoordinateBounds(),
                    4
                )
                glProgram.setBufferAttribute(
                    "aTexCoords",
                    GlUtil.getTextureCoordinateBounds(),
                    4
                )
                glProgram.setFloatUniform("uKeyColor", floatArrayOf(r, g, b))
                glProgram.setFloatUniform("uSimilarity", similarityVal.coerceIn(0.01f, 1.0f))
                glProgram.setFloatUniform("uSmoothness", smoothnessVal.coerceIn(0.001f, 1.0f))
                glProgram.setFloatUniform("uSpill", spillVal.coerceIn(0.0f, 1.0f))
            } catch (e: Exception) {
                throw VideoFrameProcessingException(e)
            }
        }

        override fun configure(inputWidth: Int, inputHeight: Int): Size {
            return Size(inputWidth, inputHeight)
        }

        override fun drawFrame(inputTextureId: Int, presentationTimeUs: Long) {
            try {
                glProgram.use()
                glProgram.setSamplerTexIdUniform("uTexSampler", inputTextureId, 0)
                glProgram.bindAttributesAndUniforms()
                GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
            } catch (e: Exception) {
                throw VideoFrameProcessingException(e)
            }
        }
    }
}
