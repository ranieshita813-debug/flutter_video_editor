import 'dart:convert';
import 'dart:io';
import 'package:flutter_video_editor/core/logger/app_logger.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';

class WhisperService {
  WhisperService({
    String? apiKey,
    String? baseUrl,
  })  : apiKey = apiKey ?? _defaultApiKey,
        baseUrl = baseUrl ?? _defaultBaseUrl;

  static const String _defaultApiKey = 'sk_c8cOfMfccvx0X1t9P6Iosh4AIcYYt1xq';
  static const String _defaultBaseUrl = 'https://gen.pollinations.ai/v1';

  final String apiKey;
  final String baseUrl;

  /// Transcribes audio file at [audioFilePath] using OpenAI Whisper Large (v3) via Pollinations API.
  Future<List<CaptionCue>> transcribeAudio({
    required String audioFilePath,
    String model = 'whisper-large-v3',
    String? language,
  }) async {
    final file = File(audioFilePath);
    final bool fileExists = await file.exists();

    if (!fileExists) {
      AppLogger.warning('[WhisperService] File does not exist at $audioFilePath. Falling back to generated cues.');
      return _generateFallbackCues(audioFilePath);
    }

    try {
      final uri = Uri.parse('$baseUrl/audio/transcriptions');
      final request = HttpClient();
      final req = await request.postUrl(uri);

      final boundary = '----WhisperBoundary${DateTime.now().millisecondsSinceEpoch}';
      req.headers.set(HttpHeaders.contentTypeHeader, 'multipart/form-data; boundary=$boundary');
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');

      final bodyBytes = <int>[];

      void addField(String name, String value) {
        bodyBytes.addAll(utf8.encode('--$boundary\r\n'));
        bodyBytes.addAll(utf8.encode('Content-Disposition: form-data; name="$name"\r\n\r\n'));
        bodyBytes.addAll(utf8.encode('$value\r\n'));
      }

      addField('model', model);
      addField('response_format', 'verbose_json');
      addField('timestamp_granularities[]', 'segment');
      addField('timestamp_granularities[]', 'word');
      if (language != null && language.isNotEmpty) {
        addField('language', language);
      }

      // Add audio file
      final fileName = audioFilePath.split(Platform.pathSeparator).last;
      bodyBytes.addAll(utf8.encode('--$boundary\r\n'));
      bodyBytes.addAll(utf8.encode('Content-Disposition: form-data; name="file"; filename="$fileName"\r\n'));
      bodyBytes.addAll(utf8.encode('Content-Type: audio/wav\r\n\r\n'));

      final fileBytes = await file.readAsBytes();
      bodyBytes.addAll(fileBytes);
      bodyBytes.addAll(utf8.encode('\r\n'));
      bodyBytes.addAll(utf8.encode('--$boundary--\r\n'));

      req.contentLength = bodyBytes.length;
      req.add(bodyBytes);

      final resp = await req.close();
      final responseBody = await resp.transform(utf8.decoder).join();

      if (resp.statusCode == 200) {
        final Map<String, dynamic> json = jsonDecode(responseBody) as Map<String, dynamic>;
        return parseWhisperVerboseJson(json);
      } else {
        AppLogger.error('[WhisperService] API error (${resp.statusCode}): $responseBody');
        return _generateFallbackCues(audioFilePath);
      }
    } catch (e, st) {
      AppLogger.error('[WhisperService] Exception transcribing audio', error: e, stackTrace: st);
      return _generateFallbackCues(audioFilePath);
    }
  }

  /// Parses OpenAI Whisper verbose_json structure into a list of [CaptionCue]s with word timings.
  static List<CaptionCue> parseWhisperVerboseJson(Map<String, dynamic> json) {
    final List<CaptionCue> cues = <CaptionCue>[];

    final rawSegments = json['segments'] as List<dynamic>?;
    final rawWords = json['words'] as List<dynamic>?;

    final List<CaptionWord> allWords = <CaptionWord>[];
    if (rawWords != null) {
      for (final w in rawWords) {
        if (w is Map) {
          final wordStr = (w['word'] as String? ?? '').trim();
          final startSec = (w['start'] as num?)?.toDouble() ?? 0.0;
          final endSec = (w['end'] as num?)?.toDouble() ?? startSec + 0.3;
          if (wordStr.isNotEmpty) {
            allWords.add(CaptionWord(
              word: wordStr,
              start: Duration(milliseconds: (startSec * 1000).round()),
              end: Duration(milliseconds: (endSec * 1000).round()),
            ));
          }
        }
      }
    }

    if (rawSegments != null && rawSegments.isNotEmpty) {
      for (int i = 0; i < rawSegments.length; i++) {
        final seg = rawSegments[i];
        if (seg is Map) {
          final text = (seg['text'] as String? ?? '').trim();
          final startSec = (seg['start'] as num?)?.toDouble() ?? 0.0;
          final endSec = (seg['end'] as num?)?.toDouble() ?? startSec + 2.0;
          final start = Duration(milliseconds: (startSec * 1000).round());
          final end = Duration(milliseconds: (endSec * 1000).round());

          // Filter words belonging to this segment
          final segWords = allWords
              .where((w) => w.start >= start - const Duration(milliseconds: 200) && w.end <= end + const Duration(milliseconds: 200))
              .toList();

          // If no specific word timings in segment, compute proportional word timings
          final finalWords = segWords.isNotEmpty
              ? segWords
              : _distributeWordTimings(text, start, end);

          cues.add(CaptionCue(
            id: 'whisper_cue_${i + 1}_${DateTime.now().millisecondsSinceEpoch}',
            start: start,
            end: end,
            text: text,
            words: finalWords,
          ));
        }
      }
    } else if (json['text'] != null && (json['text'] as String).trim().isNotEmpty) {
      final text = (json['text'] as String).trim();
      final totalSec = (json['duration'] as num?)?.toDouble() ?? 5.0;
      const start = Duration.zero;
      final end = Duration(milliseconds: (totalSec * 1000).round());
      cues.add(CaptionCue(
        id: 'whisper_cue_1_${DateTime.now().millisecondsSinceEpoch}',
        start: start,
        end: end,
        text: text,
        words: _distributeWordTimings(text, start, end),
      ));
    }

    return cues;
  }

  /// Distributes start and end times for words across a segment duration.
  static List<CaptionWord> _distributeWordTimings(String text, Duration start, Duration end) {
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return <CaptionWord>[];

    final totalMs = end.inMilliseconds - start.inMilliseconds;
    final msPerWord = totalMs / words.length;

    final result = <CaptionWord>[];
    for (int i = 0; i < words.length; i++) {
      final wStart = start + Duration(milliseconds: (i * msPerWord).round());
      final wEnd = (i == words.length - 1)
          ? end
          : start + Duration(milliseconds: ((i + 1) * msPerWord).round());
      result.add(CaptionWord(
        word: words[i],
        start: wStart,
        end: wEnd,
      ));
    }
    return result;
  }

  /// Fallback generator when local audio is unreadable or offline.
  List<CaptionCue> _generateFallbackCues(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final text = 'Transcribed audio from $name';
    final words = _distributeWordTimings(text, Duration.zero, const Duration(seconds: 4));

    return <CaptionCue>[
      CaptionCue(
        id: 'whisper_cue_fb_${DateTime.now().millisecondsSinceEpoch}',
        start: Duration.zero,
        end: const Duration(seconds: 4),
        text: text,
        words: words,
      ),
    ];
  }
}
