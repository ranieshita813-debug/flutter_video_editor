import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/services/audio_mixer.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';

class VideoPlayerPreview extends StatefulWidget {
  const VideoPlayerPreview({super.key, required this.editor});
  final EditorController editor;

  @override
  State<VideoPlayerPreview> createState() => _VideoPlayerPreviewState();
}

class _VideoPlayerPreviewState extends State<VideoPlayerPreview> {
  final Map<String, VideoPlayerController> _pool = <String, VideoPlayerController>{};
  final AudioMixer _audioMixer = AudioMixer();

  VideoPlayerController? _currentController;
  String? _currentClipId;
  String? _currentPath;
  bool _loading = false;
  bool _failed = false;
  bool _isImg = false;
  bool _isProxy = false;

  EditorController get _e => widget.editor;

  @override
  void initState() {
    super.initState();
    _e.playheadNotifier.addListener(_onPlayheadChanged);
    _e.addListener(_onEditorChanged);
    _onEditorChanged();
  }

  @override
  void didUpdateWidget(covariant VideoPlayerPreview old) {
    super.didUpdateWidget(old);
    if (old.editor != widget.editor) {
      old.editor.playheadNotifier.removeListener(_onPlayheadChanged);
      old.editor.removeListener(_onEditorChanged);
      widget.editor.playheadNotifier.addListener(_onPlayheadChanged);
      widget.editor.addListener(_onEditorChanged);
      _onEditorChanged();
    }
  }

  @override
  void dispose() {
    _e.playheadNotifier.removeListener(_onPlayheadChanged);
    _e.removeListener(_onEditorChanged);
    _audioMixer.dispose();
    for (final c in _pool.values) {
      c.dispose();
    }
    _pool.clear();
    super.dispose();
  }

  void _onPlayheadChanged() {
    _syncPlayers();
  }

  void _onEditorChanged() {
    _syncPlayers();
  }

  bool _isImagePath(String p) {
    final l = p.toLowerCase();
    return l.endsWith('.jpg') ||
        l.endsWith('.jpeg') ||
        l.endsWith('.png') ||
        l.endsWith('.webp') ||
        l.endsWith('.heic') ||
        l.endsWith('.gif');
  }

  Future<void> _syncPlayers() async {
    if (!mounted) return;
    final clip = _e.activeVideoClip;
    final String? path = clip?.sourcePath;

    _audioMixer.syncPlayback(
      clips: _e.clips,
      playhead: _e.playhead,
      isPlaying: _e.isPlaying,
    );

    if (clip == null || path == null || path.isEmpty) {
      if (_currentClipId != null) {
        setState(() {
          _currentClipId = null;
          _currentPath = null;
          _currentController = null;
          _isImg = false;
        });
      }
      return;
    }

    final bool isImage = _isImagePath(path);
    if (isImage) {
      if (_currentPath != path || !_isImg) {
        setState(() {
          _currentClipId = clip.id;
          _currentPath = path;
          _currentController = null;
          _isImg = true;
          _loading = false;
          _failed = false;
        });
      }
      return;
    }

    // Video clip
    if (_currentClipId != clip.id || _currentPath != path) {
      await _loadVideoClip(clip, path);
    }

    final c = _currentController;
    if (c == null || !c.value.isInitialized) return;

    final Duration local = _e.getClipLocalTime(clip, _e.playhead);
    final double desiredSpeed = clip.speed.clamp(0.1, 10.0);
    if ((c.value.playbackSpeed - desiredSpeed).abs() > 0.01) {
      await c.setPlaybackSpeed(desiredSpeed);
    }

    final Duration drift = (c.value.position - local).abs();
    if (_e.isPlaying) {
      if (!c.value.isPlaying) {
        await c.seekTo(local);
        await c.play();
      } else if (drift > const Duration(milliseconds: 250)) {
        await c.seekTo(local);
      }
    } else {
      if (c.value.isPlaying) await c.pause();
      if (drift > const Duration(milliseconds: 30)) await c.seekTo(local);
    }

    _preloadNextVideoClip(clip);
  }

