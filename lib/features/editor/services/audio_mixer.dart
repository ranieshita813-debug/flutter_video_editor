import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';

class AudioPlayerEntry {
  AudioPlayerEntry({required this.clipId, required this.controller});
  final String clipId;
  final VideoPlayerController controller;
  bool isReady = false;
}

class AudioMixer {
  final Map<String, AudioPlayerEntry> _players = <String, AudioPlayerEntry>{};

  /// Sync audio players to playhead position
  Future<void> syncPlayback({
    required List<TimelineClip> clips,
    required Duration playhead,
    required bool isPlaying,
  }) async {
    final audioClips = clips.where((c) => c.clipType == ClipType.audio || c.clipType == ClipType.video).toList();
    final activeClipIds = <String>{};

    for (final clip in audioClips) {
      if (clip.sourcePath == null || clip.sourcePath!.isEmpty) continue;

      // Preload clips starting within next 2 seconds or active
      final bool isActive = playhead >= clip.start && playhead <= clip.end;
      final bool isUpcoming = clip.start >= playhead && clip.start <= playhead + const Duration(seconds: 2);

      if (isActive || isUpcoming) {
        activeClipIds.add(clip.id);
        AudioPlayerEntry? entry = _players[clip.id];

        if (entry == null) {
          final controller = kIsWeb
              ? VideoPlayerController.networkUrl(Uri.parse(clip.sourcePath!))
              : VideoPlayerController.file(File(clip.sourcePath!));
          entry = AudioPlayerEntry(clipId: clip.id, controller: controller);
          _players[clip.id] = entry;

          controller.initialize().then((_) {
            entry?.isReady = true;
            controller.setVolume(clip.volume);
          }).catchError((_) {});
        }

        if (entry.isReady) {
          final Duration localTime = (playhead - clip.start + clip.trimStart) * clip.speed;
          final double volume = _calculateVolumeWithFade(clip, playhead);
          entry.controller.setVolume(volume);

          if (isActive && isPlaying) {
            final Duration currentPos = entry.controller.value.position;
            final Duration drift = (currentPos - localTime).abs();
            if (drift > const Duration(milliseconds: 80)) {
              await entry.controller.seekTo(localTime);
            }
            if (!entry.controller.value.isPlaying) {
              await entry.controller.play();
            }
          } else {
            if (entry.controller.value.isPlaying) {
              await entry.controller.pause();
            }
            if (!isPlaying && isActive) {
              final Duration currentPos = entry.controller.value.position;
              if ((currentPos - localTime).abs() > const Duration(milliseconds: 40)) {
                await entry.controller.seekTo(localTime);
              }
            }
          }
        }
      }
    }

    // Dispose unused audio players
    final keysToRemove = _players.keys.where((k) => !activeClipIds.contains(k)).toList();
    for (final key in keysToRemove) {
      final entry = _players.remove(key);
      entry?.controller.dispose();
    }
  }

  double _calculateVolumeWithFade(TimelineClip clip, Duration playhead) {
    if (playhead < clip.start || playhead > clip.end) return 0.0;
    double vol = clip.volume;
    final fadeIn = clip.audioProperties.fadeIn;
    final fadeOut = clip.audioProperties.fadeOut;

    final elapsed = playhead - clip.start;
    final remaining = clip.end - playhead;

    if (fadeIn > Duration.zero && elapsed < fadeIn) {
      vol *= (elapsed.inMilliseconds / fadeIn.inMilliseconds).clamp(0.0, 1.0);
    }
    if (fadeOut > Duration.zero && remaining < fadeOut) {
      vol *= (remaining.inMilliseconds / fadeOut.inMilliseconds).clamp(0.0, 1.0);
    }

    return vol.clamp(0.0, 1.0);
  }

  void dispose() {
    for (final entry in _players.values) {
      entry.controller.dispose();
    }
    _players.clear();
  }
}
