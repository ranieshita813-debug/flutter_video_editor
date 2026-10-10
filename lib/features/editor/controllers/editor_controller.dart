import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_video_editor/core/logger/app_logger.dart';
import 'package:flutter_video_editor/core/models/chroma_key.dart';
import 'package:flutter_video_editor/core/models/project_model.dart' hide ExportSettings;
import 'package:flutter_video_editor/core/models/shader_clip_model.dart';
import 'package:flutter_video_editor/core/services/project_storage_service.dart';
import 'package:flutter_video_editor/features/editor/controllers/playback_controller.dart';
import 'package:flutter_video_editor/features/editor/controllers/track_controller.dart';
import 'package:flutter_video_editor/features/export/models/export_settings.dart';
import 'package:flutter_video_editor/features/export/models/timeline_dto.dart';
import 'package:flutter_video_editor/features/export/services/export_service.dart';

class EditorController extends ChangeNotifier {
  EditorController({PlaybackController? playbackController}) {
    _playback = playbackController ?? PlaybackController(onTimeUpdate: notifyListeners);
    _project = VideoProject(
      id: 'proj_${DateTime.now().millisecondsSinceEpoch}',
      name: 'New Project',
      clips: <TimelineClip>[],
    );
    _selectedClipId = null;
  }

  late final PlaybackController _playback;
  final TrackController _track = TrackController();

  late VideoProject _project;

  String? _selectedClipId;
  ExportSettings _exportSettings = const ExportSettings();
  bool _isExporting = false;
  double _exportProgress = 0.0;
  bool _isCameraActive = false;

  bool _isEyedropperActive = false;
  Completer<Color?>? _eyedropperCompleter;

  ValueNotifier<Duration> get playheadListenable => _playback.playheadListenable;

  // Vector Drawing State
  List<DrawingStroke> _activeDrawingStrokes = <DrawingStroke>[];
  Color _drawingColor = Colors.purpleAccent;
  double _strokeWidth = 4.0;

  // Undo / Redo Stacks
  final List<List<TimelineClip>> _undoStack = <List<TimelineClip>>[];
  final List<List<TimelineClip>> _redoStack = <List<TimelineClip>>[];

  // Undo coalescing: a slider or trim drag fires dozens of updates a second.
  // They collapse into ONE undo step instead of flooding the 25-step stack.
  String? _coalesceKey;
  DateTime? _coalesceAt;
  static const Duration _coalesceWindow = Duration(milliseconds: 800);

  // Autosave is debounced so drags do not hit the disk on every frame.
  Timer? _saveTimer;
  static const Duration _saveDelay = Duration(milliseconds: 600);

  VideoProject get project => _project;

  void loadProject(VideoProject project) {
    _playback.reset();
    _project = project;
    _selectedClipId = project.clips.isNotEmpty ? project.clips.first.id : null;
    _undoStack.clear();
    _redoStack.clear();
    _autosave();
    notifyListeners();
  }

  void updateSelectedClipSpeed(double speed) {
    if (_selectedClipId == null) return;

    final index = _project.clips.indexWhere(
      (TimelineClip clip) => clip.id == _selectedClipId,
    );
    if (index == -1) return;

    _saveStateCoalesced('speed:$_selectedClipId');
    final double newSpeed = speed.clamp(0.1, 10.0).toDouble();
    _project.clips[index] =
        _project.clips[index].copyWith(speed: newSpeed);
    _autosave();
    notifyListeners();
  }

  void setChromaKey(String clipId, ChromaKey chromaKey) {
    final index = _project.clips.indexWhere(
      (TimelineClip clip) => clip.id == clipId,
    );
    if (index == -1) return;

    _saveStateCoalesced('chroma:$clipId');
    _project.clips[index] =
        _project.clips[index].copyWith(chromaKey: chromaKey);
    _autosave();
    notifyListeners();
  }

