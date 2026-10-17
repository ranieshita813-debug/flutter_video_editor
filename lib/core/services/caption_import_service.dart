import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_video_editor/core/logger/app_logger.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';

class CaptionImportService {
  /// Opens file picker to let user select a caption file (.srt, .vtt, .ass, .json).
  Future<List<CaptionCue>?> pickAndImportCaptionFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['srt', 'vtt', 'ass', 'json', 'txt'],
      );

      final path = result?.files.single.path;
      if (path == null) return null;

      return await parseCaptionFile(path);
    } catch (e, st) {
      AppLogger.error('[CaptionImportService] Failed to pick caption file', error: e, stackTrace: st);
      return null;
    }
  }

  /// Parses a caption file at [filePath] according to its extension.
  Future<List<CaptionCue>> parseCaptionFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      AppLogger.warning('[CaptionImportService] File not found at $filePath');
      return <CaptionCue>[];
    }

    final content = await file.readAsString();
    final ext = filePath.split('.').last.toLowerCase();

    switch (ext) {
      case 'srt':
        return parseSrt(content);
      case 'vtt':
        return parseVtt(content);
      case 'json':
        return parseJsonCaptions(content);
      case 'ass':
      default:
        return parseSrt(content);
    }
  }

  /// Parses SubRip (.srt) caption text into [CaptionCue]s.
  static List<CaptionCue> parseSrt(String srtContent) {
    final List<CaptionCue> cues = <CaptionCue>[];
    final blocks = srtContent.split(RegExp(r'\r?\n\r?\n'));

    int cueIndex = 1;
    for (final block in blocks) {
      final lines = block.trim().split(RegExp(r'\r?\n'));
      if (lines.length < 2) continue;

      // Check if first line is number or timestamp
      int timeLineIdx = 0;
      if (RegExp(r'^\d+$').hasMatch(lines[0].trim()) && lines.length >= 2) {
        timeLineIdx = 1;
      }

      final timeLine = lines[timeLineIdx];
      final timeMatch = RegExp(
        r'(\d{2}):(\d{2}):(\d{2})[,.](\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})[,.](\d{3})',
      ).firstMatch(timeLine);

      if (timeMatch != null) {
        final start = _parseSrtTimestamp(
          timeMatch.group(1)!,
          timeMatch.group(2)!,
          timeMatch.group(3)!,
          timeMatch.group(4)!,
        );
        final end = _parseSrtTimestamp(
          timeMatch.group(5)!,
          timeMatch.group(6)!,
          timeMatch.group(7)!,
          timeMatch.group(8)!,
        );

        final textLines = lines.sublist(timeLineIdx + 1).join(' ').trim();
        final cleanText = textLines.replaceAll(RegExp(r'<[^>]*>'), '');

        if (cleanText.isNotEmpty) {
          final words = _distributeWordTimings(cleanText, start, end);
          cues.add(CaptionCue(
            id: 'imported_cue_${cueIndex++}_${DateTime.now().millisecondsSinceEpoch}',
            start: start,
            end: end,
            text: cleanText,
            words: words,
          ));
        }
      }
    }

    return cues;
  }

  /// Parses WebVTT (.vtt) caption text into [CaptionCue]s.
  static List<CaptionCue> parseVtt(String vttContent) {
    // VTT uses same timestamp syntax as SRT with dots instead of commas
    return parseSrt(vttContent.replaceAll('WEBVTT', ''));
  }

  /// Parses JSON caption format into [CaptionCue]s.
  static List<CaptionCue> parseJsonCaptions(String jsonContent) {
    try {
      final dynamic decoded = jsonDecode(jsonContent);
      final List<CaptionCue> cues = <CaptionCue>[];

      List<dynamic> list = [];
      if (decoded is List) {
        list = decoded;
      } else if (decoded is Map && decoded['captions'] is List) {
        list = decoded['captions'] as List<dynamic>;
      } else if (decoded is Map && decoded['cues'] is List) {
        list = decoded['cues'] as List<dynamic>;
      }

      for (int i = 0; i < list.length; i++) {
        final item = list[i];
        if (item is Map) {
          final startMs = (item['startMs'] as num?)?.toInt() ??
              (((item['start'] as num?)?.toDouble() ?? 0.0) * 1000).round();
          final endMs = (item['endMs'] as num?)?.toInt() ??
              (((item['end'] as num?)?.toDouble() ?? 0.0) * 1000).round();
          final text = (item['text'] as String? ?? '').trim();

          final start = Duration(milliseconds: startMs);
          final end = Duration(milliseconds: endMs > startMs ? endMs : startMs + 2000);

          if (text.isNotEmpty) {
            cues.add(CaptionCue(
              id: 'json_cue_${i + 1}_${DateTime.now().millisecondsSinceEpoch}',
              start: start,
              end: end,
              text: text,
              words: _distributeWordTimings(text, start, end),
            ));
          }
        }
      }
      return cues;
    } catch (e, st) {
      AppLogger.error('[CaptionImportService] Failed to parse JSON captions', error: e, stackTrace: st);
      return <CaptionCue>[];
    }
  }

  static Duration _parseSrtTimestamp(String hh, String mm, String ss, String ms) {
    final hours = int.parse(hh);
    final minutes = int.parse(mm);
    final seconds = int.parse(ss);
    final millis = int.parse(ms);
    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: millis,
    );
  }

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
