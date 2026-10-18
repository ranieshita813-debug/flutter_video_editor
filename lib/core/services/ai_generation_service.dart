import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:flutter_video_editor/core/logger/app_logger.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/ai/gen.dart';

class AiGenerationService {
  AiGenerationService({
    String? apiKey,
    String? baseUrl,
    HttpClient? httpClient,
  })  : apiKey = apiKey ?? const String.fromEnvironment('AI_API_KEY'),
        baseUrl = baseUrl ?? _defaultBaseUrl,
        _httpClient = httpClient;

  static const String _defaultBaseUrl = 'https://gen.pollinations.ai/v1';

  final String apiKey;
  final String baseUrl;
  final HttpClient? _httpClient;

  /// Sends an [AiGenerationRequest] to the Pollinations API and returns local File path to generated media.
  Future<String> generateMedia(AiGenerationRequest request) async {
    final bool isVideo = request.type == AiMediaType.video;
    final String endpoint = isVideo ? '$baseUrl/video/generations' : '$baseUrl/images/generations';

    AppLogger.info('[AiGenerationService] Requesting AI ${request.type.name} generation with model ${request.modelId}');

    final client = _httpClient ?? HttpClient();
    try {
      final req = await client.postUrl(Uri.parse(endpoint));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      if (apiKey.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      }

      final payload = <String, dynamic>{
        'model': request.modelId,
        'prompt': request.prompt,
        if (request.negativePrompt != null) 'negative_prompt': request.negativePrompt,
        if (request.style != null) 'style': request.style,
        'aspect_ratio': request.aspectRatio,
        'n': request.count,
        'guidance_scale': request.guidance,
        'steps': request.steps,
        if (request.seed != null) 'seed': request.seed,
        if (request.durationSeconds != null) 'duration': request.durationSeconds,
        if (request.motionStrength != null) 'motion': request.motionStrength,
      };

      req.add(utf8.encode(jsonEncode(payload)));
      final resp = await req.close();
      final responseBody = await resp.transform(utf8.decoder).join();

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final Map<String, dynamic> json = jsonDecode(responseBody) as Map<String, dynamic>;
        String? mediaUrl;

        final data = json['data'];
        if (data is List && data.isNotEmpty) {
          final first = data.first;
          if (first is Map) {
            mediaUrl = first['url'] as String? ?? first['b64_json'] as String?;
          }
        } else if (json['url'] != null) {
          mediaUrl = json['url'] as String;
        }

        if (mediaUrl != null && mediaUrl.startsWith('http')) {
          return await _downloadMediaFile(mediaUrl, isVideo);
        } else if (mediaUrl != null && mediaUrl.startsWith('data:image')) {
          return await _saveBase64Image(mediaUrl);
        } else {
          AppLogger.warning('[AiGenerationService] API succeeded but no media URL returned. Falling back to response file.');
          return await _saveRawResponse(responseBody, isVideo);
        }
      } else {
        AppLogger.error('[AiGenerationService] API error (${resp.statusCode}): $responseBody');
        throw Exception('AI generation failed (${resp.statusCode}): $responseBody');
      }
    } catch (e, st) {
      AppLogger.error('[AiGenerationService] Exception generating AI media', error: e, stackTrace: st);
      rethrow;
    } finally {
      if (_httpClient == null) {
        client.close();
      }
    }
  }

  Future<String> _downloadMediaFile(String url, bool isVideo) async {
    final client = _httpClient ?? HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close();

      final bytes = await resp.fold<List<int>>(<int>[], (acc, data) => acc..addAll(data));
      final tempDir = await getTemporaryDirectory();
      final ext = isVideo ? 'mp4' : 'png';
      final file = File('${tempDir.path}/ai_gen_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await file.writeAsBytes(bytes);
      return file.path;
    } finally {
      if (_httpClient == null) {
        client.close();
      }
    }
  }

  Future<String> _saveBase64Image(String dataUrl) async {
    final commaIndex = dataUrl.indexOf(',');
    final base64Str = commaIndex != -1 ? dataUrl.substring(commaIndex + 1) : dataUrl;
    final bytes = base64Decode(base64Str);
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/ai_gen_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  Future<String> _saveRawResponse(String content, bool isVideo) async {
    final tempDir = await getTemporaryDirectory();
    final ext = isVideo ? 'mp4' : 'png';
    final file = File('${tempDir.path}/ai_gen_${DateTime.now().millisecondsSinceEpoch}.$ext');
    await file.writeAsString(content);
    return file.path;
  }
}