  Future<void> _loadVideoClip(TimelineClip clip, String path) async {
    setState(() {
      _loading = true;
      _failed = false;
      _isImg = false;
      _isProxy = path.contains('_proxy');
    });

    VideoPlayerController? c = _pool[clip.id];
    if (c == null) {
      final file = File(path);
      if (!await file.exists()) {
        if (mounted) setState(() { _loading = false; _failed = true; });
        return;
      }

      c = VideoPlayerController.file(
        file,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );

      try {
        await c.initialize();
        await c.setLooping(false);

        // Keep pool max size at 2 live video controllers
        if (_pool.length >= 2) {
          final oldestKey = _pool.keys.firstWhere((k) => k != clip.id, orElse: () => _pool.keys.first);
          final oldController = _pool.remove(oldestKey);
          await oldController?.dispose();
        }

        _pool[clip.id] = c;
      } catch (_) {
        await c.dispose();
        if (mounted) setState(() { _loading = false; _failed = true; });
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      _currentClipId = clip.id;
      _currentPath = path;
      _currentController = c;
      _loading = false;
    });
  }

  void _preloadNextVideoClip(TimelineClip currentClip) {
    final nextClips = _e.clips
        .where((c) => (c.clipType == ClipType.video || c.clipType == ClipType.image) && c.start >= currentClip.end)
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    if (nextClips.isNotEmpty) {
      final next = nextClips.first;
      final path = next.sourcePath;
      if (path != null && !_isImagePath(path) && !_pool.containsKey(next.id)) {
        final file = File(path);
        file.exists().then((exists) {
          if (exists) {
            final pc = VideoPlayerController.file(file);
            pc.initialize().then((_) {
              if (_pool.length < 2) {
                _pool[next.id] = pc;
              } else {
                pc.dispose();
              }
            }).catchError((_) {
              pc.dispose();
            });
          }
        });
      }
    }
  }

  ColorFilter _getColorFilterMatrix(ColorGradingSettings g) {
    final double b = g.brightness;
    final double c = g.contrast;
    final double s = g.saturation;

    final double invSat = 1.0 - s;
    final double R = 0.213 * invSat;
    final double G = 0.715 * invSat;
    final double B = 0.072 * invSat;

    final List<double> matrix = <double>[
      (R + s) * c, G * c, B * c, 0, b * 255,
      R * c, (G + s) * c, B * c, 0, b * 255,
      R * c, G * c, (B + s) * c, 0, b * 255,
      0, 0, 0, 1, 0,
    ];

    return ColorFilter.matrix(matrix);
  }

  Widget _buildContent(TimelineClip? clip) {
    if (_isImg && _currentPath != null) {
      return Image.file(
        File(_currentPath!),
        key: ValueKey<String>(_currentPath!),
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _placeholder('Failed to load image'),
      );
    }

    final c = _currentController;
    if (c != null && c.value.isInitialized) {
      Widget videoWidget = AspectRatio(
        aspectRatio: c.value.aspectRatio,
        child: VideoPlayer(c),
      );

      if (clip != null) {
        // Color grading matrix
        videoWidget = ColorFiltered(
          colorFilter: _getColorFilterMatrix(clip.colorGrading),
          child: videoWidget,
        );

        // Opacity
        if (clip.opacity < 1.0) {
          videoWidget = Opacity(
            opacity: clip.opacity.clamp(0.0, 1.0),
            child: videoWidget,
          );
        }
      }

      return videoWidget;
    }

    if (_failed) {
      return _placeholder('Can\'t play video');
    }

    return _placeholder(clip?.label ?? 'No active media');
  }

  Widget _placeholder(String text) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (_loading)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: EditorTokens.text),
            )
          else
            const Icon(Icons.movie_outlined, size: 40, color: EditorTokens.faint),
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(color: EditorTokens.muted, fontSize: EditorTokens.minFontSize)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clip = _e.activeVideoClip;

    return RepaintBoundary(
      child: Container(
        color: EditorTokens.bg,
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: <Widget>[
            Center(child: _buildContent(clip)),
            if (_loading)
              const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2, color: EditorTokens.text),
                ),
              ),
            if (_isProxy)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('PROXY', style: TextStyle(color: EditorTokens.text, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
