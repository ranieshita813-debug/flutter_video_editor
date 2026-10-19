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
import java.io.File

class CustomShaderEffect(
    private val context: Context,
    private val effectId: String,
    private val initialParameters: Map<String, Double> = emptyMap(),
    private val shaderEffectSpec: ShaderEffectSpec? = null,
    private val startMs: Long = 0L,
    private val endMs: Long = 0L,
    private val baseStartMs: Long = 0L
) : GlEffect {

    override fun toGlShaderProgram(context: Context, useHdr: Boolean): GlShaderProgram {
        return CustomShaderProgram(
            context = this.context,
            useHdr = useHdr,
            effectId = effectId,
            initialParameters = initialParameters,
            shaderEffectSpec = shaderEffectSpec,
            startMs = startMs,
            endMs = endMs,
            baseStartMs = baseStartMs
        )
    }

    private class CustomShaderProgram(
        context: Context,
        useHdr: Boolean,
        private val effectId: String,
        private val initialParameters: Map<String, Double>,
        private val shaderEffectSpec: ShaderEffectSpec?,
        private val startMs: Long,
        private val endMs: Long,
        private val baseStartMs: Long
    ) : BaseGlShaderProgram(useHdr, 1) {

        private val glProgram: GlProgram
        private var surfaceWidth: Int = 1920
        private var surfaceHeight: Int = 1080

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

            val fragmentShader = getFragmentShaderForEffect(context, effectId)

            try {
                glProgram = GlProgram(vertexShader, fragmentShader)
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
            } catch (e: Exception) {
                throw VideoFrameProcessingException(e)
            }
        }

        override fun configure(inputWidth: Int, inputHeight: Int): Size {
            surfaceWidth = inputWidth
            surfaceHeight = inputHeight
            return Size(inputWidth, inputHeight)
        }

        override fun drawFrame(inputTextureId: Int, presentationTimeUs: Long) {
            val clipRelativeTimeMs = presentationTimeUs / 1000L
            val currentTimelineMs = baseStartMs + clipRelativeTimeMs

            val isActive = if (startMs > 0 || endMs > 0) {
                currentTimelineMs in startMs..endMs
            } else {
                true
            }

            try {
                glProgram.use()
                glProgram.setSamplerTexIdUniform("uTexSampler", inputTextureId, 0)

                val interpolatedParams = if (shaderEffectSpec != null) {
                    shaderEffectSpec.getInterpolatedParameters(clipRelativeTimeMs)
                } else {
                    initialParameters
                }

                val amount = if (isActive) {
                    (interpolatedParams["amount"]
                        ?: interpolatedParams["intensity"]
                        ?: interpolatedParams["strength"]
                        ?: 1.0).toFloat()
                } else {
                    0.0f
                }

                val speed = (interpolatedParams["speed"] ?: 1.0).toFloat()
                val radius = (interpolatedParams["radius"] ?: interpolatedParams["blur"] ?: 1.0).toFloat()
                val timeSec = clipRelativeTimeMs / 1000.0f

                setUniformIfPresent("uSize", floatArrayOf(surfaceWidth.toFloat(), surfaceHeight.toFloat()))
                setUniformIfPresent("uTime", timeSec)
                setUniformIfPresent("uAmount", amount)
                setUniformIfPresent("uSpeed", speed)
                setUniformIfPresent("uRadius", radius)
                setUniformIfPresent("uIntensity", amount)

                // Bind any additional dynamic float parameters
                for ((paramKey, paramVal) in interpolatedParams) {
                    setUniformIfPresent("u${paramKey.replaceFirstChar { it.uppercase() }}", paramVal.toFloat())
                    setUniformIfPresent(paramKey, paramVal.toFloat())
                }

                glProgram.bindAttributesAndUniforms()
                GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
            } catch (e: Exception) {
                throw VideoFrameProcessingException(e)
            }
        }

        private fun setUniformIfPresent(name: String, value: Float) {
            try {
                glProgram.setFloatUniform(name, value)
            } catch (_: Exception) {
                // Ignore uniform if not present in compiled GLSL shader
            }
        }

        private fun setUniformIfPresent(name: String, values: FloatArray) {
            try {
                glProgram.setFloatsUniform(name, values)
            } catch (_: Exception) {
                // Ignore uniform if not present in compiled GLSL shader
            }
        }

        companion object {
            private fun convertFlutterFragToGlslEs(rawFrag: String): String {
                var code = rawFrag
                code = code.replace(Regex("#version\\s+460\\s+core"), "")
                code = code.replace(Regex("#include\\s+<flutter/runtime_effect\\.glsl>"), "")
                code = code.replace("out vec4 fragColor;", "precision mediump float;\nvarying vec2 vTexCoords;")
                code = code.replace("uniform sampler2D uTexture;", "uniform sampler2D uTexSampler;")
                code = code.replace("FlutterFragCoord().xy / uSize", "vTexCoords")
                code = code.replace("FlutterFragCoord().xy", "(vTexCoords * uSize)")
                code = code.replace(Regex("\\btexture\\("), "texture2D(")
                code = code.replace("fragColor =", "gl_FragColor =")
                return code
            }

            private fun getFragmentShaderForEffect(context: Context, effectId: String): String {
                // Check if effectId points to a local file or CDN downloaded shader file
                if (effectId.endsWith(".frag") || effectId.contains("/") || effectId.contains("\\")) {
                    try {
                        val file = File(effectId)
                        if (file.exists() && file.canRead()) {
                            val rawContent = file.readText()
                            return convertFlutterFragToGlslEs(rawContent)
                        }
                    } catch (_: Exception) {
                    }

                    try {
                        val assetPath = if (effectId.startsWith("flutter_assets/")) effectId else "flutter_assets/$effectId"
                        val rawContent = context.assets.open(assetPath).bufferedReader().use { it.readText() }
                        return convertFlutterFragToGlslEs(rawContent)
                    } catch (_: Exception) {
                    }
                }

                val eff = effectId.lowercase()
                return when {
                    eff.contains("glitch") -> """
                        precision mediump float;
                        uniform sampler2D uTexSampler;
                        varying vec2 vTexCoords;
                        uniform vec2 uSize;
                        uniform float uTime;
                        uniform float uAmount;
                        uniform float uSpeed;

                        float hash(float n) { return fract(sin(n * 127.1) * 43758.5453); }
                        vec4 tex(vec2 p) { return texture2D(uTexSampler, clamp(p, vec2(0.0), vec2(1.0))); }

                        void main() {
                            vec2 uv = vTexCoords;
                            float t = floor(uTime * uSpeed * 8.0);
                            float band = floor(uv.y * 14.0);
                            float trig = step(1.0 - 0.35 * uAmount, hash(t * 1.7 + band * 0.31));
                            float shift = (hash(band + t) - 0.5) * 0.18 * uAmount * trig;
                            float split = 0.012 * uAmount * trig;
                            vec2 p = vec2(uv.x + shift, uv.y);
                            float r = tex(p + vec2(split, 0.0)).r;
                            vec4 g = tex(p);
                            float b = tex(p - vec2(split, 0.0)).b;
                            vec3 c = vec3(r, g.g, b);
                            c += 0.05 * uAmount * trig * hash(floor(uv.y * uSize.y * 0.5) + t);
                            gl_FragColor = vec4(c, g.a);
                        }
                    """.trimIndent()

                    eff.contains("chromatic") || eff.contains("split") || eff.contains("aberration") -> """
                        precision mediump float;
                        uniform sampler2D uTexSampler;
                        varying vec2 vTexCoords;
                        uniform float uAmount;

                        void main() {
                            vec2 uv = vTexCoords;
                            float offset = 0.02 * uAmount;
                            float r = texture2D(uTexSampler, uv + vec2(offset, 0.0)).r;
                            vec4 g = texture2D(uTexSampler, uv);
                            float b = texture2D(uTexSampler, uv - vec2(offset, 0.0)).b;
                            gl_FragColor = vec4(r, g.g, b, g.a);
                        }
                    """.trimIndent()

                    eff.contains("grain") -> """
                        precision mediump float;
                        uniform sampler2D uTexSampler;
                        varying vec2 vTexCoords;
                        uniform float uTime;
                        uniform float uAmount;

                        float rand(vec2 co) {
                            return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
                        }

                        void main() {
                            vec4 color = texture2D(uTexSampler, vTexCoords);
                            float noise = rand(vTexCoords + vec2(uTime * 0.1, uTime * 0.2)) - 0.5;
                            color.rgb += noise * 0.3 * uAmount;
                            gl_FragColor = color;
                        }
                    """.trimIndent()

                    eff.contains("wave") || eff.contains("liquid") -> """
                        precision mediump float;
                        uniform sampler2D uTexSampler;
                        varying vec2 vTexCoords;
                        uniform float uTime;
                        uniform float uAmount;
                        uniform float uSpeed;

                        void main() {
                            vec2 uv = vTexCoords;
                            uv.x += sin(uv.y * 10.0 + uTime * uSpeed * 3.0) * 0.02 * uAmount;
                            uv.y += cos(uv.x * 10.0 + uTime * uSpeed * 3.0) * 0.02 * uAmount;
                            gl_FragColor = texture2D(uTexSampler, clamp(uv, vec2(0.0), vec2(1.0)));
                        }
                    """.trimIndent()

                    eff.contains("pixelate") || eff.contains("mosaic") -> """
                        precision mediump float;
                        uniform sampler2D uTexSampler;
                        varying vec2 vTexCoords;
                        uniform float uAmount;

                        void main() {
                            float pixels = max(4.0, (1.0 - clamp(uAmount, 0.0, 0.99)) * 100.0);
                            vec2 uv = floor(vTexCoords * pixels) / pixels;
                            gl_FragColor = texture2D(uTexSampler, uv);
                        }
                    """.trimIndent()

                    eff.contains("vhs") -> """
                        precision mediump float;
                        uniform sampler2D uTexSampler;
                        varying vec2 vTexCoords;
                        uniform float uTime;
                        uniform float uAmount;

                        float hash(float n) { return fract(sin(n) * 43758.5453123); }

                        void main() {
                            vec2 uv = vTexCoords;
                            float scanline = sin(uv.y * 800.0 + uTime * 10.0) * 0.04 * uAmount;
                            uv.x += (hash(uv.y + uTime) - 0.5) * 0.01 * uAmount;
                            vec4 col = texture2D(uTexSampler, clamp(uv, vec2(0.0), vec2(1.0)));
                            col.rgb -= scanline;
                            gl_FragColor = col;
                        }
                    """.trimIndent()

                    eff.contains("leak") || eff.contains("fire") || eff.contains("flame") -> """
                        precision mediump float;
                        uniform sampler2D uTexSampler;
                        varying vec2 vTexCoords;
                        uniform float uTime;
                        uniform float uAmount;

                        void main() {
                            vec2 uv = vTexCoords;
                            vec4 col = texture2D(uTexSampler, uv);
                            float leak = sin(uv.x * 3.0 + uTime * 2.0) * cos(uv.y * 2.0 + uTime * 1.5) * 0.5 + 0.5;
                            col.rgb += vec3(1.0, 0.6, 0.2) * leak * 0.4 * uAmount;
                            gl_FragColor = col;
                        }
                    """.trimIndent()

                    eff.contains("convex") || eff.contains("lens") -> """
                        precision mediump float;
                        uniform sampler2D uTexSampler;
                        varying vec2 vTexCoords;
                        uniform float uAmount;

                        void main() {
                            vec2 uv = vTexCoords - vec2(0.5);
                            float r2 = uv.x * uv.x + uv.y * uv.y;
                            uv *= (1.0 + 0.5 * uAmount * r2);
                            uv += vec2(0.5);
                            if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
                                gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0);
                            } else {
                                gl_FragColor = texture2D(uTexSampler, uv);
                            }
                        }
                    """.trimIndent()

                    eff.contains("glow") || eff.contains("bloom") -> """
                        precision mediump float;
                        uniform sampler2D uTexSampler;
                        varying vec2 vTexCoords;
                        uniform float uAmount;

                        void main() {
                            vec2 uv = vTexCoords;
                            vec4 col = texture2D(uTexSampler, uv);
                            vec4 bloom = vec4(0.0);
                            float step = 0.005 * uAmount;
                            bloom += texture2D(uTexSampler, uv + vec2(-step, -step));
                            bloom += texture2D(uTexSampler, uv + vec2(step, -step));
                            bloom += texture2D(uTexSampler, uv + vec2(-step, step));
                            bloom += texture2D(uTexSampler, uv + vec2(step, step));
                            bloom *= 0.25;
                            gl_FragColor = col + bloom * 0.5 * uAmount;
                        }
                    """.trimIndent()

                    eff.contains("vignette") -> """
                        precision mediump float;
                        uniform sampler2D uTexSampler;
                        varying vec2 vTexCoords;
                        uniform float uAmount;

                        void main() {
                            vec2 uv = vTexCoords;
                            vec4 col = texture2D(uTexSampler, uv);
                            vec2 dist = uv - vec2(0.5);
                            float vig = 1.0 - smoothstep(0.3, 0.8, length(dist) * (1.0 + uAmount));
                            col.rgb *= vig;
                            gl_FragColor = col;
                        }
                    """.trimIndent()

                    eff.contains("cold") -> """
                        precision mediump float;
                        uniform sampler2D uTexSampler;
                        varying vec2 vTexCoords;
                        uniform float uAmount;

                        void main() {
                            vec4 col = texture2D(uTexSampler, vTexCoords);
                            col.r *= 0.7;
                            col.g *= 0.95;
                            col.b *= 1.3 * (1.0 + 0.2 * uAmount);
                            gl_FragColor = col;
                        }
                    """.trimIndent()

                    eff.contains("thermal") -> """
                        precision mediump float;
                        uniform sampler2D uTexSampler;
                        varying vec2 vTexCoords;

                        void main() {
                            vec4 col = texture2D(uTexSampler, vTexCoords);
                            float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
                            vec3 thermal = mix(vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), lum);
                            if (lum > 0.7) thermal = mix(vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), (lum - 0.7) / 0.3);
                            gl_FragColor = vec4(thermal, col.a);
                        }
                    """.trimIndent()

                    eff.contains("kaleidoscope") || eff.contains("prism") -> """
                        precision mediump float;
                        uniform sampler2D uTexSampler;
                        varying vec2 vTexCoords;
                        uniform float uAmount;

                        void main() {
                            vec2 uv = vTexCoords - 0.5;
                            float r = length(uv);
                            float a = atan(uv.y, uv.x);
                            float sides = max(3.0, floor(6.0 * uAmount));
                            float tau = 6.2831853;
                            a = mod(a, tau / sides);
                            a = abs(a - tau / (2.0 * sides));
                            uv = r * vec2(cos(a), sin(a)) + 0.5;
                            gl_FragColor = texture2D(uTexSampler, clamp(uv, vec2(0.0), vec2(1.0)));
                        }
                    """.trimIndent()

                    else -> """
                        precision mediump float;
                        uniform sampler2D uTexSampler;
                        varying vec2 vTexCoords;
                        uniform float uAmount;

                        void main() {
                            vec4 col = texture2D(uTexSampler, vTexCoords);
                            gl_FragColor = col;
                        }
                    """.trimIndent()
                }
            }
        }
    }
}
