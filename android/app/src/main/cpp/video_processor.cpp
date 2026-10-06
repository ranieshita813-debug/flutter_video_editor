#include <jni.h>
#include <cmath>
#include <algorithm>

extern "C" {

JNIEXPORT void JNICALL
Java_com_example_flutter_1video_1editor_export_ExportPlugin_nativeApplyColorGrading(
        JNIEnv *env,
        jobject thiz,
        jintArray pixels,
        jint width,
        jint height,
        jfloat brightness,
        jfloat contrast,
        jfloat saturation) {

    jint *pixelData = env->GetIntArrayElements(pixels, nullptr);
    if (!pixelData) return;

    int totalPixels = width * height;
    float alpha_contrast = contrast;

    for (int i = 0; i < totalPixels; ++i) {
        int color = pixelData[i];
        int a = (color >> 24) & 0xFF;
        int r = (color >> 16) & 0xFF;
        int g = (color >> 8) & 0xFF;
        int b = color & 0xFF;

        // Brightness adjustment [-1.0, 1.0]
        float rf = r + brightness * 255.0f;
        float gf = g + brightness * 255.0f;
        float bf = b + brightness * 255.0f;

        // Contrast adjustment [0.0, 2.0]
        rf = (rf - 128.0f) * alpha_contrast + 128.0f;
        gf = (gf - 128.0f) * alpha_contrast + 128.0f;
        bf = (bf - 128.0f) * alpha_contrast + 128.0f;

        // Saturation adjustment [0.0, 2.0]
        float gray = 0.299f * rf + 0.587f * gf + 0.114f * bf;
        rf = gray + (rf - gray) * saturation;
        gf = gray + (gf - gray) * saturation;
        bf = gray + (bf - gray) * saturation;

        // Clamp
        int finalR = std::min(255, std::max(0, static_cast<int>(rf)));
        int finalG = std::min(255, std::max(0, static_cast<int>(gf)));
        int finalB = std::min(255, std::max(0, static_cast<int>(bf)));

        pixelData[i] = (a << 24) | (finalR << 16) | (finalG << 8) | finalB;
    }

    env->ReleaseIntArrayElements(pixels, pixelData, 0);
}

JNIEXPORT void JNICALL
Java_com_example_flutter_1video_1editor_export_ExportPlugin_nativeApplyColorGradingExt(
        JNIEnv *env,
        jobject thiz,
        jintArray pixels,
        jint width,
        jint height,
        jfloat brightness,
        jfloat contrast,
        jfloat saturation,
        jfloat temperature,
        jfloat tint,
        jfloat exposure,
        jfloat vignette) {

    jint *pixelData = env->GetIntArrayElements(pixels, nullptr);
    if (!pixelData) return;

    int totalPixels = width * height;
    float centerX = width / 2.0f;
    float centerY = height / 2.0f;
    float maxDist = std::sqrt(centerX * centerX + centerY * centerY);

    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            int idx = y * width + x;
            int color = pixelData[idx];
            int a = (color >> 24) & 0xFF;
            int r = (color >> 16) & 0xFF;
            int g = (color >> 8) & 0xFF;
            int b = color & 0xFF;

            // Exposure [-1.0, 1.0]
            float expFactor = std::pow(2.0f, exposure);
            float rf = r * expFactor;
            float gf = g * expFactor;
            float bf = b * expFactor;

            // Brightness [-1.0, 1.0]
            rf += brightness * 255.0f;
            gf += brightness * 255.0f;
            bf += brightness * 255.0f;

            // Temperature / Tint
            rf += temperature * 30.0f;
            bf -= temperature * 30.0f;
            gf += tint * 30.0f;

            // Contrast [0.0, 2.0]
            rf = (rf - 128.0f) * contrast + 128.0f;
            gf = (gf - 128.0f) * contrast + 128.0f;
            bf = (bf - 128.0f) * contrast + 128.0f;

            // Saturation [0.0, 2.0]
            float gray = 0.299f * rf + 0.587f * gf + 0.114f * bf;
            rf = gray + (rf - gray) * saturation;
            gf = gray + (gf - gray) * saturation;
            bf = gray + (bf - gray) * saturation;

            // Vignette [0.0, 1.0]
            if (vignette > 0.0f) {
                float dx = x - centerX;
                float dy = y - centerY;
                float dist = std::sqrt(dx * dx + dy * dy) / maxDist;
                float vigFactor = 1.0f - (dist * vignette);
                vigFactor = std::max(0.0f, vigFactor);
                rf *= vigFactor;
                gf *= vigFactor;
                bf *= vigFactor;
            }

            int finalR = std::min(255, std::max(0, static_cast<int>(rf)));
            int finalG = std::min(255, std::max(0, static_cast<int>(gf)));
            int finalB = std::min(255, std::max(0, static_cast<int>(bf)));

            pixelData[idx] = (a << 24) | (finalR << 16) | (finalG << 8) | finalB;
        }
    }

    env->ReleaseIntArrayElements(pixels, pixelData, 0);
}

