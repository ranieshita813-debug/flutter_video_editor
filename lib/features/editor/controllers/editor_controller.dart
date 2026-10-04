import 'package:flutter/foundation.dart';

import 'package:flutter_video_editor/core/models/project_model.dart'
    show ClipType, TimelineClip, VideoEffect, VideoProject;

class EditorController extends ChangeNotifier {
  EditorController() {
    _project = VideoProject(
      projectName: 'CapCut Inspired Foundation',
      clips: <TimelineClip>[
        TimelineClip(
          id: 'clip_1',
          label: 'Intro Shot',
          start: Duration.zero,
          end: const Duration(seconds: 5),
          clipType: ClipType.video,
          effect: VideoEffect.cinematic,
        ),
        TimelineClip(
          id: 'clip_2',
          label: 'B-roll',
          start: const Duration(seconds: 5),
          end: const Duration(seconds: 12),
          clipType: ClipType.video,
          effect: VideoEffect.warm,
        ),
        TimelineClip(
          id: 'clip_3',
          label: 'Voiceover',
          start: const Duration(seconds: 2),
          end: const Duration(seconds: 9),
          clipType: ClipType.audio,
          volume: 0.85,
        ),
      ],
    );
  }

  late VideoProject _project;

  Duration _playhead = Duration.zero;
  bool _isPlaying = false;
  double _zoom = 1.0;
  String? _selectedClipId;

  VideoProject get project => _project;
  Duration get playhead => _playhead;
  bool get isPlaying => _isPlaying;
  double get zoom => _zoom;
  String? get selectedClipId => _selectedClipId;
  List<TimelineClip> get clips => _project.clips;

  void addClip(TimelineClip clip) {
    _project.addClip(clip);
    notifyListeners();
  }

  void selectClip(String id) {
    _selectedClipId = id;
    notifyListeners();
  }

  void setZoom(double value) {
    _zoom = value.clamp(0.7, 2.5);
    notifyListeners();
  }

  void setPlayhead(Duration value) {
    _playhead = value;
    notifyListeners();
  }

  void togglePlayback() {
    _isPlaying = !_isPlaying;
    notifyListeners();
  }

  void splitSelectedClip() {
    if (_selectedClipId == null) return;

    final existing = _project.clips.firstWhere(
      (TimelineClip clip) => clip.id == _selectedClipId,
      orElse: () => _project.clips.first,
    );

    if (_playhead <= existing.start || _playhead >= existing.end) return;

    final left = existing.copyWith(
      id: '${existing.id}_left',
      end: _playhead,
      label: '${existing.label} A',
    );

    final right = existing.copyWith(
      id: '${existing.id}_right',
      start: _playhead,
      label: '${existing.label} B',
    );

    final index = _project.clips.indexOf(existing);
    _project.clips
      ..removeAt(index)
      ..insertAll(index, <TimelineClip>[left, right]);

    _selectedClipId = right.id;
    notifyListeners();
  }

  void trimSelectedClip(Duration trimStart, Duration trimEnd) {
    if (_selectedClipId == null) return;

    final index = _project.clips.indexWhere(
      (TimelineClip clip) => clip.id == _selectedClipId,
    );
    if (index == -1) return;

    _project.clips[index] = _project.clips[index].copyWith(
      start: trimStart,
      end: trimEnd,
    );
    notifyListeners();
  }

  void addTextOverlay(String text) {
    final clip = TimelineClip(
      id: 'text_${DateTime.now().millisecondsSinceEpoch}',
      label: text,
      start: _playhead,
      end: _playhead + const Duration(seconds: 4),
      clipType: ClipType.text,
      effect: VideoEffect.vibrant,
    );

    _project.addClip(clip);
    _selectedClipId = clip.id;
    notifyListeners();
  }

  void applyEffect(VideoEffect effect) {
    if (_selectedClipId == null) return;

    final index = _project.clips.indexWhere(
      (TimelineClip clip) => clip.id == _selectedClipId,
    );
    if (index == -1) return;

    _project.clips[index] = _project.clips[index].copyWith(effect: effect);
    notifyListeners();
  }

  void addTransition() {
    _isPlaying = false;
    notifyListeners();
  }

  void reset() {
    _playhead = Duration.zero;
    _isPlaying = false;
    _selectedClipId = null;
    _zoom = 1.0;
    notifyListeners();
  }
}
