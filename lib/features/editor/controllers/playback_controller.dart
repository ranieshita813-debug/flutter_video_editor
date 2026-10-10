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

  void setHead(Duration value) {
    _playhead = value;
    playheadListenable.value = value;
  }

  void setZoom(double value) {
    final double z = value.clamp(0.5, 8.0).toDouble();
    if (z == _zoom) return;
    _zoom = z;
    onTimeUpdate();
  }

  void setPlayhead(Duration value, Duration maxDuration) {
    final Duration next = maxDuration > Duration.zero
        ? Duration(
            milliseconds: value.inMilliseconds.clamp(0, maxDuration.inMilliseconds),
          )
        : value;
    if (next == _playhead) return;
    setHead(next);
    if (_isPlaying) {
      _playFrom = _playhead;
      _clock
        ..reset()
        ..start();
    }
    onTimeUpdate();
  }

  void togglePlayback(Duration totalDuration) {
    _isPlaying = !_isPlaying;
    _ticker?.cancel();
    _clock.stop();

    if (_isPlaying) {
      if (totalDuration > Duration.zero && _playhead >= totalDuration) {
        setHead(Duration.zero);
      }

      _playFrom = _playhead;
      _clock
        ..reset()
        ..start();

      _ticker = Timer.periodic(const Duration(milliseconds: 33), (Timer _) {
        final Duration next = _playFrom + _clock.elapsed;

        if (totalDuration > Duration.zero && next >= totalDuration) {
          setHead(totalDuration);
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
    setHead(Duration.zero);
    _isPlaying = false;
    _zoom = 1.0;
  }

  void dispose() {
    _ticker?.cancel();
    _clock.stop();
    playheadListenable.dispose();
  }
}
