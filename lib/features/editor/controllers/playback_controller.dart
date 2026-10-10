import 'dart:async';
import 'package:flutter/material.dart';

class PlaybackController {
  PlaybackController({
    required this.onTimeUpdate,
    Stopwatch? clock,
  }) : _clock = clock ?? Stopwatch();

  final VoidCallback onTimeUpdate;

  Duration _playhead = Duration.zero;
  bool _isPlaying = false;
  Timer? _ticker;
  final Stopwatch _clock;
  Duration _playFrom = Duration.zero;
  double _zoom = 1.0;

  final ValueNotifier<Duration> playheadListenable = ValueNotifier<Duration>(Duration.zero);

  Duration get playhead => _playhead;
  bool get isPlaying => _isPlaying;
  double get zoom => _zoom;

  void setHead(Duration value) {
    _playhead = value;
    if (playheadListenable.value != value) {
      playheadListenable.value = value;
    }
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
    if (next == _playhead && playheadListenable.value == next) return;
    setHead(next);
    if (_isPlaying) {
      _playFrom = _playhead;
      _clock
        ..reset()
        ..start();
    }
    onTimeUpdate();
  }

  void togglePlayback(Duration Function() totalDurationGetter) {
    _isPlaying = !_isPlaying;
    _ticker?.cancel();
    _clock.stop();

    if (_isPlaying) {
      final Duration initialTotal = totalDurationGetter();
      if (initialTotal > Duration.zero && _playhead >= initialTotal) {
        setHead(Duration.zero);
      }

      _playFrom = _playhead;
      _clock
        ..reset()
        ..start();

      _ticker = Timer.periodic(const Duration(milliseconds: 33), (Timer _) {
        final Duration next = _playFrom + _clock.elapsed;
        final Duration currentTotal = totalDurationGetter();

        if (currentTotal > Duration.zero && next >= currentTotal) {
          setHead(currentTotal);
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
    onTimeUpdate();
  }

  void dispose() {
    _ticker?.cancel();
    _clock.stop();
    playheadListenable.dispose();
  }
}
