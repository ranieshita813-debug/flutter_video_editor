import 'dart:async';
import 'package:flutter/material.dart';

class PlaybackController {
  PlaybackController({required this.onTimeUpdate});

  final VoidCallback onTimeUpdate;

  Duration _playhead = Duration.zero;
  bool _isPlaying = false;
  Timer? _ticker;
  final Stopwatch _clock = Stopwatch();
  Duration _playFrom = Duration.zero;
  double _zoom = 1.0;

  final ValueNotifier<Duration> playheadListenable = ValueNotifier<Duration>(Duration.zero);

  Duration get playhead => _playhead;
  bool get isPlaying => _isPlaying;
  double get zoom => _zoom;

  void setHead(Duration value, {Duration? maxDuration, bool notifyParent = false}) {
    final Duration next = (maxDuration != null && maxDuration > Duration.zero)
        ? Duration(
            milliseconds: value.inMilliseconds.clamp(0, maxDuration.inMilliseconds),
          )
        : (value.isNegative ? Duration.zero : value);

    if (next == _playhead) return;
    _playhead = next;
    playheadListenable.value = next;

    if (_isPlaying && notifyParent) {
      _playFrom = _playhead;
      _clock
        ..reset()
        ..start();
    }
    if (notifyParent) {
      onTimeUpdate();
    }
  }

  void setZoom(double value) {
    final double z = value.clamp(0.5, 8.0).toDouble();
    if (z == _zoom) return;
    _zoom = z;
    onTimeUpdate();
  }

  void setPlayhead(Duration value, Duration maxDuration) {
    setHead(value, maxDuration: maxDuration, notifyParent: true);
  }

  void togglePlayback(Duration Function() totalDurationGetter) {
    _isPlaying = !_isPlaying;
    _ticker?.cancel();
    _clock.stop();

    if (_isPlaying) {
      final Duration currentTotal = totalDurationGetter();
      if (currentTotal > Duration.zero && _playhead >= currentTotal) {
        setHead(Duration.zero);
      }

      _playFrom = _playhead;
      _clock
        ..reset()
        ..start();

      _ticker = Timer.periodic(const Duration(milliseconds: 33), (Timer _) {
        final Duration total = totalDurationGetter();
        final Duration next = _playFrom + _clock.elapsed;

        if (total > Duration.zero && next >= total) {
          setHead(total);
          _isPlaying = false;
          _ticker?.cancel();
          _clock.stop();
          onTimeUpdate();
        } else {
          setHead(next);
        }
      });
    }

    onTimeUpdate();
  }

  void reset() {
    _ticker?.cancel();
    _clock.stop();
    setHead(Duration.zero, notifyParent: true);
    _isPlaying = false;
    _zoom = 1.0;
  }

  void dispose() {
    _ticker?.cancel();
    _clock.stop();
    playheadListenable.dispose();
  }
}
