import 'package:flutter/material.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';

class EditorController extends ChangeNotifier {
  EditorController();

  final VideoProject _project = VideoProject(
    projectName: 'CapCut Inspired Foundation',
    clips: <TimelineClip>[
      TimelineClip(
        id: 'clip_1',
        label: 'Opening Shot',
        start: Duration.zero,
        end: const Duration(seconds: 6),
        clipType: ClipType.video,
        effect: VideoEffect.cinematic,
      ),
      TimelineClip(
        id: 'clip_2',
        label: 'Travel B-roll',
        start: const Duration(seconds: 6),
        end: const Duration(seconds: 14),
        clipType: ClipType.video,
        effect: VideoEffect.warm,
      ),
      TimelineClip(
        id: 'clip_3',
        label: 'Voiceover',
        start: const Duration(seconds: 2),
        end: const Duration(seconds: 10),
        clipType: ClipType.audio,
        volume: 0.85,
      ),
    ],
  );

  Duration _playhead = Duration.zero;
  bool _isPlaying = false;
  double _zoom = 1.0;
  String? _selectedClipId;

  VideoProject get project => _project;
  Duration get playhead => _playhead;
  bool get isPlaying => _isPlaying;
  double get zoom => _zoom;
  String? get selectedClipId => _selectedClipId;

  List<TimelineClip> get allClips => _project.clips;

  void selectClip(String id) {
    _selectedClipId = id;
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

  void setZoom(double value) {
    _zoom = value.clamp(0.7, 2.5);
    notifyListeners();
  }

  void splitSelectedClip() {
    if (_selectedClipId == null) return;

    final target = _project.clips.firstWhere(
      (clip) => clip.id == _selectedClipId,
      orElse: () => _project.clips.first,
    );

    if (_playhead <= target.start || _playhead >= target.end) {
      return;
    }

    final left = target.copyWith(
      id: '${target.id}_left',
      end: _playhead,
      label: '${target.label} A',
    );

    final right = target.copyWith(
      id: '${target.id}_right',
      start: _playhead,
      label: '${target.label} B',
    );

    final index = _project.clips.indexOf(target);
    _project.clips
      ..removeAt(index)
      ..insertAll(index, <TimelineClip>[left, right]);

    _selectedClipId = right.id;
    notifyListeners();
  }

  void trimSelectedClip(Duration newStart, Duration newEnd) {
    if (_selectedClipId == null) return;

    final index = _project.clips.indexWhere((clip) => clip.id == _selectedClipId);
    if (index == -1) return;

    _project.clips[index] = _project.clips[index].copyWith(
      start: newStart,
      end: newEnd,
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

    final index = _project.clips.indexWhere((clip) => clip.id == _selectedClipId);
    if (index == -1) return;

    _project.clips[index] = _project.clips[index].copyWith(effect: effect);
    notifyListeners();
  }
}
