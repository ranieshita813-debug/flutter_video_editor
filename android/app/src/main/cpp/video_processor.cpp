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
