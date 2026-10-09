package com.example.flutter_video_editor.export

import android.content.Context
import androidx.media3.effect.GlEffect
import androidx.media3.effect.GlShaderProgram
import androidx.media3.effect.GlState

class ChromaKeyEffect(
    private val keyColor: Int = 0x00FF00,
    private val similarity: Float = 0.4f,
    private val smoothness: Float = 0.1f,
    private val spillSuppress: Float = 0.5f
) : GlEffect {

    companion object {
        private const val VERTEX_SHADER = """
            #version 300 es
            in vec4 a_position;
            in vec2 a_texture_coordinates;
            out vec2 v_texture_coordinates;

            void main() {
                gl_Position = a_position;
                v_texture_coordinates = a_texture_coordinates;
            }
        """

        private const val FRAGMENT_SHADER = """
            #version 300 es
            precision highp float;

            uniform sampler2D u_texture;
            uniform vec3 u_key_color;
            uniform float u_similarity;
            uniform float u_smoothness;
            uniform float u_spill_suppress;

            in vec2 v_texture_coordinates;
            out vec4 v_color;

            void main() {
                vec4 tex_color = texture(u_texture, v_texture_coordinates);
                float r = tex_color.r;
                float g = tex_color.g;
                float b = tex_color.b;

                float dr = r - u_key_color.r;
                float dg = g - u_key_color.g;
                float db = b - u_key_color.b;
                float distance = sqrt(dr * dr + dg * dg + db * db);

                float alpha = smoothstep(u_similarity, u_similarity + u_smoothness, distance);

                float max_rgb = max(r, max(g, b));
                float gray = (r + g + b) / 3.0;
                float spill_factor = max(0.0, g - max(r, b));
                float corrected_g = g - (spill_factor * u_spill_suppress);

                vec3 final_color = vec3(r, corrected_g, b);
                v_color = vec4(final_color, alpha * tex_color.a);
            }
        """
    }

    override fun toGlShaderProgram(context: Context, useHdr: Boolean): GlShaderProgram {
        return GlShaderProgram(VERTEX_SHADER, FRAGMENT_SHADER)
    }

    override fun prepare(glState: GlState) {
        val program = glState.glShaderProgram
        program.use()

        val keyColorNormalized = floatArrayOf(
            ((keyColor shr 16) and 0xFF) / 255.0f,
            ((keyColor shr 8) and 0xFF) / 255.0f,
            (keyColor and 0xFF) / 255.0f
        )

        program.setFloat3("u_key_color", keyColorNormalized[0], keyColorNormalized[1], keyColorNormalized[2])
        program.setFloat("u_similarity", similarity.coerceIn(0.0f, 1.0f))
        program.setFloat("u_smoothness", smoothness.coerceIn(0.0f, 1.0f))
        program.setFloat("u_spill_suppress", spillSuppress.coerceIn(0.0f, 1.0f))
    }

    override fun release(glState: GlState) {
        // Resource cleanup if needed
    }
}
