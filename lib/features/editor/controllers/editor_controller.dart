import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'package:flutter_video_editor/core/logger/app_logger.dart';
import 'package:flutter_video_editor/core/models/project_model.dart' hide ExportSettings;
import 'package:flutter_video_editor/features/export/models/export_settings.dart';
import 'package:flutter_video_editor/features/export/models/timeline_dto.dart';
import 'package:flutter_video_editor/features/export/services/export_service.dart';

class EditorController extends ChangeNotifier {
  EditorController() {
    _project = VideoProject(
      id: 'proj_${DateTime.now().millisecondsSinceEpoch}',
      name: 'New Project',
      clips: <TimelineClip>[],
    );
    _selectedClipId = null;
    _startAutosaveTimer();
  }

  late VideoProject _project;

  final ValueNotifier<Duration> playheadNotifier = ValueNotifier<Duration>(Duration.zero);
  Duration get playhead => playheadNotifier.value;

  bool _isPlaying = false;
  Timer? _ticker;
  Timer? _autosaveTimer;
  double _zoom = 1.0;
  String? _selectedClipId;
  final Set<String> _multiSelectedClipIds = <String>{};
  TimelineClip? _copiedClip;
  bool _isDirty = false;

  ExportSettings _exportSettings = const ExportSettings();
  bool _isExporting = false;
  double _exportProgress = 0.0;
  bool _isCameraActive = false;

  // Vector Drawing State
  List<DrawingStroke> _activeDrawingStrokes = <DrawingStroke>[];
  Color _drawingColor = Colors.white;
  double _strokeWidth = 4.0;

  // Undo / Redo Stacks
  final List<List<TimelineClip>> _undoStack = <List<TimelineClip>>[];
  final List<List<TimelineClip>> _redoStack = <List<TimelineClip>>[];
  List<TimelineClip>? _gestureSnapshot;

  VideoProject get project => _project;
  int get fps => _project.fps > 0 ? _project.fps : 30;

  void loadProject(VideoProject project) {
    _ticker?.cancel();
    _project = project;
    _selectedClipId = project.clips.isNotEmpty ? project.clips.first.id : null;
    _multiSelectedClipIds.clear();
    playheadNotifier.value = Duration.zero;
    _isPlaying = false;
    _undoStack.clear();
    _redoStack.clear();
    _isDirty = false;
    notifyListeners();
  }

  bool get isPlaying => _isPlaying;
  double get zoom => _zoom;
  String? get selectedClipId => _selectedClipId;
  Set<String> get multiSelectedClipIds => _multiSelectedClipIds;
  List<TimelineClip> get clips => _project.clips;
  ExportSettings get exportSettings => _exportSettings;
  bool get isExporting => _isExporting;
  double get exportProgress => _exportProgress;
  bool get isCameraActive => _isCameraActive;
  bool get isDirty => _isDirty;

  List<DrawingStroke> get activeDrawingStrokes => _activeDrawingStrokes;
  Color get drawingColor => _drawingColor;
  double get strokeWidth => _strokeWidth;

  TimelineClip? get selectedClip {
    if (_selectedClipId == null) return null;
    try {
      return _project.clips.firstWhere((clip) => clip.id == _selectedClipId);
    } catch (_) {
      return null;
    }
  }

  TimelineClip? get activeVideoClip {
    final Duration current = playhead;
    for (final clip in _project.clips) {
      if ((clip.clipType == ClipType.video || clip.clipType == ClipType.image) &&
          current >= clip.start &&
          current <= clip.end) {
        return clip;
      }
    }
    return selectedClip;
  }

