package com.motiongr.videoedit.export

import androidx.media3.effect.GlMatrixTransformation
import kotlin.math.pow

/**
 * কাস্টম কালার গ্রেডিং ইফেক্ট GL শেডার ম্যাট্রিক্স ব্যবহার করে।
 * 
 * প্যারামিটার রেঞ্জ:
 * - brightness: -1.0 (অন্ধকার) থেকে 1.0 (উজ্জ্বল), 0 = নিউট্রাল
 * - contrast: 0.0 (কম) থেকে 2.0 (বেশি), 1.0 = নিউট্রাল
 * - saturation: 0.0 (গ্রিস্কেল) থেকে 2.0 (অতিসম্পৃক্ত), 1.0 = নিউট্রাল
 * - temperature: -1.0 (ঠান্ডা/নীল) থেকে 1.0 (গরম/লাল), 0 = নিউট্রাল
 * - exposure: -1.0 (অন্ধকার) থেকে 1.0 (উজ্জ্বল), 0 = নিউট্রাল (EV স্টপ)
 */
class ColorGradingEffect(
    private val brightness: Float = 0f,
    private val contrast: Float = 1f,
    private val saturation: Float = 1f,
    private val temperature: Float = 0f,
    private val exposure: Float = 0f
) : GlMatrixTransformation {

    override fun getGlMatrixArray(presentationTimeUs: Long): FloatArray {
        // 4x4 কলাম-মেজর অর্ডার ম্যাট্রিক্স (OpenGL ES ফরম্যাট)
        val matrix = FloatArray(16)
        
        // এক্সপোজার থেকে গেইন গণনা (EV স্টপ)
        val gain = 2.0.pow(exposure.toDouble()).toFloat()
        
        // তাপমাত্রা এবং টিন্ট থেকে RGB স্কেল ফ্যাক্টর
        // temperature: -1 (নীল) থেকে 1 (লাল)
        // positive temperature = লাল বাড়ায়, নীল কমায়
        // negative temperature = নীল বাড়ায়, লাল কমায়
        val redScale = (gain * (1.0f + 0.25f * temperature)).coerceAtLeast(0.0f)
        val greenScale = gain
        val blueScale = (gain * (1.0f - 0.25f * temperature)).coerceAtLeast(0.0f)
        
        // কনট্রাস্ট ফ্যাক্টর
        val contrastFactor = contrast.coerceIn(0.0f, 2.0f)
        
        // ব্রাইটনেস অফসেট (-1 থেকে 1)
        val brightnessOffset = brightness.coerceIn(-1.0f, 1.0f)
        
        // স্যাচুরেশন ফ্যাক্টর
        val saturationFactor = saturation.coerceIn(0.0f, 2.0f)
        
        // স্যাচুরেশন ম্যাট্রিক্স (লুমিন্যান্স-বেসড)
        // RGB থেকে লুমিন্যান্সে কনভার্ট করার ওয়েট
        val lumR = 0.2126f
        val lumG = 0.7152f
        val lumB = 0.0722f
        
        // স্যাচুরেশন ম্যাট্রিক্স উপাদান
        val sr = (1.0f - saturationFactor) * lumR + saturationFactor
        val sg = (1.0f - saturationFactor) * lumG
        val sb = (1.0f - saturationFactor) * lumB
        val srg = (1.0f - saturationFactor) * lumR
        val sgg = (1.0f - saturationFactor) * lumG + saturationFactor
        val sbg = (1.0f - saturationFactor) * lumB
        val srb = (1.0f - saturationFactor) * lumR
        val sgb = (1.0f - saturationFactor) * lumG
        val sbb = (1.0f - saturationFactor) * lumB + saturationFactor
        
        // চূড়ান্ত ম্যাট্রিক্স তৈরি (কলাম-মেজর অর্ডার)
        // প্রতিটি RGB চ্যানেলে স্কেল এবং অফসেট প্রয়োগ
        matrix[0] = sr * redScale * contrastFactor      // R -> R
        matrix[1] = srg * redScale * contrastFactor     // R -> G
        matrix[2] = srb * redScale * contrastFactor     // R -> B
        matrix[3] = 0.0f                                // R -> A
        
        matrix[4] = sg * greenScale * contrastFactor    // G -> R
        matrix[5] = sgg * greenScale * contrastFactor   // G -> G
        matrix[6] = sgb * greenScale * contrastFactor   // G -> B
        matrix[7] = 0.0f                                // G -> A
        
        matrix[8] = sb * blueScale * contrastFactor     // B -> R
        matrix[9] = sbg * blueScale * contrastFactor    // B -> G
        matrix[10] = sbb * blueScale * contrastFactor   // B -> B
        matrix[11] = 0.0f                               // B -> A
        
        // ব্রাইটনেস অফসেট (RGB চ্যানেলে যোগ হয়)
        matrix[12] = brightnessOffset                   // অফসেট R
        matrix[13] = brightnessOffset                   // অফসেট G
        matrix[14] = brightnessOffset                   // অফসেট B
        matrix[15] = 1.0f                               // অফসেট A (ওয়াই)

        return matrix
    }
}