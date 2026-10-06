import 'dart:async';

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
  }

  late VideoProject _project;

  Duration _playhead = Duration.zero;
  bool _isPlaying = false;
  Timer? _ticker;
  double _zoom = 1.0;
  String? _selectedClipId;
  ExportSettings _exportSettings = const ExportSettings();
  bool _isExporting = false;
  double _exportProgress = 0.0;
  bool _isCameraActive = false;

  // Vector Drawing State
  List<DrawingStroke> _activeDrawingStrokes = <DrawingStroke>[];
  Color _drawingColor = Colors.purpleAccent;
  double _strokeWidth = 4.0;

  // Undo / Redo Stacks
  final List<List<TimelineClip>> _undoStack = <List<TimelineClip>>[];
  final List<List<TimelineClip>> _redoStack = <List<TimelineClip>>[];

  VideoProject get project => _project;

  void loadProject(VideoProject project) {
    _ticker?.cancel();
    _project = project;
    _selectedClipId = project.clips.isNotEmpty ? project.clips.first.id : null;
    _playhead = Duration.zero;
    _isPlaying = false;
    _undoStack.clear();
    _redoStack.clear();
    notifyListeners();
  }

  Duration get playhead => _playhead;
  bool get isPlaying => _isPlaying;
  double get zoom => _zoom;
  String? get selectedClipId => _selectedClipId;
  List<TimelineClip> get clips => _project.clips;
  ExportSettings get exportSettings => _exportSettings;
  bool get isExporting => _isExporting;
  double get exportProgress => _exportProgress;
  bool get isCameraActive => _isCameraActive;

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
    for (final clip in _project.clips) {
      if ((clip.clipType == ClipType.video || clip.clipType == ClipType.image) &&
          _playhead >= clip.start &&
          _playhead <= clip.end) {
        return clip;
      }
    }
    return selectedClip;
  }

  void _saveState() {
    final snapshot = _project.clips.map((c) => c.copyWith()).toList();
    _undoStack.add(snapshot);
    if (_undoStack.length > 25) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
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

  void addClip(TimelineClip clip) {
    _saveState();
    _project.addClip(clip);
    _selectedClipId = clip.id;
    notifyListeners();
  }

  void selectClip(String? id) {
    _selectedClipId = id;
    notifyListeners();
  }

  void setZoom(double value) {
    _zoom = value.clamp(0.5, 3.0);
    notifyListeners();
  }

  void setPlayhead(Duration value) {
    final maxDuration = _project.totalDuration;
    if (maxDuration > Duration.zero) {
      _playhead = Duration(
        milliseconds: value.inMilliseconds.clamp(0, maxDuration.inMilliseconds),
      );
    } else {
      _playhead = value;
    }
    notifyListeners();
  }

  void togglePlayback() {
    _isPlaying = !_isPlaying;
    _ticker?.cancel();

    if (_isPlaying) {
      final Duration total = _project.totalDuration;
      if (total > Duration.zero && _playhead >= total) {
        _playhead = Duration.zero;
      }

      const Duration tick = Duration(milliseconds: 33);
      _ticker = Timer.periodic(tick, (Timer _) {
        final Duration end = _project.totalDuration;
        final Duration next = _playhead + tick;

        if (end > Duration.zero && next >= end) {
          _playhead = end;
          _isPlaying = false;
          _ticker?.cancel();
        } else {
          _playhead = next;
        }
        notifyListeners();
      });
    }

    notifyListeners();
  }

  void toggleCameraActive() {
    _isCameraActive = !_isCameraActive;
    notifyListeners();
  }

  void splitSelectedClip() {
    if (_selectedClipId == null) return;

    final existing = selectedClip;
    if (existing == null) return;

    if (_playhead <= existing.start || _playhead >= existing.end) return;

    _saveState();

    final left = existing.copyWith(
      id: '${existing.id}_part1',
      end: _playhead,
      label: '${existing.label} (Part 1)',
    );

    final right = existing.copyWith(
      id: '${existing.id}_part2',
      start: _playhead,
      label: '${existing.label} (Part 2)',
    );

    final index = _project.clips.indexOf(existing);
    _project.clips
      ..removeAt(index)
      ..insertAll(index, <TimelineClip>[left, right]);

    _selectedClipId = right.id;
    notifyListeners();
  }

  void deleteSelectedClip() {
    if (_selectedClipId == null) return;
    _saveState();
    _project.removeClip(_selectedClipId!);
    _selectedClipId = _project.clips.isNotEmpty ? _project.clips.first.id : null;
    notifyListeners();
  }

  void removeSelectedClip() {
    deleteSelectedClip();
  }

  void duplicateSelectedClip() {
    final current = selectedClip;
    if (current == null) return;
    _saveState();
    final copy = current.copyWith(
      id: 'clip_${DateTime.now().millisecondsSinceEpoch}',
      start: current.end,
      end: current.end + current.duration,
    );
    _project.addClip(copy);
    _selectedClipId = copy.id;
    notifyListeners();
  }

  void addMediaClip(String path) {
    _saveState();
    final lower = path.toLowerCase();
    final isVideo = lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.webm');
    final clip = TimelineClip(
      id: 'clip_${DateTime.now().millisecondsSinceEpoch}',
      label: path.split('/').last,
      start: _playhead,
      end: _playhead + const Duration(seconds: 5),
      clipType: isVideo ? ClipType.video : ClipType.image,
      sourcePath: path,
    );
    _project.addClip(clip);
    _selectedClipId = clip.id;
    notifyListeners();
  }

  void trimSelectedClip(Duration trimStart, Duration trimEnd) {
    if (_selectedClipId == null) return;

    final index = _project.clips.indexWhere(
      (TimelineClip clip) => clip.id == _selectedClipId,
    );
    if (index == -1) return;

    _saveState();
    _project.clips[index] = _project.clips[index].copyWith(
      start: trimStart,
      end: trimEnd,
    );
    notifyListeners();
  }

  void updateSelectedClipAnimation(ClipAnimation animation, {required bool isInAnimation}) {
    if (isInAnimation) {
      updateAnimations(inAnimation: animation);
    } else {
      updateAnimations(outAnimation: animation);
    }
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

  // Text & Fonts
  void addTextOverlay(
    String text, {
    String fontFamily = 'Poppins',
    TextAnimationStyle animationStyle = TextAnimationStyle.fadeIn,
  }) {
    _saveState();
    final clip = TimelineClip(
      id: 'text_${DateTime.now().millisecondsSinceEpoch}',
      label: text,
      start: _playhead,
      end: _playhead + const Duration(seconds: 4),
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

  List<String> get availableFonts {
    final list = <String>[
      'Poppins',
      'Unbounded',
      'Roboto',
      'Montserrat',
      'Playfair Display',
      'Bebas Neue',
      'Caveat',
      ..._project.customFonts,
    ];
    return list.toSet().toList();
  }

  void updateSelectedClipTextStyle(TextStyleProperties properties) {
    final current = selectedClip;
    if (current == null) return;

    _saveState();
    final index = _project.clips.indexWhere((c) => c.id == current.id);
    if (index != -1) {
      _project.clips[index] = _project.clips[index].copyWith(
        textStyle: properties,
      );
      notifyListeners();
    }
  }

  void updateSelectedClipFont(String fontFamily) {
    final current = selectedClip;
    if (current == null) return;

    _saveState();
    final index = _project.clips.indexWhere((c) => c.id == current.id);
    if (index != -1) {
      _project.clips[index] = _project.clips[index].copyWith(
        fontFamily: fontFamily,
      );
      notifyListeners();
    }
  }

  void updateSelectedTextProperties({
    String? text,
    String? fontFamily,
    TextAnimationStyle? textAnimationStyle,
    TextStyleProperties? textStyle,
  }) {
    final current = selectedClip;
    if (current == null || (current.clipType != ClipType.text && current.clipType != ClipType.caption)) return;

    _saveState();
    final index = _project.clips.indexWhere((c) => c.id == current.id);
    _project.clips[index] = _project.clips[index].copyWith(
      label: text ?? current.label,
      fontFamily: fontFamily ?? current.fontFamily,
      textAnimationStyle: textAnimationStyle ?? current.textAnimationStyle,
      textStyle: textStyle ?? current.textStyle,
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
      start: _playhead,
      end: _playhead + const Duration(seconds: 5),
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

  void updateChromaKeySettings(ChromaKeySettings settings) {
    if (_selectedClipId == null) return;

    final index = _project.clips.indexWhere((c) => c.id == _selectedClipId);
    if (index == -1) return;

    _saveState();
    _project.clips[index] = _project.clips[index].copyWith(
      chromaKey: settings,
    );
    notifyListeners();
  }

  void extractAudioFromSelectedClip() {
    final clip = selectedClip;
    if (clip == null || clip.sourcePath == null) return;
    if (clip.clipType != ClipType.video) return;

    _saveState();

    // Mute original video clip
    final index = _project.clips.indexWhere((c) => c.id == clip.id);
    if (index != -1) {
      _project.clips[index] = _project.clips[index].copyWith(
        volume: 0.0,
        audioProperties: _project.clips[index].audioProperties.copyWith(volume: 0.0),
      );
    }

    // Create extracted audio clip
    final audioClip = TimelineClip(
      id: 'extracted_audio_${DateTime.now().millisecondsSinceEpoch}',
      label: 'Audio - ${clip.label}',
      start: clip.start,
      end: clip.end,
      trimIn: clip.trimIn,
      trimOut: clip.trimOut,
      clipType: ClipType.audio,
      layerIndex: 1,
      speed: clip.speed,
      volume: clip.volume == 0.0 ? 1.0 : clip.volume,
      sourcePath: clip.sourcePath,
      audioProperties: clip.audioProperties.copyWith(
        volume: clip.volume == 0.0 ? 1.0 : clip.volume,
        speed: clip.speed,
      ),
    );

    _project.addClip(audioClip);
    _selectedClipId = audioClip.id;
    notifyListeners();
  }

  // Audio Tools & Multi-layer
  void addAudioTrack(String trackName, {double volume = 1.0}) {
    _saveState();
    final clip = TimelineClip(
      id: 'audio_${DateTime.now().millisecondsSinceEpoch}',
      label: trackName,
      start: _playhead,
      end: _playhead + const Duration(seconds: 10),
      clipType: ClipType.audio,
      layerIndex: 1,
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
      start: _playhead,
      end: _playhead + const Duration(seconds: 5),
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
    _playhead = Duration.zero;
    _isPlaying = false;
    _selectedClipId = null;
    _zoom = 1.0;
    _activeDrawingStrokes.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