  void _saveState() {
    _isDirty = true;
    final snapshot = _project.clips.map((c) => c.copyWith()).toList();
    _undoStack.add(snapshot);
    if (_undoStack.length > 30) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void beginGesture() {
    _gestureSnapshot = _project.clips.map((c) => c.copyWith()).toList();
  }

  void commitGesture() {
    if (_gestureSnapshot != null) {
      _isDirty = true;
      _undoStack.add(_gestureSnapshot!);
      if (_undoStack.length > 30) {
        _undoStack.removeAt(0);
      }
      _redoStack.clear();
      _gestureSnapshot = null;
    }
  }

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void undo() {
    if (!canUndo) return;
    _redoStack.add(_project.clips.map((c) => c.copyWith()).toList());
    final previous = _undoStack.removeLast();
    _project.clips.clear();
    _project.clips.addAll(previous);
    notifyListeners();
  }

  void redo() {
    if (!canRedo) return;
    _undoStack.add(_project.clips.map((c) => c.copyWith()).toList());
    final next = _redoStack.removeLast();
    _project.clips.clear();
    _project.clips.addAll(next);
    notifyListeners();
  }

  void markSaved() {
    _isDirty = false;
  }

  void _startAutosaveTimer() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      autosave();
    });
  }

  void autosave() {
    if (_isDirty) {
      AppLogger.info('Autosaving project ${_project.id}', tag: 'EditorController');
      _isDirty = false;
    }
  }

  // --------------------------------------------------------------------------
  // Clip Management & Adding
  // --------------------------------------------------------------------------

  void addClip(TimelineClip clip) {
    _saveState();
    _project.addClip(clip);
    _selectedClipId = clip.id;
    notifyListeners();
  }

  /// Appends new clips to current project. Main track clips (video/image) go
  /// sequentially after the last main track clip. Audio clips go to the audio lane at playhead.
  void addClips(List<TimelineClip> newClips) {
    if (newClips.isEmpty) return;
    _saveState();

    final mainClips = _project.clips
        .where((c) => c.clipType == ClipType.video || c.clipType == ClipType.image)
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    Duration nextMainStart = mainClips.isNotEmpty ? mainClips.last.end : Duration.zero;

    for (final raw in newClips) {
      TimelineClip clip = raw;
      if (clip.clipType == ClipType.video || clip.clipType == ClipType.image) {
        final Duration dur = clip.duration;
        clip = clip.copyWith(start: nextMainStart, end: nextMainStart + dur);
        nextMainStart += dur;
      } else if (clip.clipType == ClipType.audio) {
        final Duration dur = clip.duration;
        clip = clip.copyWith(start: playhead, end: playhead + dur, layerIndex: _assignAudioLane(playhead, playhead + dur));
      } else {
        final Duration dur = clip.duration;
        clip = clip.copyWith(start: playhead, end: playhead + dur);
      }
      _project.addClip(clip);
    }
    _selectedClipId = newClips.last.id;
    notifyListeners();
  }

  int _assignAudioLane(Duration start, Duration end) {
    final audioClips = _project.clips.where((c) => c.clipType == ClipType.audio).toList();
    int lane = 1;
    while (true) {
      bool overlap = audioClips.any((c) => c.layerIndex == lane && !(end <= c.start || start >= c.end));
      if (!overlap) return lane;
      lane++;
    }
  }

  void selectClip(String? id, {bool toggleMulti = false}) {
    if (toggleMulti && id != null) {
      if (_multiSelectedClipIds.contains(id)) {
        _multiSelectedClipIds.remove(id);
      } else {
        _multiSelectedClipIds.add(id);
      }
      _selectedClipId = id;
    } else {
      _multiSelectedClipIds.clear();
      if (id != null) _multiSelectedClipIds.add(id);
      _selectedClipId = id;
    }
    notifyListeners();
  }

  void setZoom(double value) {
    _zoom = value.clamp(0.5, 8.0);
    notifyListeners();
  }

  void setPlayhead(Duration value) {
    final maxDuration = _project.totalDuration;
    final int quantizedMs = ((value.inMilliseconds / 1000.0 * fps).round() / fps * 1000).round();
    final Duration clamped = Duration(
      milliseconds: quantizedMs.clamp(0, math.max(maxDuration.inMilliseconds, 0)),
    );
    if (playheadNotifier.value != clamped) {
      playheadNotifier.value = clamped;
    }
  }

  void jumpToStart() {
    setPlayhead(Duration.zero);
  }

  void jumpToEnd() {
    setPlayhead(_project.totalDuration);
  }

  void togglePlayback() {
    _isPlaying = !_isPlaying;
    _ticker?.cancel();

    if (_isPlaying) {
      final Duration total = _project.totalDuration;
      if (total > Duration.zero && playhead >= total) {
        setPlayhead(Duration.zero);
      }

      final int stepMs = (1000 / fps).round();
      final Duration tick = Duration(milliseconds: stepMs);
      _ticker = Timer.periodic(tick, (Timer _) {
        final Duration end = _project.totalDuration;
        final Duration next = playhead + tick;

        if (end > Duration.zero && next >= end) {
          setPlayhead(end);
          _isPlaying = false;
          _ticker?.cancel();
        } else {
          setPlayhead(next);
        }
      });
    }

    notifyListeners();
  }

  // --------------------------------------------------------------------------
  // Trim, Move, Ripple & Speed
  // --------------------------------------------------------------------------

  /// Trim start/end of a clip.
  void updateClipTrim(String clipId, {Duration? trimStart, Duration? trimEnd}) {
    final index = _project.clips.indexWhere((c) => c.id == clipId);
    if (index == -1) return;
    final clip = _project.clips[index];

    final double speedFactor = clip.speed > 0 ? clip.speed : 1.0;
    final Duration minDur = Duration(milliseconds: (100 * speedFactor).round());

    Duration newTrimStart = trimStart ?? clip.trimStart;
    Duration newTrimEnd = trimEnd ?? clip.trimEnd;

    if (newTrimStart < Duration.zero) newTrimStart = Duration.zero;
    if (newTrimEnd < Duration.zero) newTrimEnd = Duration.zero;

    // Source duration bounds
    final Duration availableSource = clip.sourceDuration;
    if (newTrimStart + newTrimEnd > availableSource - minDur) {
      return;
    }

    final Duration effectiveSourceDur = availableSource - newTrimStart - newTrimEnd;
    final Duration newTimelineDur = Duration(milliseconds: (effectiveSourceDur.inMilliseconds / speedFactor).round());

    final updated = clip.copyWith(
      trimStart: newTrimStart,
      trimEnd: newTrimEnd,
      end: clip.start + (newTimelineDur < minDur ? minDur : newTimelineDur),
    );

    _project.clips[index] = updated;

    if (clip.clipType == ClipType.video || clip.clipType == ClipType.image) {
      _applyRippleMainTrack();
    }

    notifyListeners();
  }

  /// Move clip to a new start time, with optional ripple on main track.
  void moveClip(String clipId, Duration newStart) {
    final index = _project.clips.indexWhere((c) => c.id == clipId);
    if (index == -1) return;
    final clip = _project.clips[index];

    final Duration dur = clip.duration;
    Duration clampedStart = newStart.isNegative ? Duration.zero : newStart;

    _project.clips[index] = clip.copyWith(
      start: clampedStart,
      end: clampedStart + dur,
    );

    if (clip.clipType == ClipType.video || clip.clipType == ClipType.image) {
      _project.clips.sort((a, b) {
        if ((a.clipType == ClipType.video || a.clipType == ClipType.image) &&
            (b.clipType == ClipType.video || b.clipType == ClipType.image)) {
          return a.start.compareTo(b.start);
        }
        return 0;
      });
      _applyRippleMainTrack();
    }

    notifyListeners();
  }

  void _applyRippleMainTrack() {
    final mainClips = _project.clips
        .where((c) => c.clipType == ClipType.video || c.clipType == ClipType.image)
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    Duration currentStart = Duration.zero;
    for (final c in mainClips) {
      final idx = _project.clips.indexOf(c);
      final dur = c.duration;
      _project.clips[idx] = c.copyWith(
        start: currentStart,
        end: currentStart + dur,
      );
      currentStart += dur;
    }
  }

  /// Map timeline playhead to local media playback position
  Duration getClipLocalTime(TimelineClip clip, Duration playhead) {
    if (playhead < clip.start) return clip.trimStart;
    final Duration offset = playhead - clip.start;
    final Duration scaledOffset = Duration(milliseconds: (offset.inMilliseconds * clip.speed).round());
    Duration local = clip.trimStart + scaledOffset;
    final Duration maxLocal = clip.sourceDuration - clip.trimEnd;
    if (local > maxLocal) local = maxLocal;
    return local;
  }

  void setPlaybackSpeed(double speed) {
    if (_selectedClipId == null) return;
    final index = _project.clips.indexWhere((c) => c.id == _selectedClipId);
    if (index == -1) return;

    _saveState();
    final clip = _project.clips[index];
    final double safeSpeed = speed.clamp(0.1, 10.0);

    final Duration availableSource = clip.sourceDuration - clip.trimStart - clip.trimEnd;
    final Duration newTimelineDur = Duration(milliseconds: (availableSource.inMilliseconds / safeSpeed).round());

    _project.clips[index] = clip.copyWith(
      speed: safeSpeed,
      end: clip.start + newTimelineDur,
    );

    if (clip.clipType == ClipType.video || clip.clipType == ClipType.image) {
      _applyRippleMainTrack();
    }

    notifyListeners();
  }

  void setClipTransition(String clipId, ClipTransition transition) {
    final index = _project.clips.indexWhere((c) => c.id == clipId);
    if (index == -1) return;
    _saveState();
    _project.clips[index] = _project.clips[index].copyWith(transition: transition);
    notifyListeners();
  }

  // --------------------------------------------------------------------------
  // Edit Actions: Split, Delete, Duplicate, Reverse, Freeze, Copy/Paste
  // --------------------------------------------------------------------------

  void splitSelectedClip() {
    if (_selectedClipId == null) return;
    final existing = selectedClip;
    if (existing == null) return;

    final Duration current = playhead;
    if (current <= existing.start || current >= existing.end) return;

    _saveState();

    final double speedFactor = existing.speed > 0 ? existing.speed : 1.0;
    final Duration splitTimelineOffset = current - existing.start;
    final Duration splitSourceOffset = Duration(milliseconds: (splitTimelineOffset.inMilliseconds * speedFactor).round());

    final left = existing.copyWith(
      id: '${existing.id}_part1',
      end: current,
      trimEnd: existing.trimEnd + (existing.sourceDuration - existing.trimStart - existing.trimEnd - splitSourceOffset),
      label: '${existing.label} (Part 1)',
    );

    final right = existing.copyWith(
      id: '${existing.id}_part2',
      start: current,
      trimStart: existing.trimStart + splitSourceOffset,
      label: '${existing.label} (Part 2)',
    );

    final index = _project.clips.indexOf(existing);
    _project.clips
      ..removeAt(index)
      ..insertAll(index, <TimelineClip>[left, right]);

    _selectedClipId = right.id;
    if (existing.clipType == ClipType.video || existing.clipType == ClipType.image) {
      _applyRippleMainTrack();
    }
    notifyListeners();
  }

  void deleteSelectedClip() {
    final targetIds = _multiSelectedClipIds.isNotEmpty
        ? Set<String>.from(_multiSelectedClipIds)
        : (_selectedClipId != null ? <String>{_selectedClipId!} : <String>{});

    if (targetIds.isEmpty) return;

    _saveState();
    _project.clips.removeWhere((c) => targetIds.contains(c.id));
    _multiSelectedClipIds.clear();
    _selectedClipId = _project.clips.isNotEmpty ? _project.clips.first.id : null;

    _applyRippleMainTrack();
    notifyListeners();
  }

  void duplicateSelectedClip() {
    final clip = selectedClip;
    if (clip == null) return;

    _saveState();
    final Duration dur = clip.duration;
    final newClip = clip.copyWith(
      id: 'clip_${DateTime.now().millisecondsSinceEpoch}',
      label: '${clip.label} (Copy)',
      start: clip.end,
      end: clip.end + dur,
    );

    _project.addClip(newClip);
    if (clip.clipType == ClipType.video || clip.clipType == ClipType.image) {
      _applyRippleMainTrack();
    }
    _selectedClipId = newClip.id;
    notifyListeners();
  }

  void copySelectedClip() {
    if (selectedClip != null) {
      _copiedClip = selectedClip;
      AppLogger.info('Copied clip ${selectedClip!.id}', tag: 'EditorController');
    }
  }

  void pasteClip() {
    if (_copiedClip == null) return;
    _saveState();
    final clip = _copiedClip!;
    final Duration dur = clip.duration;
    final pasted = clip.copyWith(
      id: 'clip_${DateTime.now().millisecondsSinceEpoch}',
      label: '${clip.label} (Pasted)',
      start: playhead,
      end: playhead + dur,
    );
    _project.addClip(pasted);
    if (pasted.clipType == ClipType.video || pasted.clipType == ClipType.image) {
      _applyRippleMainTrack();
    }
    _selectedClipId = pasted.id;
    notifyListeners();
  }

  void freezeFrame() {
    final clip = selectedClip;
    if (clip == null) return;
    _saveState();

    final freezeClip = clip.copyWith(
      id: 'freeze_${DateTime.now().millisecondsSinceEpoch}',
      label: 'Freeze Frame',
      clipType: ClipType.image,
      start: playhead,
      end: playhead + const Duration(seconds: 3),
    );

    _project.addClip(freezeClip);
    if (clip.clipType == ClipType.video || clip.clipType == ClipType.image) {
      _applyRippleMainTrack();
    }
    _selectedClipId = freezeClip.id;
    notifyListeners();
  }

  void toggleReverse() {
    final clip = selectedClip;
    if (clip == null) return;
    _saveState();
    final index = _project.clips.indexOf(clip);
    _project.clips[index] = clip.copyWith(isReversed: !clip.isReversed);
    notifyListeners();
  }

  void toggleClipVisibility(String id) {
    final index = _project.clips.indexWhere((c) => c.id == id);
    if (index == -1) return;
    _project.clips[index] = _project.clips[index].copyWith(
      isVisible: !_project.clips[index].isVisible,
    );
    notifyListeners();
  }

  void toggleClipLock(String id) {
    final index = _project.clips.indexWhere((c) => c.id == id);
    if (index == -1) return;
    _project.clips[index] = _project.clips[index].copyWith(
      isLocked: !_project.clips[index].isLocked,
    );
    notifyListeners();
  }

  // --------------------------------------------------------------------------
  // Text & Fonts
  // --------------------------------------------------------------------------

  void addTextOverlay(
    String text, {
    String fontFamily = 'Poppins',
    TextAnimationStyle animationStyle = TextAnimationStyle.fadeIn,
  }) {
    _saveState();
    final clip = TimelineClip(
      id: 'text_${DateTime.now().millisecondsSinceEpoch}',
      label: text,
      start: playhead,
      end: playhead + const Duration(seconds: 4),
      clipType: ClipType.text,
      layerIndex: 2,
      fontFamily: fontFamily,
      textAnimationStyle: animationStyle,
      effect: VideoEffect.vibrant,
    );

    _project.addClip(clip);
    _selectedClipId = clip.id;
    notifyListeners();
  }

  void updateSelectedTextProperties({
    String? text,
    String? fontFamily,
    TextAnimationStyle? textAnimationStyle,
  }) {
    final current = selectedClip;
    if (current == null || current.clipType != ClipType.text) return;

    _saveState();
    final index = _project.clips.indexWhere((c) => c.id == current.id);
    _project.clips[index] = _project.clips[index].copyWith(
      label: text ?? current.label,
      fontFamily: fontFamily ?? current.fontFamily,
      textAnimationStyle: textAnimationStyle ?? current.textAnimationStyle,
    );
    notifyListeners();
  }

  void uploadCustomFont(String fontName) {
    if (!_project.customFonts.contains(fontName)) {
      _project.customFonts.add(fontName);
      notifyListeners();
    }
  }

  // Elements & Objects
  void addElementClip(
    ElementShape shape, {
    String label = 'Element',
    Color color = Colors.white,
  }) {
    _saveState();
    final clip = TimelineClip(
      id: 'elem_${DateTime.now().millisecondsSinceEpoch}',
      label: '$label (${shape.name})',
      start: playhead,
      end: playhead + const Duration(seconds: 5),
      clipType: ClipType.element,
      layerIndex: 3,
      elementProperties: ElementProperties(
        shape: shape,
        fillColor: color,
      ),
    );

    _project.addClip(clip);
    _selectedClipId = clip.id;
    notifyListeners();
  }

  void updateElementProperties(ElementProperties elementProperties) {
    if (_selectedClipId == null) return;
    final index = _project.clips.indexWhere((c) => c.id == _selectedClipId);
    if (index == -1) return;

    _saveState();
    _project.clips[index] = _project.clips[index].copyWith(
      elementProperties: elementProperties,
    );
    notifyListeners();
  }

  // Camera Settings
  void updateCameraProperties(CameraProperties cameraProperties) {
    if (_selectedClipId == null) return;
    final index = _project.clips.indexWhere((c) => c.id == _selectedClipId);
    if (index == -1) return;

    _saveState();
    _project.clips[index] = _project.clips[index].copyWith(
      cameraProperties: cameraProperties,
    );
    notifyListeners();
  }

  // Masking
  void updateMaskProperties(MaskProperties maskProperties) {
    if (_selectedClipId == null) return;
    final index = _project.clips.indexWhere((c) => c.id == _selectedClipId);
    if (index == -1) return;

    _saveState();
    _project.clips[index] = _project.clips[index].copyWith(
      maskProperties: maskProperties,
    );
    notifyListeners();
  }

  // Keyframes & Curves
  void addKeyframe(Keyframe keyframe) {
    if (_selectedClipId == null) return;
    final index = _project.clips.indexWhere((c) => c.id == _selectedClipId);
    if (index == -1) return;

    _saveState();
    final updatedKeyframes = List<Keyframe>.from(_project.clips[index].keyframes)
      ..removeWhere((k) => k.property == keyframe.property && k.time == keyframe.time)
      ..add(keyframe);

    _project.clips[index] = _project.clips[index].copyWith(
      keyframes: updatedKeyframes,
    );
    notifyListeners();
  }

  void removeKeyframe(String keyframeId) {
    if (_selectedClipId == null) return;
    final index = _project.clips.indexWhere((c) => c.id == _selectedClipId);
    if (index == -1) return;

    _saveState();
    final updatedKeyframes = List<Keyframe>.from(_project.clips[index].keyframes)
      ..removeWhere((k) => k.id == keyframeId);

    _project.clips[index] = _project.clips[index].copyWith(
      keyframes: updatedKeyframes,
    );
    notifyListeners();
  }

  // Translation & Transform
  void updateTranslation({
    double? positionX,
    double? positionY,
    double? scale,
    double? rotation,
    double? opacity,
    double? anchorX,
    double? anchorY,
  }) {
    if (_selectedClipId == null) return;
    final index = _project.clips.indexWhere((c) => c.id == _selectedClipId);
    if (index == -1) return;

    _saveState();
    _project.clips[index] = _project.clips[index].copyWith(
      positionX: positionX ?? _project.clips[index].positionX,
      positionY: positionY ?? _project.clips[index].positionY,
      scale: scale ?? _project.clips[index].scale,
      rotation: rotation ?? _project.clips[index].rotation,
      opacity: opacity ?? _project.clips[index].opacity,
      anchorX: anchorX ?? _project.clips[index].anchorX,
      anchorY: anchorY ?? _project.clips[index].anchorY,
    );
    notifyListeners();
  }

  // Animations
  void updateAnimations({
    ClipAnimation? inAnimation,
    ClipAnimation? outAnimation,
    ClipAnimation? loopAnimation,
  }) {
    if (_selectedClipId == null) return;
    final index = _project.clips.indexWhere((c) => c.id == _selectedClipId);
    if (index == -1) return;

    _saveState();
    _project.clips[index] = _project.clips[index].copyWith(
      inAnimation: inAnimation ?? _project.clips[index].inAnimation,
      outAnimation: outAnimation ?? _project.clips[index].outAnimation,
      loopAnimation: loopAnimation ?? _project.clips[index].loopAnimation,
    );
    notifyListeners();
  }

  // Multilayer & Reordering
  void reorderClipLayer(String clipId, int newLayerIndex) {
    final index = _project.clips.indexWhere((c) => c.id == clipId);
    if (index == -1) return;

    _saveState();
    _project.clips[index] = _project.clips[index].copyWith(
      layerIndex: newLayerIndex,
    );
    notifyListeners();
  }

  // Effects & Color Grading
  void applyEffect(VideoEffect effect) {
    if (_selectedClipId == null) return;

    final index = _project.clips.indexWhere(
      (TimelineClip clip) => clip.id == _selectedClipId,
    );
    if (index == -1) return;

    _saveState();
    _project.clips[index] = _project.clips[index].copyWith(effect: effect);
    notifyListeners();
  }

  void updateColorGrading(ColorGradingSettings colorGrading) {
    if (_selectedClipId == null) return;

    final index = _project.clips.indexWhere(
      (TimelineClip clip) => clip.id == _selectedClipId,
    );
    if (index == -1) return;

    _saveState();
    _project.clips[index] =
        _project.clips[index].copyWith(colorGrading: colorGrading);
    notifyListeners();
  }

  // Audio Tools & Multi-layer
  void addAudioTrack(String trackName, {double volume = 1.0}) {
    _saveState();
    final clip = TimelineClip(
      id: 'audio_${DateTime.now().millisecondsSinceEpoch}',
      label: trackName,
      start: playhead,
      end: playhead + const Duration(seconds: 10),
      clipType: ClipType.audio,
      layerIndex: _assignAudioLane(playhead, playhead + const Duration(seconds: 10)),
      volume: volume,
      audioProperties: AudioProperties(volume: volume),
    );

    _project.addClip(clip);
    _selectedClipId = clip.id;
    notifyListeners();
  }

  void updateAudioProperties(AudioProperties audioProperties) {
    if (_selectedClipId == null) return;

    final index = _project.clips.indexWhere(
      (TimelineClip clip) => clip.id == _selectedClipId,
    );
    if (index == -1) return;

    _saveState();
    _project.clips[index] = _project.clips[index].copyWith(
      audioProperties: audioProperties,
      volume: audioProperties.volume,
      speed: audioProperties.speed,
    );
    notifyListeners();
  }

  // Vector Drawing Tools
  void setDrawingColor(Color color) {
    _drawingColor = color;
    notifyListeners();
  }

  void setStrokeWidth(double width) {
    _strokeWidth = width;
    notifyListeners();
  }

  void addStrokeToActiveDrawing(DrawingStroke stroke) {
    _activeDrawingStrokes.add(stroke);
    notifyListeners();
  }

  void clearActiveDrawing() {
    _activeDrawingStrokes.clear();
    notifyListeners();
  }

  void saveVectorDrawingAsClip() {
    if (_activeDrawingStrokes.isEmpty) return;
    _saveState();

    final clip = TimelineClip(
      id: 'drawing_${DateTime.now().millisecondsSinceEpoch}',
      label:
          'Vector Drawing ${_project.clips.where((c) => c.clipType == ClipType.drawing).length + 1}',
      start: playhead,
      end: playhead + const Duration(seconds: 5),
      clipType: ClipType.drawing,
      layerIndex: 3,
      strokes: List<DrawingStroke>.from(_activeDrawingStrokes),
    );

    _project.addClip(clip);
    _activeDrawingStrokes = <DrawingStroke>[];
    _selectedClipId = clip.id;
    notifyListeners();
  }

  // Camera & Tracking
  void updateTrackingData(TrackingData trackingData) {
    if (_selectedClipId == null) return;

    final index = _project.clips.indexWhere(
      (TimelineClip clip) => clip.id == _selectedClipId,
    );
    if (index == -1) return;

    _saveState();
    _project.clips[index] =
        _project.clips[index].copyWith(trackingData: trackingData);
    notifyListeners();
  }

  // Auto Captions Generator
  void generateAutoCaptions() {
    _saveState();
    _project.captions.clear();

    _project.clips.removeWhere((TimelineClip c) => c.clipType == ClipType.caption);

    final mediaClips = _project.clips
        .where((c) => c.clipType == ClipType.video || c.clipType == ClipType.audio)
        .toList();

    if (mediaClips.isEmpty) {
      notifyListeners();
      return;
    }

    final newCaptions = <CaptionCue>[];
    for (int i = 0; i < mediaClips.length; i++) {
      final clip = mediaClips[i];
      final cue = CaptionCue(
        id: 'cap_${i + 1}_${DateTime.now().millisecondsSinceEpoch}',
        start: clip.start,
        end: clip.end,
        text: 'Caption: ${clip.label}',
      );
      newCaptions.add(cue);
    }

    _project.captions.addAll(newCaptions);

    for (final cue in newCaptions) {
      final clip = TimelineClip(
        id: 'caption_${cue.id}',
        label: cue.text,
        start: cue.start,
        end: cue.end,
        clipType: ClipType.caption,
        layerIndex: 4,
        fontFamily: 'Poppins',
      );
      _project.addClip(clip);
    }

    notifyListeners();
  }

  // Camera Active
  void toggleCameraActive() {
    _isCameraActive = !_isCameraActive;
    notifyListeners();
  }

  // Export pipeline
  void updateExportSettings(ExportSettings settings) {
    _exportSettings = settings;
    notifyListeners();
  }

  Future<String?> startExport({Function? onComplete}) async {
    _isExporting = true;
    _exportProgress = 0.0;
    notifyListeners();

    try {
      AppLogger.info('Starting timeline export for project ${_project.id}', tag: 'EditorController');
      final exportService = ExportService();
      final dto = TimelineDto.fromProject(_project, _exportSettings);
      final resultPath = await exportService.exportTimeline(dto.toJson());
      _isExporting = false;
      _exportProgress = 1.0;
      notifyListeners();
      if (onComplete != null) {
        if (onComplete is void Function(String)) {
          onComplete(resultPath);
        } else {
          onComplete();
        }
      }
      return resultPath;
    } catch (e, stack) {
      AppLogger.error('Timeline export failed', tag: 'EditorController', error: e, stackTrace: stack);
      _isExporting = false;
      notifyListeners();
      return null;
    }
  }

  void reset() {
    _ticker?.cancel();
    playheadNotifier.value = Duration.zero;
    _isPlaying = false;
    _selectedClipId = null;
    _multiSelectedClipIds.clear();
    _zoom = 1.0;
    _activeDrawingStrokes.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _autosaveTimer?.cancel();
    playheadNotifier.dispose();
    super.dispose();
  }
}