  void addSvgElementClip(String svgContent, String label) {
    _saveState();
    final Duration start = playhead;
    final Duration end = playhead + const Duration(seconds: 5);
    final clip = TimelineClip(
      id: 'svg_${DateTime.now().millisecondsSinceEpoch}',
      label: label,
      start: start,
      end: end,
      clipType: ClipType.element,
      layerIndex: _freeOverlayLayer(3, start, end),
      elementProperties: ElementProperties(svgPath: svgContent),
    );

    _project.addClip(clip);
    _selectedClipId = clip.id;
    _autosave();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Shader Effects System Integration
  // ---------------------------------------------------------------------------
  void addShaderEffectToSelectedClip(ShaderEffectClip shaderEffect) {
    if (_selectedClipId == null) return;

    final index = _project.clips.indexWhere((c) => c.id == _selectedClipId);
    if (index == -1) return;

    _saveState();
    final updatedList = List<ShaderEffectClip>.from(_project.clips[index].shaderEffects)
      ..add(shaderEffect);

    _project.clips[index] = _project.clips[index].copyWith(
      shaderEffects: updatedList,
    );
    _autosave();
    notifyListeners();
  }

  void removeShaderEffectFromSelectedClip(String shaderEffectId) {
    if (_selectedClipId == null) return;

    final index = _project.clips.indexWhere((c) => c.id == _selectedClipId);
    if (index == -1) return;

    _saveState();
    final updatedList = List<ShaderEffectClip>.from(_project.clips[index].shaderEffects)
      ..removeWhere((e) => e.id == shaderEffectId);

    _project.clips[index] = _project.clips[index].copyWith(
      shaderEffects: updatedList,
    );
    _autosave();
    notifyListeners();
  }

  void updateShaderEffectParameters(String shaderEffectId, Map<String, dynamic> parameterValues) {
    if (_selectedClipId == null) return;

    final clipIndex = _project.clips.indexWhere((c) => c.id == _selectedClipId);
    if (clipIndex == -1) return;

    final effectIndex = _project.clips[clipIndex].shaderEffects.indexWhere((e) => e.id == shaderEffectId);
    if (effectIndex == -1) return;

    _saveStateCoalesced('shader:$shaderEffectId');
    final currentEffect = _project.clips[clipIndex].shaderEffects[effectIndex];
    final newValues = Map<String, dynamic>.from(currentEffect.parameterValues)
      ..addAll(parameterValues);

    final updatedEffect = currentEffect.copyWith(parameterValues: newValues);
    final updatedEffectsList = List<ShaderEffectClip>.from(_project.clips[clipIndex].shaderEffects);
    updatedEffectsList[effectIndex] = updatedEffect;

    _project.clips[clipIndex] = _project.clips[clipIndex].copyWith(
      shaderEffects: updatedEffectsList,
    );
    _autosave();
    notifyListeners();
  }

  void toggleShaderEffectEnabled(String shaderEffectId) {
    if (_selectedClipId == null) return;

    final clipIndex = _project.clips.indexWhere((c) => c.id == _selectedClipId);
    if (clipIndex == -1) return;

    final effectIndex = _project.clips[clipIndex].shaderEffects.indexWhere((e) => e.id == shaderEffectId);
    if (effectIndex == -1) return;

    _saveState();
    final currentEffect = _project.clips[clipIndex].shaderEffects[effectIndex];
    final updatedEffect = currentEffect.copyWith(isEnabled: !currentEffect.isEnabled);

    final updatedEffectsList = List<ShaderEffectClip>.from(_project.clips[clipIndex].shaderEffects);
    updatedEffectsList[effectIndex] = updatedEffect;

    _project.clips[clipIndex] = _project.clips[clipIndex].copyWith(
      shaderEffects: updatedEffectsList,
    );
    _autosave();
    notifyListeners();
  }

  void addShaderKeyframeToSelectedClip(
    String shaderEffectId,
    String parameterId,
    dynamic value,
    AnimationEasing easing,
  ) {
    if (_selectedClipId == null) return;

    final clipIndex = _project.clips.indexWhere((c) => c.id == _selectedClipId);
    if (clipIndex == -1) return;

    final clip = _project.clips[clipIndex];
    final effectIndex = clip.shaderEffects.indexWhere((e) => e.id == shaderEffectId);
    if (effectIndex == -1) return;

    _saveState();
    final shaderFx = clip.shaderEffects[effectIndex];
    final relativeTime = playhead - clip.start;

    final newKeyframe = ShaderKeyframe(
      id: 'skf_${DateTime.now().millisecondsSinceEpoch}',
      time: relativeTime,
      value: value,
      easing: easing,
    );

    final updatedAnimations = List<KeyframeAnimation>.from(shaderFx.keyframeAnimations);
    final animIndex = updatedAnimations.indexWhere((a) => a.parameterId == parameterId);

    if (animIndex != -1) {
      final existingAnim = updatedAnimations[animIndex];
      final newKfs = List<ShaderKeyframe>.from(existingAnim.keyframes)
        ..removeWhere((k) => (k.time - relativeTime).abs() < const Duration(milliseconds: 50))
        ..add(newKeyframe);
      updatedAnimations[animIndex] = existingAnim.copyWith(keyframes: newKfs);
    } else {
      updatedAnimations.add(KeyframeAnimation(
        id: 'kanim_${DateTime.now().millisecondsSinceEpoch}',
        parameterId: parameterId,
        keyframes: <ShaderKeyframe>[newKeyframe],
      ));
    }

    final updatedShaderFx = shaderFx.copyWith(keyframeAnimations: updatedAnimations);
    final updatedShaderList = List<ShaderEffectClip>.from(clip.shaderEffects);
    updatedShaderList[effectIndex] = updatedShaderFx;

    _project.clips[clipIndex] = clip.copyWith(shaderEffects: updatedShaderList);
    _autosave();
    notifyListeners();
  }

  void removeShaderKeyframeFromSelectedClip(
    String shaderEffectId,
    String parameterId,
    String keyframeId,
  ) {
    if (_selectedClipId == null) return;

    final clipIndex = _project.clips.indexWhere((c) => c.id == _selectedClipId);
    if (clipIndex == -1) return;

    final clip = _project.clips[clipIndex];
    final effectIndex = clip.shaderEffects.indexWhere((e) => e.id == shaderEffectId);
    if (effectIndex == -1) return;

    _saveState();
    final shaderFx = clip.shaderEffects[effectIndex];
    final updatedAnimations = List<KeyframeAnimation>.from(shaderFx.keyframeAnimations);
    final animIndex = updatedAnimations.indexWhere((a) => a.parameterId == parameterId);

    if (animIndex != -1) {
      final existingAnim = updatedAnimations[animIndex];
      final newKfs = List<ShaderKeyframe>.from(existingAnim.keyframes)
        ..removeWhere((k) => k.id == keyframeId);

      if (newKfs.isEmpty) {
        updatedAnimations.removeAt(animIndex);
      } else {
        updatedAnimations[animIndex] = existingAnim.copyWith(keyframes: newKfs);
      }
    }

    final updatedShaderFx = shaderFx.copyWith(keyframeAnimations: updatedAnimations);
    final updatedShaderList = List<ShaderEffectClip>.from(clip.shaderEffects);
    updatedShaderList[effectIndex] = updatedShaderFx;

    _project.clips[clipIndex] = clip.copyWith(shaderEffects: updatedShaderList);
    _autosave();
    notifyListeners();
  }

  Future<bool> tryRestoreRecoverySession() async {
    final recovered = await ProjectStorageService.instance.loadRecoveryState();
    if (recovered != null && recovered.clips.isNotEmpty) {
      loadProject(recovered);
      return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Autosave (debounced)
  // ---------------------------------------------------------------------------
  void _autosave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, _flushSave);
  }

  void _flushSave() {
    _saveTimer?.cancel();
    _saveTimer = null;
    ProjectStorageService.instance.saveProject(_project);
    ProjectStorageService.instance.saveRecoveryState(_project);
  }

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------
  Duration get playhead => _playback.playhead;
  bool get isPlaying => _playback.isPlaying;
  double get zoom => _playback.zoom;
  String? get selectedClipId => _selectedClipId;
  List<TimelineClip> get clips => _project.clips;
  ExportSettings get exportSettings => _exportSettings;
  bool get isExporting => _isExporting;
  double get exportProgress => _exportProgress;
  bool get isCameraActive => _isCameraActive;
  bool get isEyedropperActive => _isEyedropperActive;

  Future<Color?> pickColorFromFrame() async {
    _isEyedropperActive = true;
    _eyedropperCompleter = Completer<Color?>();
    notifyListeners();
    return _eyedropperCompleter!.future;
  }

  void completeEyedropper(Color? color) {
    if (_eyedropperCompleter != null && !_eyedropperCompleter!.isCompleted) {
      _eyedropperCompleter!.complete(color);
    }
    _eyedropperCompleter = null;
    _isEyedropperActive = false;
    notifyListeners();
  }

  void cancelEyedropper() {
    completeEyedropper(null);
  }

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
          playhead >= clip.start &&
          playhead <= clip.end) {
        return clip;
      }
    }
    return selectedClip;
  }

  // ---------------------------------------------------------------------------
  // Undo / Redo
  // ---------------------------------------------------------------------------
  void _saveState() {
    _coalesceKey = null;
    final snapshot = _project.clips.map((c) => c.copyWith()).toList();
    _undoStack.add(snapshot);
    if (_undoStack.length > 25) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  /// Like [_saveState], but repeated calls with the same [key] within a short
  /// window (a continuous drag) record only the first snapshot.
  void _saveStateCoalesced(String key) {
    final DateTime now = DateTime.now();
    if (_coalesceKey == key &&
        _coalesceAt != null &&
        now.difference(_coalesceAt!) < _coalesceWindow) {
      _coalesceAt = now;
      return;
    }
    _saveState();
    _coalesceKey = key;
    _coalesceAt = now;
  }

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void undo() {
    if (!canUndo) return;
    _coalesceKey = null;
    _redoStack.add(_project.clips.map((c) => c.copyWith()).toList());
    final previous = _undoStack.removeLast();
    _project.clips.clear();
    _project.clips.addAll(previous);
    _autosave();
    notifyListeners();
  }

  void redo() {
    if (!canRedo) return;
    _coalesceKey = null;
    _undoStack.add(_project.clips.map((c) => c.copyWith()).toList());
    final next = _redoStack.removeLast();
    _project.clips.clear();
    _project.clips.addAll(next);
    _autosave();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Layer helpers
  // ---------------------------------------------------------------------------
  bool _isOverlay(TimelineClip c) =>
      c.clipType != ClipType.audio &&
      (c.layerIndex > 0 ||
          (c.clipType != ClipType.video && c.clipType != ClipType.image));

  /// First overlay layer at or above [base] with no time overlap against
  /// [start]..[end], so two clips playing together never share one lane.
  int _freeOverlayLayer(int base, Duration start, Duration end) {
    return _track.freeOverlayLayer(_project.clips, base, start, end);
  }

  Duration _mainTrackEnd() {
    return _track.mainTrackEnd(_project.clips);
  }


  // ---------------------------------------------------------------------------
  // Clips
  // ---------------------------------------------------------------------------
  void addClip(TimelineClip clip) {
    _saveState();
    _project.addClip(clip);
    _selectedClipId = clip.id;
    _autosave();
    notifyListeners();
  }

  void addOverlayClip(String path) {
    _saveState();
    final lower = path.toLowerCase();
    final isVideo = lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.3gp') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.webm');

    final Duration start = playhead;
    final Duration end = playhead + const Duration(seconds: 5);
    final clip = TimelineClip(
      id: 'overlay_${DateTime.now().millisecondsSinceEpoch}',
      label: path.split(RegExp(r'[\\/]')).last,
      start: start,
      end: end,
      clipType: isVideo ? ClipType.video : ClipType.image,
      layerIndex: _freeOverlayLayer(1, start, end),
      sourcePath: path,
    );

    _project.addClip(clip);
    _selectedClipId = clip.id;
    _autosave();
    notifyListeners();
  }

  void selectClip(String? id) {
    if (_selectedClipId == id) return;
    _selectedClipId = id;
    notifyListeners();
  }

  /// Deselect every clip (tap on empty timeline space).
  void clearSelection() => selectClip(null);

  void setZoom(double value) {
    _playback.setZoom(value);
  }

  void setPlayhead(Duration value) {
    _playback.setPlayhead(value, _project.totalDuration);
  }

  void togglePlayback() {
    _playback.togglePlayback(() => _project.totalDuration);
  }

  void toggleCameraActive() {
    _isCameraActive = !_isCameraActive;
    notifyListeners();
  }

  void splitSelectedClip() {
    if (_selectedClipId == null) return;

    final existing = selectedClip;
    if (existing == null) return;

    if (playhead <= existing.start || playhead >= existing.end) return;

    _saveState();

    final splitOffset = playhead - existing.start;

    final left = existing.copyWith(
      id: '${existing.id}_part1',
      end: playhead,
      label: '${existing.label} (Part 1)',
      trimOut: existing.trimIn + splitOffset,
    );

    final right = existing.copyWith(
      id: '${existing.id}_part2',
      start: playhead,
      label: '${existing.label} (Part 2)',
      trimIn: existing.trimIn + splitOffset,
    );

    final index = _project.clips.indexOf(existing);
    _project.clips
      ..removeAt(index)
      ..insertAll(index, <TimelineClip>[left, right]);

    _selectedClipId = right.id;
    _autosave();
    notifyListeners();
  }

  void deleteSelectedClip() {
    if (_selectedClipId == null) return;
    _saveState();
    _project.removeClip(_selectedClipId!);
    // Nothing is selected afterwards; auto-selecting the first clip was
    // surprising and fought with tap-to-deselect.
    _selectedClipId = null;
    _autosave();
    notifyListeners();
  }

  void removeSelectedClip() {
    deleteSelectedClip();
  }

  void duplicateSelectedClip() {
    final current = selectedClip;
    if (current == null) return;
    _saveState();
    final Duration newStart = current.end;
    final Duration newEnd = current.end + current.duration;
    final copy = current.copyWith(
      id: 'clip_${DateTime.now().millisecondsSinceEpoch}',
      start: newStart,
      end: newEnd,
      layerIndex: _isOverlay(current)
          ? _freeOverlayLayer(current.layerIndex, newStart, newEnd)
          : current.layerIndex,
    );
    _project.addClip(copy);
    _selectedClipId = copy.id;
    _autosave();
    notifyListeners();
  }

  void addMediaClip(String path) {
    _saveState();
    final lower = path.toLowerCase();
    final isVideo = lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.3gp') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.webm');
    // Media is appended to the end of the main track so it can never overlap
    // an existing clip (the timeline assumes a gap-free, non-overlapping row).
    final Duration start = _mainTrackEnd();
    final clip = TimelineClip(
      id: 'clip_${DateTime.now().millisecondsSinceEpoch}',
      label: path.split(RegExp(r'[\\/]')).last,
      start: start,
      end: start + const Duration(seconds: 5),
      clipType: isVideo ? ClipType.video : ClipType.image,
      sourcePath: path,
    );
    _project.addClip(clip);
    _selectedClipId = clip.id;
    _autosave();
    notifyListeners();
  }

  void trimSelectedClip(Duration trimStart, Duration trimEnd) {
    if (_selectedClipId == null) return;

    final index = _project.clips.indexWhere(
      (TimelineClip clip) => clip.id == _selectedClipId,
    );
    if (index == -1) return;

    final existing = _project.clips[index];
    final startDelta = trimStart - existing.start;
    final endDelta = trimEnd - existing.end;

    final calculatedTrimIn = existing.trimIn + startDelta;
    final newTrimIn = calculatedTrimIn >= Duration.zero ? calculatedTrimIn : Duration.zero;
    final newTrimOut = existing.trimOut + endDelta;

    _saveStateCoalesced('trim:$_selectedClipId');
    _project.clips[index] = existing.copyWith(
      start: trimStart,
      end: trimEnd,
      trimIn: newTrimIn,
      trimOut: newTrimOut,
    );
    _autosave();
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
    _autosave();
    notifyListeners();
  }

  void toggleClipLock(String id) {
    final index = _project.clips.indexWhere((c) => c.id == id);
    if (index == -1) return;
    _project.clips[index] = _project.clips[index].copyWith(
      isLocked: !_project.clips[index].isLocked,
    );
    _autosave();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Text & Fonts
  // ---------------------------------------------------------------------------
  void addTextOverlay(
    String text, {
    String fontFamily = 'Poppins',
    TextAnimationStyle animationStyle = TextAnimationStyle.fadeIn,
  }) {
    _saveState();
    final Duration start = playhead;
    final Duration end = playhead + const Duration(seconds: 4);
    final clip = TimelineClip(
      id: 'text_${DateTime.now().millisecondsSinceEpoch}',
      label: text,
      start: start,
      end: end,
      clipType: ClipType.text,
      layerIndex: _freeOverlayLayer(2, start, end),
      fontFamily: fontFamily,
      textAnimationStyle: animationStyle,
      effect: VideoEffect.vibrant,
    );

    _project.addClip(clip);
    _selectedClipId = clip.id;
    _autosave();
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

    _saveStateCoalesced('textstyle:${current.id}');
    final index = _project.clips.indexWhere((c) => c.id == current.id);
    if (index != -1) {
      _project.clips[index] = _project.clips[index].copyWith(
        textStyle: properties,
      );
      _autosave();
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
      _autosave();
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

    _saveStateCoalesced('textprops:${current.id}');
    final index = _project.clips.indexWhere((c) => c.id == current.id);
    if (index == -1) return;
    _project.clips[index] = _project.clips[index].copyWith(
      label: text ?? current.label,
      fontFamily: fontFamily ?? current.fontFamily,
      textAnimationStyle: textAnimationStyle ?? current.textAnimationStyle,
      textStyle: textStyle ?? current.textStyle,
    );
    _autosave();
    notifyListeners();
  }

  void uploadCustomFont(String fontName) {
    if (!_project.customFonts.contains(fontName)) {
      _project.customFonts.add(fontName);
      _autosave();
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Elements & Objects
  // ---------------------------------------------------------------------------
  void addElementClip(
    ElementShape shape, {
    String label = 'Element',
    Color color = Colors.white,
  }) {
    _saveState();
    final Duration start = playhead;
    final Duration end = playhead + const Duration(seconds: 5);
    final clip = TimelineClip(
      id: 'elem_${DateTime.now().millisecondsSinceEpoch}',
      label: '$label (${shape.name})',
      start: start,
      end: end,
      clipType: ClipType.element,
      layerIndex: _freeOverlayLayer(3, start, end),
      elementProperties: ElementProperties(
        shape: shape,
        fillColor: color,
      ),
    );

    _project.addClip(clip);
    _selectedClipId = clip.id;
    _autosave();
    notifyListeners();
  }

  void updateElementProperties(ElementProperties elementProperties) {
    if (_selectedClipId == null) return;
    final index = _project.clips.indexWhere((c) => c.id == _selectedClipId);
    if (index == -1) return;

    _saveStateCoalesced('element:$_selectedClipId');
    _project.clips[index] = _project.clips[index].copyWith(
      elementProperties: elementProperties,
    );
    _autosave();
    notifyListeners();
  }

  // Camera Settings
  void updateCameraProperties(CameraProperties cameraProperties) {
    if (_selectedClipId == null) return;
    final index = _project.clips.indexWhere((c) => c.id == _selectedClipId);
    if (index == -1) return;

    _saveStateCoalesced('camera:$_selectedClipId');
    _project.clips[index] = _project.clips[index].copyWith(
      cameraProperties: cameraProperties,
    );
    _autosave();
    notifyListeners();
  }

  // Masking
  void updateMaskProperties(MaskProperties maskProperties) {
    if (_selectedClipId == null) return;
    final index = _project.clips.indexWhere((c) => c.id == _selectedClipId);
    if (index == -1) return;

    _saveStateCoalesced('mask:$_selectedClipId');
    _project.clips[index] = _project.clips[index].copyWith(
      maskProperties: maskProperties,
    );
    _autosave();
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
    _autosave();
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
    _autosave();
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

    _saveStateCoalesced('xform:$_selectedClipId');
    _project.clips[index] = _project.clips[index].copyWith(
      positionX: positionX ?? _project.clips[index].positionX,
      positionY: positionY ?? _project.clips[index].positionY,
      scale: scale ?? _project.clips[index].scale,
      rotation: rotation ?? _project.clips[index].rotation,
      opacity: opacity ?? _project.clips[index].opacity,
      anchorX: anchorX ?? _project.clips[index].anchorX,
      anchorY: anchorY ?? _project.clips[index].anchorY,
    );
    _autosave();
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
    _autosave();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Multilayer & Reordering
  // ---------------------------------------------------------------------------

  /// Raw setter kept for compatibility. Prefer [moveClipLayer] for UI.
  void reorderClipLayer(String clipId, int newLayerIndex) {
    final index = _project.clips.indexWhere((c) => c.id == clipId);
    if (index == -1) return;

    _saveState();
    _project.clips[index] = _project.clips[index].copyWith(
      layerIndex: newLayerIndex,
    );
    _autosave();
    notifyListeners();
  }

  /// Whether the lane holding [clipId] can move one step up (or down).
  bool canMoveClipLayer(String clipId, {required bool up}) {
    return _track.canMoveClipLayer(_project.clips, clipId, up: up);
  }

  void moveClipLayer(String clipId, {required bool up, bool toEdge = false}) {
    if (!canMoveClipLayer(clipId, up: up)) return;
    _saveState();
    _track.moveClipLayer(_project.clips, clipId, up: up, toEdge: toEdge);
    _autosave();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Effects & Color Grading
  // ---------------------------------------------------------------------------
  void applyEffect(VideoEffect effect) {
    if (_selectedClipId == null) return;

    final index = _project.clips.indexWhere(
      (TimelineClip clip) => clip.id == _selectedClipId,
    );
    if (index == -1) return;

    _saveState();
    _project.clips[index] = _project.clips[index].copyWith(effect: effect);
    _autosave();
    notifyListeners();
  }

  void updateColorGrading(ColorGradingSettings colorGrading) {
    if (_selectedClipId == null) return;

    final index = _project.clips.indexWhere(
      (TimelineClip clip) => clip.id == _selectedClipId,
    );
    if (index == -1) return;

    _saveStateCoalesced('grade:$_selectedClipId');
    _project.clips[index] =
        _project.clips[index].copyWith(colorGrading: colorGrading);
    _autosave();
    notifyListeners();
  }

  // Audio Tools & Multi-layer
  void addAudioTrack(String sourcePath, {String? trackName, double volume = 1.0, Duration? duration}) {
    _saveState();
    final name = trackName ?? sourcePath.split(RegExp(r'[\\/]')).last;
    final clip = TimelineClip(
      id: 'audio_${DateTime.now().millisecondsSinceEpoch}',
      label: name,
      start: playhead,
      end: playhead + (duration ?? const Duration(seconds: 10)),
      clipType: ClipType.audio,
      layerIndex: 1,
      volume: volume,
      sourcePath: sourcePath,
      audioProperties: AudioProperties(volume: volume),
    );

    _project.addClip(clip);
    _selectedClipId = clip.id;
    _autosave();
    notifyListeners();
  }

  void updateAudioProperties(AudioProperties audioProperties) {
    if (_selectedClipId == null) return;

    final index = _project.clips.indexWhere(
      (TimelineClip clip) => clip.id == _selectedClipId,
    );
    if (index == -1) return;

    _saveStateCoalesced('audio:$_selectedClipId');
    _project.clips[index] = _project.clips[index].copyWith(
      audioProperties: audioProperties,
      volume: audioProperties.volume,
      speed: audioProperties.speed,
    );
    _autosave();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Vector Drawing Tools
  // ---------------------------------------------------------------------------
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

    final Duration start = playhead;
    final Duration end = playhead + const Duration(seconds: 5);
    final clip = TimelineClip(
      id: 'drawing_${DateTime.now().millisecondsSinceEpoch}',
      label:
          'Vector Drawing ${_project.clips.where((c) => c.clipType == ClipType.drawing).length + 1}',
      start: start,
      end: end,
      clipType: ClipType.drawing,
      layerIndex: _freeOverlayLayer(3, start, end),
      strokes: List<DrawingStroke>.from(_activeDrawingStrokes),
    );

    _project.addClip(clip);
    _activeDrawingStrokes = <DrawingStroke>[];
    _selectedClipId = clip.id;
    _autosave();
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
    _autosave();
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
      _autosave();
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
        layerIndex: _freeOverlayLayer(4, cue.start, cue.end),
        fontFamily: 'Poppins',
      );
      _project.addClip(clip);
    }

    _autosave();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Export pipeline
  // ---------------------------------------------------------------------------
  void updateExportSettings(ExportSettings settings) {
    _exportSettings = settings;
    notifyListeners();
  }

  Future<String?> startExport({Function? onComplete}) async {
    // Make sure the latest edits are on disk and playback is not competing
    // with the encoder.
    if (isPlaying) togglePlayback();
    if (_saveTimer?.isActive ?? false) _flushSave();

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
    _playback.reset();
    _selectedClipId = null;
    _activeDrawingStrokes.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _playback.dispose();
    if (_saveTimer?.isActive ?? false) _flushSave();
    super.dispose();
  }
}