JNIEXPORT void JNICALL
Java_com_example_flutter_1video_1editor_export_ExportPlugin_nativeBlendOverlays(
        JNIEnv *env,
        jobject thiz,
        jintArray basePixels,
        jintArray overlayPixels,
        jint width,
        jint height) {

    jint *baseData = env->GetIntArrayElements(basePixels, nullptr);
    jint *overlayData = env->GetIntArrayElements(overlayPixels, nullptr);
    if (!baseData || !overlayData) return;

    int totalPixels = width * height;

    for (int i = 0; i < totalPixels; ++i) {
        int overColor = overlayData[i];
        int overA = (overColor >> 24) & 0xFF;
        if (overA == 0) continue;

        int overR = (overColor >> 16) & 0xFF;
        int overG = (overColor >> 8) & 0xFF;
        int overB = overColor & 0xFF;

        if (overA == 255) {
            baseData[i] = overColor;
            continue;
        }

        int baseColor = baseData[i];
        int baseA = (baseColor >> 24) & 0xFF;
        int baseR = (baseColor >> 16) & 0xFF;
        int baseG = (baseColor >> 8) & 0xFF;
        int baseB = baseColor & 0xFF;

        float alpha = overA / 255.0f;
        int outR = static_cast<int>(overR * alpha + baseR * (1.0f - alpha));
        int outG = static_cast<int>(overG * alpha + baseG * (1.0f - alpha));
        int outB = static_cast<int>(overB * alpha + baseB * (1.0f - alpha));

        baseData[i] = (baseA << 24) | (outR << 16) | (outG << 8) | outB;
    }

    env->ReleaseIntArrayElements(overlayPixels, overlayData, 0);
    env->ReleaseIntArrayElements(basePixels, baseData, 0);
}

JNIEXPORT jdoubleArray JNICALL
Java_com_example_flutter_1video_1editor_export_ExportPlugin_nativeExtractWaveform(
        JNIEnv *env,
        jobject thiz,
        jintArray frameBrightness,
        jint count) {

    jint *data = env->GetIntArrayElements(frameBrightness, nullptr);
    jdoubleArray result = env->NewDoubleArray(count);
    if (!data || !result) return nullptr;

    jdouble *outBuf = env->GetDoubleArrayElements(result, nullptr);

    for (int i = 0; i < count; ++i) {
        float val = static_cast<float>(data[i]) / 255.0f;
        outBuf[i] = std::min(1.0, std::max(0.1, static_cast<double>(std::abs(val - 0.5f) * 2.0f)));
    }

    env->ReleaseDoubleArrayElements(result, outBuf, 0);
    env->ReleaseIntArrayElements(frameBrightness, data, 0);

    return result;
}

} // extern "C"
