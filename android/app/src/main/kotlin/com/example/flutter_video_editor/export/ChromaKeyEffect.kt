package com.example.flutter_video_editor.export

import android.opengl.GLES20
import android.opengl.Matrix
import androidx.media3.effect.GlEffect
import androidx.media3.effect.GlMatrixTransformation
import androidx.media3.effect.TextureOverlay
import com.google.common.collect.ImmutableList
import kotlin.math.sqrt

/**
 * ক্রোমা কি (Green Screen/Blue Screen) ইফেক্ট।
 * 
 * এটি একটি কাস্টম GL শেডার ব্যবহার করে নির্দিষ্ট রঙকে স্বচ্ছ (transparent) করে দেয়।
 * 
 * প্যারামিটার:
 * - keyColor: যে রঙটি রিমুভ করতে চান (ডিফল্ট: সবুজ #00FF00)
 * - similarity: কতটা কাছের রঙ রিমুভ হবে (0.0-1.0, ডিফল্ট: 0.4)
 * - smoothness: এজ স্মুথনেস (0.0-1.0, ডিফল্ট: 0.1)
 * - spillSuppress: স্পিল সাপ্রেশন (0.0-1.0, ডিফল্ট: 0.5)
 */
class ChromaKeyEffect(
    private val keyColor: Int = 0x00FF00, // ডিফল্ট সবুজ
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
                
                // RGB চ্যানেল আলাদা করুন
                float r = tex_color.r;
                float g = tex_color.g;
                float b = tex_color.b;
                
                // কী কালার থেকে দূরত্ব গণনা (Euclidean distance)
                float dr = r - u_key_color.r;
                float dg = g - u_key_color.g;
                float db = b - u_key_color.b;
                float distance = sqrt(dr * dr + dg * dg + db * db);
                
                // সিমিলারিটি বেসড আলফা গণনা
                float alpha = smoothstep(u_similarity, u_similarity + u_smoothness, distance);
                
                // স্পিল সাপ্রেশন (সবুজ স্পিল কমানো)
                float max_rgb = max(r, max(g, b));
                float gray = (r + g + b) / 3.0;
                float spill_factor = max(0.0, g - max(r, b));
                
                float corrected_g = g - (spill_factor * u_spill_suppress);
                
                // ফাইনাল কালার
                vec3 final_color = vec3(r, corrected_g, b);
                
                v_color = vec4(final_color, alpha * tex_color.a);
            }
        """
    }

    override fun getGlShaderProgram(): androidx.media3.effect.GlShaderProgram {
        return androidx.media3.effect.GlShaderProgram(VERTEX_SHADER, FRAGMENT_SHADER)
    }

    override fun prepare(glState: androidx.media3.effect.GlState) {
        val program = glState.glShaderProgram
        program.use()

        // ইউনিফর্ম ভেরিয়েবল সেট করুন
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

    override fun release(glState: androidx.media3.effect.GlState) {
        // রিসোর্স ক্লিনআপ (যদি প্রয়োজন হয়)
    }
}