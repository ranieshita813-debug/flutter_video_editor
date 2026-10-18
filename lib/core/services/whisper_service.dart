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
      AppLogger.error('[WhisperService] File does not exist at $audioFilePath.');
      throw Exception('Audio file not found at $audioFilePath');
    }

    try {
      final uri = Uri.parse('$baseUrl/audio/transcriptions');
      final request = HttpClient();
      request.connectionTimeout = const Duration(seconds: 30);
      final req = await request.postUrl(uri).timeout(const Duration(seconds: 30));

      final boundary = '----WhisperBoundary${DateTime.now().millisecondsSinceEpoch}';
      req.headers.set(HttpHeaders.contentTypeHeader, 'multipart/form-data; boundary=$boundary');
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');

      final headerBytes = <int>[];

      void addField(String name, String value) {
        headerBytes.addAll(utf8.encode('--$boundary\r\n'));
        headerBytes.addAll(utf8.encode('Content-Disposition: form-data; name="$name"\r\n\r\n'));
        headerBytes.addAll(utf8.encode('$value\r\n'));
      }

      addField('model', model);
      addField('response_format', 'verbose_json');
      addField('timestamp_granularities[]', 'segment');
      addField('timestamp_granularities[]', 'word');

      final normalizedLang = normalizeLanguageCode(language);
      if (normalizedLang != null && normalizedLang.isNotEmpty) {
        addField('language', normalizedLang);
      }

      // Add audio/video file
      final fileName = audioFilePath.split(Platform.pathSeparator).last;
      final ext = fileName.split('.').last.toLowerCase();
      final contentType = switch (ext) {
        'mp3' => 'audio/mpeg',
        'wav' => 'audio/wav',
        'm4a' || 'mp4' => 'audio/mp4',
        'aac' => 'audio/aac',
        'ogg' => 'audio/ogg',
        'flac' => 'audio/flac',
        _ => 'application/octet-stream',
      };

      headerBytes.addAll(utf8.encode('--$boundary\r\n'));
      headerBytes.addAll(utf8.encode('Content-Disposition: form-data; name="file"; filename="$fileName"\r\n'));
      headerBytes.addAll(utf8.encode('Content-Type: $contentType\r\n\r\n'));

      final footerBytes = utf8.encode('\r\n--$boundary--\r\n');
      final fileSize = await file.length();

      req.contentLength = headerBytes.length + fileSize + footerBytes.length;
      req.add(headerBytes);
      await req.addStream(file.openRead()).timeout(const Duration(seconds: 120));
      req.add(footerBytes);

      final resp = await req.close().timeout(const Duration(seconds: 60));
      final responseBody = await resp.transform(utf8.decoder).join().timeout(const Duration(seconds: 30));

      if (resp.statusCode == 200) {
        final Map<String, dynamic> json = jsonDecode(responseBody) as Map<String, dynamic>;
        return parseWhisperVerboseJson(json);
      } else {
        AppLogger.error('[WhisperService] API error (${resp.statusCode}): $responseBody');
        throw Exception('Whisper API transcription failed (${resp.statusCode}): $responseBody');
      }
    } catch (e, st) {
      AppLogger.error('[WhisperService] Exception transcribing audio', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Normalizes language names or codes to ISO 639-1 language codes (e.g., Bengali -> bn).
  static String? normalizeLanguageCode(String? language) {
    if (language == null || language.trim().isEmpty) return null;
    final lower = language.trim().toLowerCase();
    switch (lower) {
      case 'bengali':
      case 'bn':
      case 'bangla':
        return 'bn';
      case 'hindi':
      case 'hi':
        return 'hi';
      case 'spanish':
      case 'es':
        return 'es';
      case 'french':
      case 'fr':
        return 'fr';
      case 'german':
      case 'de':
        return 'de';
      case 'japanese':
      case 'ja':
        return 'ja';
      case 'arabic':
      case 'ar':
        return 'ar';
      case 'chinese':
      case 'zh':
        return 'zh';
      case 'russian':
      case 'ru':
        return 'ru';
      case 'english':
      case 'en':
        return 'en';
      default:
        return lower;
    }
  }

  /// Parses OpenAI Whisper verbose_json structure into a list of [CaptionCue]s with word timings.
  static List<CaptionCue> parseWhisperVerboseJson(Map<String, dynamic> json) {
    final List<CaptionCue> cues = <CaptionCue>[];

    final rawSegments = json['segments'] as List<dynamic>?;
    final rawWords = json['words'] as List<dynamic>?;

    final List<CaptionWord> topLevelWords = <CaptionWord>[];
    if (rawWords != null) {
      for (final w in rawWords) {
        if (w is Map) {
          final wordStr = (w['word'] as String? ?? '').trim();
          final startSec = (w['start'] as num?)?.toDouble() ?? 0.0;
          final endSec = (w['end'] as num?)?.toDouble() ?? startSec + 0.3;
          if (wordStr.isNotEmpty) {
            topLevelWords.add(CaptionWord(
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

          final List<CaptionWord> segWords = <CaptionWord>[];
          final segWordsRaw = seg['words'] as List<dynamic>?;
          if (segWordsRaw != null && segWordsRaw.isNotEmpty) {
            for (final w in segWordsRaw) {
              if (w is Map) {
                final wordStr = (w['word'] as String? ?? '').trim();
                final wStartSec = (w['start'] as num?)?.toDouble() ?? startSec;
                final wEndSec = (w['end'] as num?)?.toDouble() ?? wStartSec + 0.3;
                if (wordStr.isNotEmpty) {
                  segWords.add(CaptionWord(
                    word: wordStr,
                    start: Duration(milliseconds: (wStartSec * 1000).round()),
                    end: Duration(milliseconds: (wEndSec * 1000).round()),
                  ));
                }
              }
            }
          }

          if (segWords.isEmpty && topLevelWords.isNotEmpty) {
            segWords.addAll(
              topLevelWords.where((w) => w.start >= start - const Duration(milliseconds: 300) && w.end <= end + const Duration(milliseconds: 300)),
            );
          }

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

    return chunkCaptionCues(cues);
  }

  /// Chunks/splits long caption cues into concise sub-cues (max [maxWords] or max [maxDuration]).
  static List<CaptionCue> chunkCaptionCues(
    List<CaptionCue> cues, {
    int maxWords = 4,
    Duration maxDuration = const Duration(milliseconds: 2500),
  }) {
    final List<CaptionCue> result = <CaptionCue>[];

    for (int i = 0; i < cues.length; i++) {
      final cue = cues[i];
      final words = cue.words;

      if (words.isEmpty) {
        result.add(cue);
        continue;
      }

      List<CaptionWord> currentChunk = <CaptionWord>[];

      void flushChunk() {
        if (currentChunk.isEmpty) return;
        final start = currentChunk.first.start;
        final end = currentChunk.last.end;
        final text = currentChunk.map((w) => w.word).join(' ');
        result.add(CaptionCue(
          id: '${cue.id}_chunk_${result.length + 1}',
          start: start,
          end: end > start ? end : start + const Duration(milliseconds: 300),
          text: text,
          words: List<CaptionWord>.from(currentChunk),
        ));
        currentChunk = <CaptionWord>[];
      }

      for (final word in words) {
        if (currentChunk.isNotEmpty) {
          final chunkDuration = word.end - currentChunk.first.start;
          if (currentChunk.length >= maxWords || chunkDuration > maxDuration) {
            flushChunk();
          }
        }
        currentChunk.add(word);
      }
      flushChunk();
    }

    return result;
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
}
