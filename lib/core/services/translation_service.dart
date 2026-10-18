import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_video_editor/core/logger/app_logger.dart';

class TranslationService {
  TranslationService();

  static const Map<String, String> _langCodes = {
    'Bengali': 'bn',
    'English': 'en',
    'Spanish': 'es',
    'French': 'fr',
    'German': 'de',
    'Hindi': 'hi',
    'Japanese': 'ja',
    'Arabic': 'ar',
    'Chinese': 'zh',
    'Russian': 'ru',
  };

  static const Map<String, Map<String, String>> _phraseDictionary = {
    'Bengali': {
      'hello world': 'হ্যালো বিশ্ব',
      'welcome to video editor': 'ভিডিও সম্পাদকে স্বাগতম',
      'hello': 'হ্যালো',
      'world': 'বিশ্ব',
      'welcome': 'স্বাগতম',
      'video': 'ভিডিও',
      'editor': 'সম্পাদক',
      'thank you': 'ধন্যবাদ',
      'good morning': 'শুভ সকাল',
      'flutter': 'ফ্লাটার',
      'caption': 'ক্যাপশন',
      'captions': 'ক্যাপশন',
      'auto captions': 'স্বয়ংক্রিয় ক্যাপশন',
      'text': 'লেখা',
      'audio': 'শব্দ',
      'music': 'সঙ্গীত',
      'effect': 'প্রভাব',
      'subtitles': 'উপশিরোনাম',
      'this is': 'এটি হল',
      'how are you': 'আপনি কেমন আছেন',
      'good': 'ভাল',
      'great': 'দারুণ',
      'nice': 'সুন্দর',
    },
    'Spanish': {
      'hello world': 'hola mundo',
      'welcome to video editor': 'bienvenido al editor de video',
      'hello': 'hola',
      'world': 'mundo',
      'welcome': 'bienvenido',
      'video': 'video',
      'editor': 'editor',
      'thank you': 'gracias',
      'flutter': 'flutter',
      'caption': 'subtítulo',
      'auto captions': 'subtítulos automáticos',
      'good morning': 'buenos días',
      'how are you': 'cómo estás',
    },
    'French': {
      'hello world': 'bonjour le monde',
      'welcome to video editor': 'bienvenue dans l\'éditeur vidéo',
      'hello': 'bonjour',
      'world': 'monde',
      'welcome': 'bienvenue',
      'video': 'vidéo',
      'editor': 'éditeur',
      'thank you': 'merci',
      'caption': 'légende',
      'good morning': 'bonjour',
    },
    'German': {
      'hello world': 'hallo welt',
      'welcome to video editor': 'willkommen im video-editor',
      'hello': 'hallo',
      'world': 'welt',
      'welcome': 'willkommen',
      'video': 'video',
      'editor': 'editor',
      'thank you': 'danke',
      'caption': 'titel',
    },
    'Hindi': {
      'hello world': 'नमस्ते दुनिया',
      'welcome to video editor': 'वीडियो संपादक में आपका स्वागत है',
      'hello': 'नमस्ते',
      'world': 'दुनिया',
      'welcome': 'स्वागत',
      'video': 'वीडियो',
      'editor': 'संपादक',
      'thank you': 'धन्यवाद',
      'caption': 'कैप्शन',
    },
    'Japanese': {
      'hello world': 'ハローワールド',
      'welcome to video editor': '動画エディターへようこそ',
      'hello': 'こんにちは',
      'world': '世界',
      'welcome': 'ようこそ',
      'video': '動画',
      'editor': 'エディター',
      'thank you': 'ありがとう',
      'caption': 'キャプション',
    },
    'Arabic': {
      'hello world': 'مرحبا بالعالم',
      'welcome to video editor': 'مرحبا بكم في محرر الفيديو',
      'hello': 'مرحبا',
      'world': 'العالم',
      'welcome': 'أهلا بك',
      'video': 'فيديو',
      'editor': 'محرر',
      'thank you': 'شكرا لك',
    },
    'Chinese': {
      'hello world': '你好世界',
      'welcome to video editor': '欢迎使用视频编辑器',
      'hello': '你好',
      'world': '世界',
      'welcome': '欢迎',
      'video': '视频',
      'editor': '编辑器',
      'thank you': '谢谢',
    },
    'Russian': {
      'hello world': 'привет мир',
      'welcome to video editor': 'добро пожаловать в видеоредактор',
      'hello': 'привет',
      'world': 'мир',
      'welcome': 'добро пожаловать',
      'video': 'видео',
      'editor': 'редактор',
      'thank you': 'спасибо',
    },
  };

  /// Translates [text] to [targetLanguage] (e.g., 'Bengali', 'Spanish', 'French').
  Future<String> translateText(String text, String targetLanguage) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return text;

    final targetCode = _langCodes[targetLanguage] ?? targetLanguage.toLowerCase();

    // Strategy 1: Attempt HTTP translation via Lingva / Google API with short timeout
    try {
      final translated = await _fetchOnlineTranslation(trimmed, targetCode);
      if (translated != null && translated.trim().isNotEmpty && translated.trim() != trimmed) {
        return translated.trim();
      }
    } catch (e) {
      AppLogger.warning('[TranslationService] Online translation attempt failed, using fallback: $e');
    }

    // Strategy 2: Expanded built-in phrase & word dictionary translation
    AppLogger.warning('[TranslationService] Online translation unavailable, using offline dictionary fallback for target language: $targetLanguage');
    return _dictionaryTranslate(trimmed, targetLanguage);
  }

  Future<String?> _fetchOnlineTranslation(String text, String targetLangCode) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      AppLogger.info('[TranslationService] Requesting online translation via Lingva API (lingva.ml) to $targetLangCode');
      final encoded = Uri.encodeComponent(text);
      final uri = Uri.parse('https://lingva.ml/api/v1/auto/$targetLangCode/$encoded');
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final Map<String, dynamic> json = jsonDecode(body) as Map<String, dynamic>;
        final trans = json['translation'] as String?;
        if (trans != null && trans.trim().isNotEmpty && trans.trim().toLowerCase() != text.trim().toLowerCase()) {
          return trans.trim();
        }
      }
    } catch (_) {
      // Fallback
    } finally {
      client.close();
    }
    return null;
  }

  String _dictionaryTranslate(String original, String targetLanguage) {
    final dict = _phraseDictionary[targetLanguage];
    if (dict == null) return original;

    final lower = original.toLowerCase().trim();

    // Direct match
    if (dict.containsKey(lower)) {
      return dict[lower]!;
    }

    // Phrase replacement
    String result = original;
    for (final entry in dict.entries) {
      if (entry.key.contains(' ')) {
        final reg = RegExp(r'\b' + RegExp.escape(entry.key) + r'\b', caseSensitive: false);
        if (reg.hasMatch(result)) {
          result = result.replaceAll(reg, entry.value);
        }
      }
    }

    // Word-by-word replacement
    final words = result.split(RegExp(r'\s+'));
    final translatedWords = words.map((w) {
      final clean = w.replaceAll(RegExp(r'[^\w\s]'), '').toLowerCase();
      if (dict.containsKey(clean)) {
        return dict[clean]!;
      }
      return w;
    }).toList();

    return translatedWords.join(' ');
  }
}
