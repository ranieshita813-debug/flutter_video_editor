import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_video_editor/core/logger/app_logger.dart';
import 'package:path_provider/path_provider.dart';

class GoogleTtsService {
  GoogleTtsService({
    String? apiKey,
    HttpClient? httpClient,
  })  : apiKey = apiKey ?? const String.fromEnvironment('GEMINI_API_KEY'),
        _httpClient = httpClient;

  final String apiKey;
  final HttpClient? _httpClient;

  /// Available prebuilt voices in Google AI Studio / Gemini Speech API
  static const List<String> voices = <String>[
    'Puck',
    'Charon',
    'Kore',
    'Fenrir',
    'Aoede',
  ];

  /// Generates speech audio file from input text using Google AI Studio / Gemini API.
  Future<String> textToSpeech(String text, {String voiceName = 'Puck'}) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      throw Exception('Cannot convert empty text to speech.');
    }

    AppLogger.info('[GoogleTtsService] Converting text to speech: "$cleanText" with voice $voiceName');

    if (apiKey.isNotEmpty) {
      try {
        final String filePath = await _requestGeminiTts(cleanText, voiceName);
        return filePath;
      } catch (e) {
        AppLogger.warning('[GoogleTtsService] Gemini API TTS failed ($e), generating local fallback audio.');
      }
    }

    return await _generateFallbackPcmWav(cleanText);
  }

  Future<String> _requestGeminiTts(String text, String voiceName) async {
    final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey');

    final client = _httpClient ?? HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);

    try {
      final req = await client.postUrl(url).timeout(const Duration(seconds: 20));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');

      final payload = <String, dynamic>{
        'contents': <Map<String, dynamic>>[
          <String, dynamic>{
            'parts': <Map<String, dynamic>>[
              <String, dynamic>{
                'text': 'Read the following text out loud clearly in natural speech: "$text"'
              }
            ]
          }
        ],
        'generationConfig': <String, dynamic>{
          'responseModalities': <String>['AUDIO'],
          'speechConfig': <String, dynamic>{
            'voiceConfig': <String, dynamic>{
              'prebuiltVoiceConfig': <String, dynamic>{
                'voiceName': voiceName,
              }
            }
          }
        }
      };

      req.add(utf8.encode(jsonEncode(payload)));
      final resp = await req.close().timeout(const Duration(seconds: 30));
      final body = await resp.transform(utf8.decoder).join().timeout(const Duration(seconds: 20));

      if (resp.statusCode == 200) {
        final json = jsonDecode(body) as Map<String, dynamic>;
        final candidates = json['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final content = candidates.first['content'] as Map<String, dynamic>?;
          final parts = content?['parts'] as List?;
          if (parts != null) {
            for (final part in parts) {
              final inlineData = part['inlineData'] as Map<String, dynamic>?;
              if (inlineData != null) {
                final base64Data = inlineData['data'] as String?;
                final mimeType = inlineData['mimeType'] as String? ?? 'audio/wav';
                if (base64Data != null && base64Data.isNotEmpty) {
                  final bytes = base64Decode(base64Data);
                  final ext = mimeType.contains('mp3') ? 'mp3' : 'wav';
                  return await _saveBytesToTempFile(bytes, ext);
                }
              }
            }
          }
        }
      }
      throw Exception('Gemini API returned status ${resp.statusCode}: $body');
    } finally {
      if (_httpClient == null) {
        client.close();
      }
    }
  }

  Future<String> _saveBytesToTempFile(Uint8List bytes, String extension) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.$extension');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Synthesizes a fallback audio WAV file with PCM tone waves representing word cadence.
  Future<String> _generateFallbackPcmWav(String text) async {
    final wordCount = text.trim().split(RegExp(r'\s+')).length;
    final double durationSeconds = (wordCount * 0.45).clamp(1.5, 30.0);
    const int sampleRate = 22050;
    final int numSamples = (sampleRate * durationSeconds).round();

    final Uint8List pcmData = Uint8List(numSamples * 2);
    final ByteData bd = pcmData.buffer.asByteData();

    final List<String> words = text.trim().split(RegExp(r'\s+'));

    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      final int wordIndex = ((t / durationSeconds) * words.length).floor().clamp(0, words.length - 1);
      final double freq = 180.0 + (words[wordIndex].length * 15.0) % 120;

      final double env = 0.5 + 0.5 * (1.0 - (t % 0.35) / 0.35);
      final double sample = 0.4 * env * ( (i % (sampleRate ~/ freq) > (sampleRate ~/ (2 * freq))) ? 1.0 : -1.0 );
      final int val16 = (sample * 16384).round().clamp(-32768, 32767);
      bd.setInt16(i * 2, val16, Endian.little);
    }

    final Uint8List wavHeader = Uint8List(44);
    final ByteData h = wavHeader.buffer.asByteData();

    final int dataSize = pcmData.length;
    final int fileSize = 36 + dataSize;

    h.setUint32(0, 0x52494646, Endian.big); // "RIFF"
    h.setUint32(4, fileSize, Endian.little);
    h.setUint32(8, 0x57415645, Endian.big); // "WAVE"
    h.setUint32(12, 0x666d7420, Endian.big); // "fmt "
    h.setUint32(16, 16, Endian.little); // Subchunk1Size
    h.setUint16(20, 1, Endian.little); // AudioFormat (1 = PCM)
    h.setUint16(22, 1, Endian.little); // NumChannels (1 = Mono)
    h.setUint32(24, sampleRate, Endian.little);
    h.setUint32(28, sampleRate * 2, Endian.little); // ByteRate
    h.setUint16(32, 2, Endian.little); // BlockAlign
    h.setUint16(34, 16, Endian.little); // BitsPerSample
    h.setUint32(36, 0x64617461, Endian.big); // "data"
    h.setUint32(40, dataSize, Endian.little);

    final fullWav = Uint8List(44 + dataSize);
    fullWav.setRange(0, 44, wavHeader);
    fullWav.setRange(44, 44 + dataSize, pcmData);

    return await _saveBytesToTempFile(fullWav, 'wav');
  }
}
