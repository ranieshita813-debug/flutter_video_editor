import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/core/services/caption_import_service.dart';
import 'package:flutter_video_editor/core/services/whisper_service.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_panel.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

void main() {
  group('WhisperService Unit Tests', () {
    test('WhisperService parses verbose JSON into CaptionCue with CaptionWords', () {
      final json = <String, dynamic>{
        'text': 'Hello world, welcome to motionGr video editor.',
        'duration': 4.5,
        'segments': [
          {
            'id': 0,
            'start': 0.0,
            'end': 2.0,
            'text': 'Hello world',
          },
          {
            'id': 1,
            'start': 2.0,
            'end': 4.5,
            'text': 'welcome to motionGr video editor.',
          },
        ],
        'words': [
          {'word': 'Hello', 'start': 0.0, 'end': 0.8},
          {'word': 'world', 'start': 0.8, 'end': 2.0},
          {'word': 'welcome', 'start': 2.0, 'end': 2.8},
          {'word': 'to', 'start': 2.8, 'end': 3.1},
          {'word': 'motionGr', 'start': 3.1, 'end': 3.7},
          {'word': 'video', 'start': 3.7, 'end': 4.1},
          {'word': 'editor.', 'start': 4.1, 'end': 4.5},
        ],
      };

      final cues = WhisperService.parseWhisperVerboseJson(json);
      expect(cues.length, equals(2));
      expect(cues[0].text, equals('Hello world'));
      expect(cues[0].words.length, equals(2));
      expect(cues[0].words[0].word, equals('Hello'));
      expect(cues[0].words[0].start, equals(Duration.zero));
      expect(cues[0].words[0].end, equals(const Duration(milliseconds: 800)));

      expect(cues[1].text, equals('welcome to motionGr video editor.'));
      expect(cues[1].words.length, equals(5));
    });
  });

  group('CaptionImportService Unit Tests', () {
    test('CaptionImportService parses SubRip (.srt) caption file content', () {
      const srt = '''
1
00:00:01,000 --> 00:00:03,500
First imported caption line

2
00:00:04,000 --> 00:00:07,200
Second imported caption line
''';

      final cues = CaptionImportService.parseSrt(srt);
      expect(cues.length, equals(2));
      expect(cues[0].text, equals('First imported caption line'));
      expect(cues[0].start, equals(const Duration(seconds: 1)));
      expect(cues[0].end, equals(const Duration(milliseconds: 3500)));
      expect(cues[0].words.isNotEmpty, isTrue);

      expect(cues[1].text, equals('Second imported caption line'));
      expect(cues[1].start, equals(const Duration(seconds: 4)));
    });

    test('CaptionImportService parses JSON caption content', () {
      const jsonStr = '''
      {
        "captions": [
          {"startMs": 500, "endMs": 2500, "text": "Json cue 1"},
          {"startMs": 3000, "endMs": 5500, "text": "Json cue 2"}
        ]
      }
      ''';

      final cues = CaptionImportService.parseJsonCaptions(jsonStr);
      expect(cues.length, equals(2));
      expect(cues[0].text, equals('Json cue 1'));
      expect(cues[0].start, equals(const Duration(milliseconds: 500)));
      expect(cues[1].text, equals('Json cue 2'));
    });
  });

  group('TextStyleProperties & Caption Models Unit Tests', () {
    test('TextStyleProperties serializes and deserializes highlight settings', () {
      const style = TextStyleProperties(
        fontSize: 32.0,
        highlightColor: Color(0xFF00FF66),
        highlightBackgroundColor: Color(0xFF111111),
        highlightStyle: 'badge',
        enableHighlight: true,
      );

      final json = style.toJson();
      final restored = TextStyleProperties.fromJson(json);

      expect(restored.fontSize, equals(32.0));
      expect(restored.highlightColor.toARGB32(), equals(const Color(0xFF00FF66).toARGB32()));
      expect(restored.highlightBackgroundColor.toARGB32(), equals(const Color(0xFF111111).toARGB32()));
      expect(restored.highlightStyle, equals('badge'));
      expect(restored.enableHighlight, isTrue);
    });

    test('CaptionCue and CaptionWord serialization', () {
      final cue = CaptionCue(
        id: 'test_cue_1',
        start: const Duration(seconds: 1),
        end: const Duration(seconds: 4),
        text: 'Test Caption Word',
        words: const [
          CaptionWord(word: 'Test', start: Duration(seconds: 1), end: Duration(milliseconds: 1800)),
          CaptionWord(word: 'Caption', start: Duration(milliseconds: 1800), end: Duration(milliseconds: 2800)),
          CaptionWord(word: 'Word', start: Duration(milliseconds: 2800), end: Duration(seconds: 4)),
        ],
      );

      final json = cue.toJson();
      final restored = CaptionCue.fromJson(json);

      expect(restored.id, equals('test_cue_1'));
      expect(restored.text, equals('Test Caption Word'));
      expect(restored.words.length, equals(3));
      expect(restored.words[1].word, equals('Caption'));
    });
  });

  group('EditorTool Panel Ordering & Icon Unit Tests', () {
    test('EditorTool.ai is the LAST enum value and uses PhosphorIconsFill.sparkle icon', () {
      const tools = EditorTool.values;
      final lastTool = tools.last;

      expect(lastTool, equals(EditorTool.ai));
      expect(lastTool.title, equals('AI Generate'));
      expect(lastTool.icon, equals(PhosphorIconsFill.sparkle));
    });
  });
}
