package com.motiongr.videoedit.export

import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaCodecList
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import androidx.media3.transformer.AudioEncoderSettings
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.MediaStore
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileNotFoundException
import java.io.FileOutputStream
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Native engine of the Flutter video editor.
 *
 * Channels
 *  - MethodChannel "editor/export"
 *  - EventChannel  "editor/export/progress"  -> {progress, stage, elapsedMs, etaMs}
 *
 * Methods
 *  probe, thumbnails, frameAt, waveform, applyColorGrading,
 *  capabilities, clearCache, export, cancel
 */
@UnstableApi
class ExportPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        @Volatile
        private var nativeLoaded = false

        private const val MIN_FREE_BYTES = 150L * 1024 * 1024
        private const val MAX_CACHE_BYTES = 200L * 1024 * 1024
        private const val PROGRESS_INTERVAL_MS = 200L

        init {
            nativeLoaded = try {
                System.loadLibrary("video_processor")
                true
            } catch (_: UnsatisfiedLinkError) {
                false // pure Kotlin fallback is used
            }
        }
    }

    private external fun nativeApplyColorGrading(
        pixels: IntArray,
        width: Int,
        height: Int,
        brightness: Float,
        contrast: Float,
        saturation: Float
    )

    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var context: Context? = null

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    @Volatile
    private var attached = false

    private val executor: ExecutorService = Executors.newFixedThreadPool(3)
    private val mainHandler = Handler(Looper.getMainLooper())

    /** One export at a time. Touched on the main thread only (except [claimed]). */
    private class ExportSession(
        val result: MethodChannel.Result,
        val tempFile: File,
        val finalName: String,
        val startedAt: Long = System.currentTimeMillis()
    ) {
        val claimed = AtomicBoolean(false)
        var transformer: Transformer? = null

        /** Returns true only for the first caller -> guarantees a single reply to Flutter. */
        fun claim() = claimed.compareAndSet(false, true)
    }

    private var session: ExportSession? = null

    // ------------------------------------------------------------------------------------------
    // Lifecycle
    // ------------------------------------------------------------------------------------------

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        attached = true
        context = binding.applicationContext
        // "Cancel" button in the notification
        ExportForegroundService.cancelHandler = { mainHandler.post { cancelExport() } }
        channel = MethodChannel(binding.binaryMessenger, "editor/export")
        channel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "editor/export/progress")
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        attached = false
        ExportForegroundService.cancelHandler = null
        context?.let { ExportForegroundService.stop(it) }
        session?.let { s ->
            if (s.claim()) {
                s.transformer?.cancel()
                s.tempFile.delete()
            }
        }
        session = null
        mainHandler.removeCallbacksAndMessages(null)
        executor.shutdownNow()
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
        context = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // ------------------------------------------------------------------------------------------
    // Method dispatch
    // ------------------------------------------------------------------------------------------

    private fun MethodCall.int(key: String, def: Int): Int =
        (argument<Any>(key) as? Number)?.toInt() ?: def

    private fun MethodCall.float(key: String, def: Float): Float =
        (argument<Any>(key) as? Number)?.toFloat() ?: def

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "probe" -> {
                val path = call.argument<String>("path") ?: return invalid(result, "Path missing")
                runAsync(result) { probeFile(path) }
            }

            "thumbnails" -> {
                val path = call.argument<String>("path") ?: return invalid(result, "Path missing")
                val count = call.int("count", 5).coerceIn(1, 500)
                val height = call.int("height", 120).coerceIn(16, 1080)
                runAsync(result) { generateThumbnails(path, count, height) }
            }

            "frameAt" -> {
                val path = call.argument<String>("path") ?: return invalid(result, "Path missing")
                val timeMs = (call.argument<Any>("timeMs") as? Number)?.toLong() ?: 0L
                val maxHeight = call.int("maxHeight", 720).coerceIn(16, 2160)
                val quality = call.int("quality", 85).coerceIn(10, 100)
                runAsync(result) { frameAt(path, timeMs, maxHeight, quality) }
            }

            "waveform" -> {
                val path = call.argument<String>("path") ?: return invalid(result, "Path missing")
                val buckets = call.int("buckets", 100).coerceIn(1, 20000)
                runAsync(result) { extractWaveform(path, buckets) }
            }

            "applyColorGrading" -> {
                val pixels = call.argument<IntArray>("pixels")
                val width = call.int("width", 0)
                val height = call.int("height", 0)
                if (pixels == null || width <= 0 || height <= 0 || pixels.size < width * height) {
                    return invalid(result, "Invalid pixel data")
                }
                val brightness = call.float("brightness", 0f)
                val contrast = call.float("contrast", 1f)
                val saturation = call.float("saturation", 1f)
                runAsync(result) {
                    gradePixels(pixels, width, height, brightness, contrast, saturation)
                    pixels
                }
            }

            "capabilities" -> runAsync(result) { capabilities() }

            "clearCache" -> runAsync(result) { clearCache() }

            "export" -> {
                val timelineMap = call.argument<Map<String, Any?>>("timeline")
                    ?: return invalid(result, "Timeline data missing")
                startExport(timelineMap, result)
            }

            "cancel" -> {
                cancelExport()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun invalid(result: MethodChannel.Result, msg: String) {
        result.error("INVALID_ARG", msg, null)
    }

    /** Runs [block] on the worker pool and replies on the main thread, never leaving Flutter hanging. */
    private fun runAsync(result: MethodChannel.Result, block: () -> Any?) {
        try {
            executor.execute {
                val outcome = try {
                    Result.success(block())
                } catch (e: Throwable) {
                    Result.failure(e)
                }
                mainHandler.post {
                    if (!attached) return@post
                    outcome.fold(
                        onSuccess = { result.success(it) },
                        onFailure = { e ->
                            val code = if (e is FileNotFoundException) "FILE_NOT_FOUND" else "OPERATION_FAILED"
                            result.error(code, e.message, null)
                        }
                    )
                }
            }
        } catch (e: Exception) {
            result.error("OPERATION_FAILED", e.message, null)
        }
    }

    // ------------------------------------------------------------------------------------------
    // Helpers: sources, cache
    // ------------------------------------------------------------------------------------------

    private fun isAssetPath(path: String): Boolean =
        path.startsWith("assets/") || path.startsWith("asset/") || path.startsWith("asset://") || path.startsWith("file:///android_asset/")

    private fun toAssetPath(path: String): String {
        var p = path.removePrefix("asset:///").removePrefix("asset://").removePrefix("file:///android_asset/")
        if (p.startsWith("/")) p = p.substring(1)
        if (!p.startsWith("flutter_assets/")) {
            p = "flutter_assets/$p"
        }
        return p
    }

    private fun isUri(path: String) = path.startsWith("content://") || path.startsWith("file://") || isAssetPath(path)

    private fun requireSource(path: String) {
        if (isAssetPath(path)) {
            val ctx = context ?: return
            val ap = toAssetPath(path)
            try {
                ctx.assets.open(ap).close()
                return
            } catch (_: Exception) {
                val rawP = path.removePrefix("asset:///").removePrefix("asset://").removePrefix("file:///android_asset/").removePrefix("/")
                try {
                    ctx.assets.open(rawP).close()
                    return
                } catch (_: Exception) {
                    throw FileNotFoundException("Asset not found: $path")
                }
            }
        }
        if (!isUri(path) && !File(path).let { it.exists() && it.isFile }) {
            throw FileNotFoundException("File not found: $path")
        }
    }

    private fun MediaMetadataRetriever.source(path: String) {
        requireSource(path)
        val ctx = context
        if (isAssetPath(path) && ctx != null) {
            val ap = toAssetPath(path)
            try {
                val afd = ctx.assets.openFd(ap)
                setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                afd.close()
                return
            } catch (_: Exception) {
                val rawP = path.removePrefix("asset:///").removePrefix("asset://").removePrefix("file:///android_asset/").removePrefix("/")
                val afd = ctx.assets.openFd(rawP)
                setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                afd.close()
                return
            }
        }
        if (isUri(path)) setDataSource(ctx, Uri.parse(path)) else setDataSource(path)
    }

    private fun MediaExtractor.source(path: String) {
        requireSource(path)
        val ctx = context!!
        if (isAssetPath(path)) {
            val ap = toAssetPath(path)
            try {
                val afd = ctx.assets.openFd(ap)
                setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                afd.close()
                return
            } catch (_: Exception) {
                val rawP = path.removePrefix("asset:///").removePrefix("asset://").removePrefix("file:///android_asset/").removePrefix("/")
                val afd = ctx.assets.openFd(rawP)
                setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                afd.close()
                return
            }
        }
        if (isUri(path)) setDataSource(ctx, Uri.parse(path), null) else setDataSource(path)
    }

    /** Stable cache key: path + size + modified time (invalidates when file changes, no hashCode collisions). */
    private fun cacheKey(path: String): String {
        val f = File(path)
        val raw = "$path|${if (f.exists()) f.length() else 0}|${if (f.exists()) f.lastModified() else 0}"
        val digest = MessageDigest.getInstance("SHA-1").digest(raw.toByteArray())
        return digest.take(8).joinToString("") { "%02x".format(it) }
    }

    private fun cacheRoot(name: String): File =
        File(context?.cacheDir ?: throw IllegalStateException("No context"), name).apply { mkdirs() }

    private fun trimCache() {
        val ctx = context ?: return
        val files = listOf("thumb_cache", "wave_cache")
            .flatMap { File(ctx.cacheDir, it).walkTopDown().filter { f -> f.isFile }.toList() }
        var total = files.sumOf { it.length() }
        if (total <= MAX_CACHE_BYTES) return
        for (f in files.sortedBy { it.lastModified() }) {
            total -= f.length()
            f.delete()
            if (total <= MAX_CACHE_BYTES * 0.7) break
        }
    }

    private fun clearCache(): Long {
        val ctx = context ?: return 0L
        var freed = 0L
        for (dir in listOf("thumb_cache", "wave_cache")) {
            val d = File(ctx.cacheDir, dir)
            freed += d.walkTopDown().filter { it.isFile }.sumOf { it.length() }
            d.deleteRecursively()
        }
        return freed
    }

    // ------------------------------------------------------------------------------------------
    // Probe (real values from the file)
    // ------------------------------------------------------------------------------------------

    private fun mimeToCodec(mime: String?): String = when (mime) {
        MimeTypes.VIDEO_H264 -> "h264"
        MimeTypes.VIDEO_H265 -> "hevc"
        MimeTypes.VIDEO_AV1 -> "av1"
        MimeTypes.VIDEO_VP9 -> "vp9"
        MimeTypes.VIDEO_VP8 -> "vp8"
        null -> "unknown"
        else -> mime.substringAfter('/')
    }

    private fun probeFile(path: String): Map<String, Any> {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.source(path)
            fun meta(key: Int) = retriever.extractMetadata(key)

            val durationMs = meta(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val width = meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            val height = meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            val rotation = meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            val hasAudio = meta(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes"
            val hasVideo = meta(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) == "yes"
            val bitrate = meta(MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toLongOrNull() ?: 0L
            var fps = 0.0
            if (Build.VERSION.SDK_INT >= 23) {
                fps = meta(MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE)?.toDoubleOrNull() ?: 0.0
            }

            var videoMime: String? = null
            var isHdr = false
            var audioSampleRate = 0
            var audioChannels = 0
            val extractor = MediaExtractor()
            try {
                extractor.source(path)
                for (i in 0 until extractor.trackCount) {
                    val f = extractor.getTrackFormat(i)
                    val mime = f.getString(MediaFormat.KEY_MIME) ?: continue
                    if (mime.startsWith("video/") && videoMime == null) {
                        videoMime = mime
                        if (f.containsKey(MediaFormat.KEY_FRAME_RATE)) {
                            fps = try {
                                f.getInteger(MediaFormat.KEY_FRAME_RATE).toDouble()
                            } catch (_: Exception) {
                                f.getFloat(MediaFormat.KEY_FRAME_RATE).toDouble()
                            }
                        }
                        if (Build.VERSION.SDK_INT >= 24 && f.containsKey(MediaFormat.KEY_COLOR_TRANSFER)) {
                            val t = f.getInteger(MediaFormat.KEY_COLOR_TRANSFER)
                            isHdr = t == MediaFormat.COLOR_TRANSFER_ST2084 || t == MediaFormat.COLOR_TRANSFER_HLG
                        }
                    } else if (mime.startsWith("audio/") && audioSampleRate == 0) {
                        if (f.containsKey(MediaFormat.KEY_SAMPLE_RATE)) audioSampleRate = f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        if (f.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) audioChannels = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    }
                }
            } finally {
                try { extractor.release() } catch (_: Exception) {}
            }

            val swap = rotation == 90 || rotation == 270
            return mapOf(
                "durationMs" to durationMs,
                "width" to width,
                "height" to height,
                "displayWidth" to if (swap) height else width,
                "displayHeight" to if (swap) width else height,
                "fps" to (if (fps > 0) fps else 30.0),
                "fpsEstimated" to (fps <= 0),
                "codec" to mimeToCodec(videoMime),
                "rotation" to rotation,
                "hasAudio" to hasAudio,
                "hasVideo" to hasVideo,
                "bitrate" to bitrate,
                "isHdr" to isHdr,
                "audioSampleRate" to audioSampleRate,
                "audioChannels" to audioChannels,
                "fileSize" to (if (isUri(path)) 0L else File(path).length())
            )
        } finally {
            try { retriever.release() } catch (_: Exception) {}
        }
    }

    // ------------------------------------------------------------------------------------------
    // Thumbnails / single frame
    // ------------------------------------------------------------------------------------------

    private fun generateThumbnails(path: String, count: Int, height: Int): List<String> {
        val dir = File(cacheRoot("thumb_cache"), "${cacheKey(path)}_${count}x$height").apply { mkdirs() }

        fun cached(): List<File> =
            dir.listFiles { f -> f.extension == "jpg" }?.sortedBy { it.name } ?: emptyList()

        cached().let { if (it.size == count) return it.map { f -> f.absolutePath } }

        val retriever = MediaMetadataRetriever()
        val out = ArrayList<String>(count)
        try {
            retriever.source(path)
            val durationUs = (retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L) * 1000L
            val w = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 16
            val h = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 9
            val rot = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            val (dw, dh) = if (rot == 90 || rot == 270) h to w else w to h
            val th = height
            val tw = max(16, (th.toFloat() * dw / max(dh, 1)).roundToInt())
            val stepUs = durationUs / count

            for (i in 0 until count) {
                val timeUs = ((i + 0.5) * stepUs).toLong().coerceIn(0L, max(durationUs - 1, 0L))
                val scaled = scaledFrame(retriever, timeUs, tw, th) ?: continue
                val file = File(dir, "frame_%03d.jpg".format(i))
                try {
                    FileOutputStream(file).use { scaled.compress(Bitmap.CompressFormat.JPEG, 80, it) }
                    out.add(file.absolutePath)
                } finally {
                    scaled.recycle()
                }
            }
        } finally {
            try { retriever.release() } catch (_: Exception) {}
        }
        trimCache()
        return out
    }

    private fun scaledFrame(r: MediaMetadataRetriever, timeUs: Long, tw: Int, th: Int): Bitmap? {
        val option = MediaMetadataRetriever.OPTION_CLOSEST_SYNC
        return if (Build.VERSION.SDK_INT >= 27) {
            r.getScaledFrameAtTime(timeUs, option, tw, th)
        } else {
            val frame = r.getFrameAtTime(timeUs, option) ?: return null
            val scaled = Bitmap.createScaledBitmap(frame, tw, th, true)
            if (scaled !== frame) frame.recycle()
            scaled
        }
    }

    /** Exact (non-keyframe) frame as JPEG bytes, for scrubbing / preview. */
    private fun frameAt(path: String, timeMs: Long, maxHeight: Int, quality: Int): ByteArray? {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.source(path)
            val frame = retriever.getFrameAtTime(timeMs * 1000L, MediaMetadataRetriever.OPTION_CLOSEST)
                ?: return null
            val bmp = if (frame.height > maxHeight) {
                val w = (frame.width.toFloat() * maxHeight / frame.height).roundToInt()
                Bitmap.createScaledBitmap(frame, max(w, 16), maxHeight, true).also { frame.recycle() }
            } else frame
            return try {
                ByteArrayOutputStream().use { bos ->
                    bmp.compress(Bitmap.CompressFormat.JPEG, quality, bos)
                    bos.toByteArray()
                }
            } finally {
                bmp.recycle()
            }
        } finally {
            try { retriever.release() } catch (_: Exception) {}
        }
    }

    // ------------------------------------------------------------------------------------------
    // Real audio waveform (decodes the audio track to PCM)
    // ------------------------------------------------------------------------------------------

    private fun extractWaveform(path: String, buckets: Int): List<Double> {
        val cacheFile = File(cacheRoot("wave_cache"), "${cacheKey(path)}_$buckets.csv")
        if (cacheFile.exists()) {
            val cached = cacheFile.readText().split(",").mapNotNull { it.toDoubleOrNull() }
            if (cached.size == buckets) return cached
        }
        val peaks = decodePeaks(path, buckets)
        cacheFile.writeText(peaks.joinToString(","))
        trimCache()
        return peaks
    }

    private fun decodePeaks(path: String, buckets: Int): List<Double> {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.source(path)
            var track = -1
            var format: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val f = extractor.getTrackFormat(i)
                if (f.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) {
                    track = i; format = f; break
                }
            }
            if (track < 0 || format == null) return List(buckets) { 0.0 } // no audio

            extractor.selectTrack(track)
            val mime = format.getString(MediaFormat.KEY_MIME)!!
            var durationUs = if (format.containsKey(MediaFormat.KEY_DURATION)) format.getLong(MediaFormat.KEY_DURATION) else 0L
            if (durationUs <= 0) {
                val r = MediaMetadataRetriever()
                try {
                    r.source(path)
                    durationUs = (r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L) * 1000L
                } finally { try { r.release() } catch (_: Exception) {} }
            }
            if (durationUs <= 0) return List(buckets) { 0.0 }

            var sampleRate = if (format.containsKey(MediaFormat.KEY_SAMPLE_RATE)) format.getInteger(MediaFormat.KEY_SAMPLE_RATE) else 44100
            var channels = if (format.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) format.getInteger(MediaFormat.KEY_CHANNEL_COUNT) else 2
            var isFloat = false

            codec = MediaCodec.createDecoderByType(mime)
            codec.configure(format, null, null, 0)
            codec.start()

            val peaks = DoubleArray(buckets)
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var idleLoops = 0

            while (!outputDone && idleLoops < 500) {
                if (!inputDone) {
                    val inIdx = codec.dequeueInputBuffer(10_000)
                    if (inIdx >= 0) {
                        val buf = codec.getInputBuffer(inIdx)!!
                        val size = extractor.readSampleData(buf, 0)
                        if (size < 0) {
                            codec.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(inIdx, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                val outIdx = codec.dequeueOutputBuffer(info, 10_000)
                when {
                    outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val of = codec.outputFormat
                        if (of.containsKey(MediaFormat.KEY_SAMPLE_RATE)) sampleRate = of.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        if (of.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) channels = of.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        isFloat = of.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                            of.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
                    }

                    outIdx >= 0 -> {
                        idleLoops = 0
                        val buf = codec.getOutputBuffer(outIdx)
                        if (buf != null && info.size > 0) {
                            buf.position(info.offset)
                            buf.limit(info.offset + info.size)
                            buf.order(ByteOrder.nativeOrder())
                            val ch = max(channels, 1)
                            if (isFloat) {
                                val fb = buf.asFloatBuffer()
                                accumulate(peaks, fb.remaining() / ch, ch, info.presentationTimeUs, sampleRate, durationUs) { idx -> abs(fb.get(idx)).toDouble() }
                            } else {
                                val sb = buf.asShortBuffer()
                                accumulate(peaks, sb.remaining() / ch, ch, info.presentationTimeUs, sampleRate, durationUs) { idx -> abs(sb.get(idx).toInt()) / 32768.0 }
                            }
                        }
                        codec.releaseOutputBuffer(outIdx, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                    }

                    else -> idleLoops++
                }
            }

            val maxPeak = peaks.maxOrNull() ?: 0.0
            return if (maxPeak > 0.0) peaks.map { (it / maxPeak).coerceIn(0.0, 1.0) } else peaks.toList()
        } finally {
            try { codec?.stop() } catch (_: Exception) {}
            try { codec?.release() } catch (_: Exception) {}
            try { extractor.release() } catch (_: Exception) {}
        }
    }

    private inline fun accumulate(
        peaks: DoubleArray,
        frames: Int,
        channels: Int,
        ptsUs: Long,
        sampleRate: Int,
        durationUs: Long,
        sample: (Int) -> Double
    ) {
        val buckets = peaks.size
        val sr = max(sampleRate, 1)
        for (f in 0 until frames) {
            val t = ptsUs + f * 1_000_000L / sr
            val b = (t * buckets / durationUs).toInt().coerceIn(0, buckets - 1)
            var m = 0.0
            val base = f * channels
            for (c in 0 until channels) m = max(m, sample(base + c))
            if (m > peaks[b]) peaks[b] = m
        }
    }

    // ------------------------------------------------------------------------------------------
    // Color grading (native with safe Kotlin fallback)
    // ------------------------------------------------------------------------------------------

    private fun gradePixels(p: IntArray, w: Int, h: Int, brightness: Float, contrast: Float, saturation: Float) {
        if (nativeLoaded) {
            try {
                nativeApplyColorGrading(p, w, h, brightness, contrast, saturation)
                return
            } catch (_: UnsatisfiedLinkError) {
                nativeLoaded = false
            }
        }
        // brightness: -1..1 offset, contrast/saturation: 1.0 = unchanged
        val offset = brightness * 255f
        for (i in 0 until min(p.size, w * h)) {
            val px = p[i]
            val a = px ushr 24
            var r = ((px shr 16) and 0xFF).toFloat()
            var g = ((px shr 8) and 0xFF).toFloat()
            var b = (px and 0xFF).toFloat()
            val lum = 0.299f * r + 0.587f * g + 0.114f * b
            r = lum + (r - lum) * saturation
            g = lum + (g - lum) * saturation
            b = lum + (b - lum) * saturation
            r = (r - 128f) * contrast + 128f + offset
            g = (g - 128f) * contrast + 128f + offset
            b = (b - 128f) * contrast + 128f + offset
            p[i] = (a shl 24) or
                (r.roundToInt().coerceIn(0, 255) shl 16) or
                (g.roundToInt().coerceIn(0, 255) shl 8) or
                b.roundToInt().coerceIn(0, 255)
        }
    }

    // ------------------------------------------------------------------------------------------
    // Device capabilities
    // ------------------------------------------------------------------------------------------

    private fun capabilities(): Map<String, Any> {
        fun encoderInfo(mime: String): Map<String, Any> {
            val list = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
                .filter { it.isEncoder && it.supportedTypes.any { t -> t.equals(mime, true) } }
            var maxW = 0
            var maxH = 0
            var hw = false
            for (c in list) {
                val v = c.getCapabilitiesForType(mime).videoCapabilities ?: continue
                maxW = max(maxW, v.supportedWidths.upper)
                maxH = max(maxH, v.supportedHeights.upper)
                if (Build.VERSION.SDK_INT >= 29 && c.isHardwareAccelerated) hw = true
            }
            return mapOf(
                "supported" to list.isNotEmpty(),
                "hardware" to hw,
                "maxWidth" to maxW,
                "maxHeight" to maxH
            )
        }
        return mapOf(
            "sdk" to Build.VERSION.SDK_INT,
            "h264" to encoderInfo(MimeTypes.VIDEO_H264),
            "hevc" to encoderInfo(MimeTypes.VIDEO_H265),
            "nativeProcessor" to nativeLoaded
        )
    }

    // ------------------------------------------------------------------------------------------
    // Export
    // ------------------------------------------------------------------------------------------

    private fun startExport(timelineMap: Map<String, Any?>, result: MethodChannel.Result) {
        val ctx = context ?: return result.error("NO_CONTEXT", "Application context not available", null)

        if (session != null) {
            return result.error("BUSY", "Another export is already running", null)
        }

        var tempFile: File? = null
        try {
            val timeline = TimelineParser.parse(timelineMap)

            // Private work dir: always writable, no storage permission needed.
            val workDir = File(
                ctx.getExternalFilesDir(Environment.DIRECTORY_MOVIES) ?: ctx.filesDir, "exports"
            ).apply { mkdirs() }

            if (StatFs(workDir.path).availableBytes < MIN_FREE_BYTES) {
                return result.error("NO_SPACE", "Not enough free storage to export", null)
            }

            val stamp = System.currentTimeMillis()
            // Media3 Transformer always muxes MP4, so the container is fixed to .mp4
            val temp = File(workDir, "export_temp_$stamp.mp4").also { tempFile = it }
            val s = ExportSession(result, temp, "MotionGr_$stamp.mp4")

            val composition = CompositionBuilder.buildComposition(ctx, timeline)

            val mimeType = if (timeline.settings.codec == "hevc") MimeTypes.VIDEO_H265 else MimeTypes.VIDEO_H264

            val settingsMap = timelineMap["settings"] as? Map<*, *>
            val bitrate = (settingsMap?.get("bitrate") as? Number)?.toInt() ?: 0

            val encoderFactory = DefaultEncoderFactory.Builder(ctx).setRequestedVideoEncoderSettings(VideoEncoderSettings.Builder().setBitrate(timeline.settings.bitrateKbps * 1000).build()).setRequestedAudioEncoderSettings(AudioEncoderSettings.Builder().setBitrate(timeline.settings.audioBitrateKbps * 1000).build()).setEnableFallback(true).build()

            val listener = object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    if (!s.claim()) return
                    emitProgress(0.99, "Saving video", s)
                    executor.execute {
                        val outcome = try {
                            Result.success(publishFile(ctx, s.tempFile, s.finalName))
                        } catch (e: Throwable) {
                            Result.failure(e)
                        }
                        mainHandler.post {
                            if (session === s) session = null
                            if (!attached) return@post
                            outcome.fold(
                                onSuccess = {
                                    emitProgress(1.0, "Export complete", s)
                                    ExportForegroundService.finish(ctx, true, "Video saved successfully")
                                    s.result.success(it)
                                },
                                onFailure = { e ->
                                    s.tempFile.delete()
                                    ExportForegroundService.finish(ctx, false, e.message ?: "Could not save video")
                                    s.result.error("SAVE_ERROR", e.message, null)
                                }
                            )
                        }
                    }
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException
                ) {
                    if (!s.claim()) return
                    s.tempFile.delete()
                    if (session === s) session = null
                    ExportForegroundService.finish(ctx, false, exportException.message ?: "Export failed")
                    s.result.error(
                        "EXPORT_ERROR",
                        exportException.message,
                        mapOf("errorCode" to exportException.errorCodeName)
                    )
                }
            }

            val transformer = Transformer.Builder(ctx)
                .setVideoMimeType(mimeType)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .setEncoderFactory(encoderFactory)
                .addListener(listener)
                .build()

            s.transformer = transformer
            session = s
            ExportForegroundService.start(ctx)
            transformer.start(composition, temp.absolutePath)
            emitProgress(0.0, "Starting export", s)
            mainHandler.postDelayed(ProgressPoller(s, transformer), PROGRESS_INTERVAL_MS)
        } catch (e: Exception) {
            tempFile?.delete()
            session = null
            ExportForegroundService.stop(ctx)
            result.error("EXPORT_FAILED", e.message, null)
        }
    }

    private inner class ProgressPoller(
        private val s: ExportSession,
        private val transformer: Transformer
    ) : Runnable {
        private val holder = ProgressHolder()
        private var last = -1

        override fun run() {
            // Stops automatically when finished / cancelled / replaced -> no leaked loop.
            if (session !== s || s.claimed.get()) return
            if (transformer.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE &&
                holder.progress != last
            ) {
                last = holder.progress
                context?.let { ExportForegroundService.progress(it, holder.progress, "Rendering frames") }
                emitProgress(
                    (holder.progress / 100.0).coerceIn(0.0, 0.98),
                    "Rendering frames (${holder.progress}%)",
                    s
                )
            }
            mainHandler.postDelayed(this, PROGRESS_INTERVAL_MS)
        }
    }

    /** Moves the finished file to the public gallery (MediaStore) and returns the best path to give Flutter. */
    private fun publishFile(ctx: Context, src: File, displayName: String): String {
        if (!src.exists() || src.length() == 0L) throw IllegalStateException("Rendered file is empty")
        val privateFinal = File(src.parentFile, displayName)

        try {
            if (Build.VERSION.SDK_INT >= 29) {
                val values = ContentValues().apply {
                    put(MediaStore.Video.Media.DISPLAY_NAME, displayName)
                    put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                    put(MediaStore.Video.Media.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/MotionGr")
                    put(MediaStore.Video.Media.IS_PENDING, 1)
                }
                val resolver = ctx.contentResolver
                val uri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
                    ?: throw IllegalStateException("MediaStore insert failed")
                try {
                    resolver.openOutputStream(uri)?.use { os -> src.inputStream().use { it.copyTo(os) } }
                        ?: throw IllegalStateException("Cannot open output stream")
                    resolver.update(uri, ContentValues().apply { put(MediaStore.Video.Media.IS_PENDING, 0) }, null, null)
                } catch (e: Exception) {
                    resolver.delete(uri, null, null)
                    throw e
                }
                var path: String? = null
                resolver.query(uri, arrayOf(MediaStore.Video.Media.DATA), null, null, null)?.use { c ->
                    if (c.moveToFirst()) path = c.getString(0)
                }
                src.delete()
                return path ?: uri.toString()
            } else {
                val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES), "MotionGr")
                if (!dir.exists() && !dir.mkdirs()) throw IllegalStateException("Cannot create public dir")
                val dest = File(dir, displayName)
                src.copyTo(dest, overwrite = true)
                MediaScannerConnection.scanFile(ctx, arrayOf(dest.absolutePath), arrayOf("video/mp4"), null)
                src.delete()
                return dest.absolutePath
            }
        } catch (_: Exception) {
            // Gallery not available (permission denied etc.) -> keep the file in app storage.
            if (src.renameTo(privateFinal)) return privateFinal.absolutePath
            return src.absolutePath
        }
    }

    private fun cancelExport() {
        val s = session ?: return
        if (!s.claim()) return // already finishing, nothing to cancel
        try { s.transformer?.cancel() } catch (_: Exception) {}
        s.tempFile.delete()
        session = null
        context?.let { ExportForegroundService.stop(it) }
        emitProgress(0.0, "Cancelled", s)
        // Transformer.cancel() does not fire a listener callback -> reply here so Dart never hangs.
        s.result.error("CANCELLED", "Export cancelled", null)
    }

    private fun emitProgress(progress: Double, stage: String, s: ExportSession? = session) {
        val elapsed = s?.let { System.currentTimeMillis() - it.startedAt } ?: 0L
        val eta = if (progress > 0.02 && progress < 1.0) (elapsed / progress * (1.0 - progress)).toLong() else -1L
        eventSink?.success(
            mapOf(
                "progress" to progress,
                "stage" to stage,
                "elapsedMs" to elapsed,
                "etaMs" to eta
            )
        )
    }
}