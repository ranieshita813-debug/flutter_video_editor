import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';

// ----------------------------------------------------------------------------
// Tokens
// ----------------------------------------------------------------------------
const Color bgToken = Color(0xFF000000);
const Color surfaceToken = Color(0xFF101014);
const Color cardToken = Color(0xFF232327);
const Color mutedToken = Color(0xFF9A9AA3);
const Color textTrackToken = Color(0xFF2A2440);
const Color fxTrackToken = Color(0xFF3A2C1C);
const Color drawTrackToken = Color(0xFF1C3A30);
const Color audioTrackToken = Color(0xFF23333A);
const Color accentToken = Color(0xFF5B8CFF);
const Color dividerToken = Color(0xFF1E1E22);

const double playheadFracToken = 0.42;
const int fpsToken = 30;
const double designWToken = 360;

// ----------------------------------------------------------------------------
// Responsive helpers
// ----------------------------------------------------------------------------
double scaleOf(Size size) => (size.shortestSide / 400).clamp(0.9, 1.25).toDouble();

bool isWide(Size size) =>
    size.width >= 840 || (size.width > size.height && size.width >= 700);

bool isShort(Size size) => size.height < 520;

int colsCount(double width, double tile, {int min = 2, int max = 8}) =>
    (width / tile).floor().clamp(min, max);

// ----------------------------------------------------------------------------
// Small utils
// ----------------------------------------------------------------------------
double secondsOf(Duration v) => v.inMilliseconds / 1000.0;
String twoDigits(int n) => n.toString().padLeft(2, '0');

String formatTimecode(double s) {
  final int f = (math.max(s, 0) * fpsToken).round();
  final int sec = f ~/ fpsToken;
  return '${twoDigits(sec ~/ 3600)}:${twoDigits(sec % 3600 ~/ 60)}:${twoDigits(sec % 60)}:${twoDigits(f % fpsToken)}';
}

String formatTimecodeShort(double s) {
  final int f = (math.max(s, 0) * fpsToken).round();
  final int sec = f ~/ fpsToken;
  return '${twoDigits(sec ~/ 60)}:${twoDigits(sec % 60)}.${twoDigits(f % fpsToken)}';
}

void seekPlayhead(EditorController e, double s) {
  final double total = math.max(secondsOf(e.project.totalDuration), 1.0);
  final double c = s.clamp(0.0, total).toDouble();
  final double q = (c * fpsToken).round() / fpsToken;
  e.setPlayhead(Duration(milliseconds: (q * 1000).round()));
}

bool isImagePath(String p) {
  final l = p.toLowerCase();
  return l.endsWith('.jpg') ||
      l.endsWith('.jpeg') ||
      l.endsWith('.png') ||
      l.endsWith('.webp') ||
      l.endsWith('.heic');
}

void tapFeedback() => HapticFeedback.selectionClick();

bool isTypingActive() {
  final BuildContext? c = FocusManager.instance.primaryFocus?.context;
  if (c == null) return false;
  return c.widget is EditableText ||
      c.findAncestorWidgetOfExactType<EditableText>() != null;
}

VoidCallback guardKeyboard(VoidCallback f) => () {
      if (!isTypingActive()) f();
    };

// ----------------------------------------------------------------------------
// Pluggable media pipelines
// ----------------------------------------------------------------------------
typedef ThumbGenerator = Future<Uint8List?> Function(String path, int timeMs, int maxWidth);
ThumbGenerator? thumbGenerator;

typedef WaveformDecoder = Future<List<double>> Function(String path, int bars);
WaveformDecoder? waveformDecoder;

class ThumbCache {
  static final Map<String, Uint8List> _mem = <String, Uint8List>{};
  static final Map<String, Future<Uint8List?>> _inflight = <String, Future<Uint8List?>>{};
  static const int _maxEntries = 500;

  static Future<Uint8List?> get(String path, int timeMs, int maxW) {
    final gen = thumbGenerator;
    if (gen == null) return Future<Uint8List?>.value();
    final String key = '$path|$timeMs|$maxW';
    final Uint8List? hit = _mem[key];
    if (hit != null) return Future<Uint8List?>.value(hit);
    Future<Uint8List?>? f = _inflight[key];
    f ??= () async {
      try {
        final Uint8List? b = await gen(path, timeMs, maxW);
        if (b != null && b.isNotEmpty) {
          if (_mem.length >= _maxEntries) _mem.remove(_mem.keys.first);
          _mem[key] = b;
        }
        return b;
      } catch (_) {
        return null;
      } finally {
        _inflight.remove(key);
      }
    }();
    _inflight[key] = f;
    return f;
  }
}

final Map<String, Future<List<double>>> waveCache = <String, Future<List<double>>>{};

Future<List<double>> waveFuture(String path, int bars) =>
    waveCache.putIfAbsent('$path|$bars', () async {
      final dec = waveformDecoder;
      if (dec != null) {
        try {
          final List<double> r = await dec(path, bars);
          if (r.isNotEmpty) return r;
        } catch (_) {}
      }
      return fallbackWave(path, bars);
    });

Future<List<double>> fallbackWave(String path, int bars) async {
  const double flat = 0.4;
  try {
    final RandomAccessFile raf = await File(path).open();
    final List<int> bytes = <int>[];
    int remaining = 48 * 1024;
    while (remaining > 0) {
      final Uint8List b = await raf.read(math.min(remaining, 4096));
      if (b.isEmpty) break;
      bytes.addAll(b);
      remaining -= b.length;
    }
    await raf.close();
    if (bytes.isEmpty) return List<double>.filled(bars, flat);
    final List<double> out = List<double>.filled(bars, flat);
    final int per = math.max(1, bytes.length ~/ bars);
    for (int i = 0; i < bars; i++) {
      int h = 0;
      final int end = math.min(bytes.length, (i + 1) * per);
      for (int j = i * per; j < end; j++) {
        h = (h * 31 + bytes[j]) & 0x7fffffff;
      }
      out[i] = 0.2 + 0.8 * ((h % 997) / 997.0);
    }
    return out;
  } catch (_) {
    return List<double>.filled(bars, flat);
  }
}

void splitAllTracks(EditorController editor) {
  final Duration ph = editor.playhead;
  final List<TimelineClip> targets = editor.project.clips
      .where((c) => !c.isLocked && ph > c.start && ph < c.end)
      .toList();
  if (targets.isEmpty) return;
  tapFeedback();
  for (final c in targets) {
    editor.selectClip(c.id);
    editor.splitSelectedClip();
  }
}
