import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'package:flutter_video_editor/core/logger/app_logger.dart';
import 'package:flutter_video_editor/core/models/chroma_key.dart';
import 'package:flutter_video_editor/core/models/project_model.dart' hide ExportSettings;
import 'package:flutter_video_editor/core/models/shader_clip_model.dart';
import 'package:flutter_video_editor/core/services/caption_import_service.dart';
import 'package:flutter_video_editor/core/services/project_storage_service.dart';
import 'package:flutter_video_editor/core/services/translation_service.dart';
import 'package:flutter_video_editor/core/services/whisper_service.dart';
import 'package:flutter_video_editor/features/editor/controllers/playback_controller.dart';
import 'package:flutter_video_editor/features/editor/controllers/track_controller.dart';
import 'package:flutter_video_editor/features/editor/utils/editor_helpers.dart';
import 'package:flutter_video_editor/features/export/controllers/export_controller.dart';
import 'package:flutter_video_editor/features/export/models/export_settings.dart';
import 'package:flutter_video_editor/features/export/models/timeline_dto.dart';
import 'package:flutter_video_editor/features/export/services/export_service.dart';

class EditorController extends ChangeNotifier {
  EditorController() {
    _playback = PlaybackController(onTimeUpdate: notifyListeners);
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
  ExportStatus _exportStatus = ExportStatus.idle;
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

  final TranslationService _translationService = TranslationService();

  /// Translates caption clips into [targetLanguage].
  Future<void> translateCaptions({
    required String targetLanguage,
    bool allCaptions = true,
    TranslationService? translationService,
  }) async {
    _saveState();

    final service = translationService ?? _translationService;

    final List<TimelineClip> targets = <TimelineClip>[];
    if (allCaptions) {
      targets.addAll(_project.clips.where((c) => c.clipType == ClipType.caption));
    } else if (selectedClip != null && selectedClip!.clipType == ClipType.caption) {
      targets.add(selectedClip!);
    }

    for (final clip in targets) {
      final newText = await service.translateText(clip.label, targetLanguage);
      final words = newText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      final totalMs = clip.duration.inMilliseconds;
      final msPerWord = words.isNotEmpty ? totalMs / words.length : totalMs;

      final List<CaptionWord> newWords = <CaptionWord>[];
      for (int i = 0; i < words.length; i++) {
        final wStart = clip.start + Duration(milliseconds: (i * msPerWord).round());
        final wEnd = (i == words.length - 1)
            ? clip.end
            : clip.start + Duration(milliseconds: ((i + 1) * msPerWord).round());
        newWords.add(CaptionWord(
          word: words[i],
          start: wStart,
          end: wEnd,
        ));
      }

      final updatedClip = clip.copyWith(
        label: newText,
        words: newWords,
      );

      final clipIndex = _project.clips.indexWhere((c) => c.id == clip.id);
      if (clipIndex != -1) {
        _project.clips[clipIndex] = updatedClip;
      }

      final cueIndex = _project.captions.indexWhere(
        (c) => c.id == clip.id || 'caption_${c.id}' == clip.id,
      );
      if (cueIndex != -1) {
        _project.captions[cueIndex] = _project.captions[cueIndex].copyWith(
          text: newText,
          words: newWords,
        );
      }
    }

    _autosave();
    notifyListeners();
  }

  void updateEffectParameter(String paramName, double value) {
    if (_selectedClipId == null) return;
    final index = _project.clips.indexWhere((c) => c.id == _selectedClipId);
    if (index == -1) return;

    _saveStateCoalesced('fxparam:$_selectedClipId:$paramName');
    final clip = _project.clips[index];
    if (clip.clipType == ClipType.caption) {
      for (int i = 0; i < _project.clips.length; i++) {
        if (_project.clips[i].clipType == ClipType.caption) {
          final c = _project.clips[i];
          final updatedParams = Map<String, double>.from(c.effectParameters);
          updatedParams[paramName] = value;
          _project.clips[i] = c.copyWith(effectParameters: updatedParams);
        }
      }
    } else {
      final updatedParams = Map<String, double>.from(clip.effectParameters);
      updatedParams[paramName] = value;
      _project.clips[index] = clip.copyWith(effectParameters: updatedParams);
    }
    _autosave();
    notifyListeners();
  }

  void updateEffectParameters(Map<String, double> params) {
    if (_selectedClipId == null) return;
    final index = _project.clips.indexWhere((c) => c.id == _selectedClipId);
    if (index == -1) return;

    _saveStateCoalesced('fxparams:$_selectedClipId');
    final clip = _project.clips[index];
    if (clip.clipType == ClipType.caption) {
      for (int i = 0; i < _project.clips.length; i++) {
        if (_project.clips[i].clipType == ClipType.caption) {
          final c = _project.clips[i];
          final updatedParams = Map<String, double>.from(c.effectParameters)..addAll(params);
          _project.clips[i] = c.copyWith(effectParameters: updatedParams);
        }
      }
    } else {
      final updatedParams = Map<String, double>.from(clip.effectParameters)..addAll(params);
      _project.clips[index] = clip.copyWith(effectParameters: updatedParams);
    }
    _autosave();
    notifyListeners();
  }

  void extractAudioFromSelectedClip() {
    final current = selectedClip;
    if (current == null || current.sourcePath == null) return;

    _saveState();
    final audioClip = TimelineClip(
      id: 'audio_extracted_${DateTime.now().millisecondsSinceEpoch}',
      label: 'Audio: ${current.label}',
      start: current.start,
      end: current.end,
      clipType: ClipType.audio,
      layerIndex: 1,
      sourcePath: current.sourcePath,
      volume: current.volume > 0 ? current.volume : 1.0,
      audioProperties: current.audioProperties,
    );

    final index = _project.clips.indexOf(current);
    _project.clips[index] = current.copyWith(
      volume: 0.0,
      audioProperties: current.audioProperties.copyWith(volume: 0.0),
    );
    _project.addClip(audioClip);
    _selectedClipId = audioClip.id;
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
    final currentClip = _project.clips[index];

    final double sourceDurationMs = currentClip.duration.inMilliseconds * currentClip.speed;
    final int newDurationMs = (sourceDurationMs / newSpeed).round().clamp(200, 86400000);
    final Duration newEnd = currentClip.start + Duration(milliseconds: newDurationMs);

    _project.clips[index] = currentClip.copyWith(
      speed: newSpeed,
      end: newEnd,
      audioProperties: currentClip.audioProperties.copyWith(speed: newSpeed),
    );
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

    final targetClip = _project.clips[index];
    final existing = targetClip.shaderEffects;
    if (existing.any((e) => e.id == shaderEffect.id)) return;

    _saveState();
    if (targetClip.clipType == ClipType.caption) {
      for (int i = 0; i < _project.clips.length; i++) {
        if (_project.clips[i].clipType == ClipType.caption) {
          final c = _project.clips[i];
          final updatedList = List<ShaderEffectClip>.from(c.shaderEffects)..add(shaderEffect);
          _project.clips[i] = c.copyWith(shaderEffects: updatedList);
        }
      }
    } else {
      final updatedList = List<ShaderEffectClip>.from(existing)..add(shaderEffect);
      _project.clips[index] = targetClip.copyWith(shaderEffects: updatedList);
    }
    _autosave();
    notifyListeners();
  }

  void removeShaderEffectFromSelectedClip(String shaderEffectId) {
    if (_selectedClipId == null) return;

    final index = _project.clips.indexWhere((c) => c.id == _selectedClipId);
    if (index == -1) return;

    final targetClip = _project.clips[index];
    _saveState();
    if (targetClip.clipType == ClipType.caption) {
      for (int i = 0; i < _project.clips.length; i++) {
        if (_project.clips[i].clipType == ClipType.caption) {
          final c = _project.clips[i];
          final updatedList = List<ShaderEffectClip>.from(c.shaderEffects)
            ..removeWhere((e) => e.id == shaderEffectId);
          _project.clips[i] = c.copyWith(shaderEffects: updatedList);
        }
      }
    } else {
      final updatedList = List<ShaderEffectClip>.from(targetClip.shaderEffects)
        ..removeWhere((e) => e.id == shaderEffectId);
      _project.clips[index] = targetClip.copyWith(shaderEffects: updatedList);
    }
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
  ExportStatus get exportStatus => _exportStatus;
  bool get isCameraActive => _isCameraActive;

  void resetExportStatus() {
    _isExporting = false;
    _exportProgress = 0.0;
    _exportStatus = ExportStatus.idle;
    notifyListeners();
  }
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

  String _resolveTargetClipId(String id) {
    if (id.endsWith('_adj') || id.endsWith('_ck') || id.endsWith('_fx')) {
      return id.substring(0, id.lastIndexOf('_'));
    }
    return id;
  }

  TimelineClip? get selectedClip {
    if (_selectedClipId == null) return null;
    final targetId = _resolveTargetClipId(_selectedClipId!);
    try {
      return _project.clips.firstWhere((clip) => clip.id == targetId);
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

  /// Calculates the end timestamp of all existing video/image clips on the timeline
  /// so new media (e.g. AI generated media) is placed right after existing media clips.
  Duration getEndOfExistingMediaClips() {
    Duration maxEnd = Duration.zero;
    for (final clip in _project.clips) {
      if (clip.clipType == ClipType.video || clip.clipType == ClipType.image) {
        if (clip.end > maxEnd) {
          maxEnd = clip.end;
        }
      }
    }
    if (maxEnd == Duration.zero) {
      maxEnd = _project.totalDuration;
    }
    return maxEnd;
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
    final id = _selectedClipId!;
    if (id.endsWith('_adj')) {
      final targetId = _resolveTargetClipId(id);
      final idx = _project.clips.indexWhere((c) => c.id == targetId);
      if (idx != -1) {
        _project.clips[idx] = _project.clips[idx].copyWith(
          colorGrading: const ColorGradingSettings(),
        );
      }
    } else if (id.endsWith('_ck')) {
      final targetId = _resolveTargetClipId(id);
      final idx = _project.clips.indexWhere((c) => c.id == targetId);
      if (idx != -1) {
        _project.clips[idx] = _project.clips[idx].copyWith(
          chromaKey: const ChromaKey(enabled: false),
        );
      }
    } else if (id.endsWith('_fx')) {
      final targetId = _resolveTargetClipId(id);
      final idx = _project.clips.indexWhere((c) => c.id == targetId);
      if (idx != -1) {
        _project.clips[idx] = _project.clips[idx].copyWith(
          effect: VideoEffect.none,
          shaderEffects: const [],
        );
      }
    } else {
      _project.removeClip(id);
    }
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

  bool _isAudioPath(String path) {
    final clean = path.toLowerCase().split('?').first;
    return (clean.startsWith('content://') && clean.contains('audio')) ||
        clean.endsWith('.mp3') ||
        clean.endsWith('.wav') ||
        clean.endsWith('.m4a') ||
        clean.endsWith('.aac') ||
        clean.endsWith('.flac') ||
        clean.endsWith('.ogg') ||
        clean.endsWith('.wma') ||
        clean.endsWith('.opus') ||
        clean.endsWith('.amr') ||
        clean.endsWith('.oga') ||
        clean.endsWith('.mid') ||
        clean.endsWith('.midi');
  }

  void addMediaClip(String path) {
    if (_isAudioPath(path)) {
      addAudioTrack(path);
      return;
    }

    _saveState();
    final lower = path.toLowerCase();
    final isVideo = !lower.endsWith('.jpg') &&
        !lower.endsWith('.jpeg') &&
        !lower.endsWith('.png') &&
        !lower.endsWith('.webp') &&
        !lower.endsWith('.heic') &&
        !lower.endsWith('.gif');

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

    final targetId = _resolveTargetClipId(_selectedClipId!);
    final index = _project.clips.indexWhere(
      (TimelineClip clip) => clip.id == targetId,
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

  void updateTransitionForSelectedClip(String transitionType, int durationMs) {
    if (_selectedClipId == null) return;
    final index = _project.clips.indexWhere((c) => c.id == _selectedClipId);
    if (index == -1) return;

    _saveState();
    _project.clips[index] = _project.clips[index].copyWith(
      transitionType: transitionType,
      transitionDurationMs: durationMs,
    );
    _autosave();
    notifyListeners();
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
    String fontFamily = 'Ubuntu Sans',
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
      'Ubuntu Sans',
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
    if (current.clipType == ClipType.caption) {
      applyCaptionStyleToAll(properties);
      return;
    }
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

    if (current.clipType == ClipType.caption) {
      for (int i = 0; i < _project.clips.length; i++) {
        if (_project.clips[i].clipType == ClipType.caption) {
          final c = _project.clips[i];
          _project.clips[i] = c.copyWith(
            label: (c.id == current.id && text != null) ? text : c.label,
            fontFamily: fontFamily ?? c.fontFamily,
            textAnimationStyle: textAnimationStyle ?? c.textAnimationStyle,
            textStyle: textStyle ?? c.textStyle,
          );
        }
      }
    } else {
      _project.clips[index] = _project.clips[index].copyWith(
        label: text ?? current.label,
        fontFamily: fontFamily ?? current.fontFamily,
        textAnimationStyle: textAnimationStyle ?? current.textAnimationStyle,
        textStyle: textStyle ?? current.textStyle,
      );
    }
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
      ..removeWhere((k) => k.property == keyframe.property && (k.time.inMilliseconds - keyframe.time.inMilliseconds).abs() < 50)
      ..add(keyframe);

    _project.clips[index] = _project.clips[index].copyWith(
      keyframes: updatedKeyframes,
    );
    _autosave();
    notifyListeners();
  }

  void addKeyframeAtPlayhead([KeyframeProperty? property]) {
    if (_selectedClipId == null) return;
    final index = _project.clips.indexWhere((c) => c.id == _selectedClipId);
    if (index == -1) return;

    final clip = _project.clips[index];
    final relTime = playhead - clip.start;
    if (relTime.isNegative || relTime > clip.duration) return;

    _saveState();
    final updatedKeyframes = List<Keyframe>.from(clip.keyframes);
    final stamp = DateTime.now().millisecondsSinceEpoch;

    final propsToAdd = property != null
        ? <KeyframeProperty>[property]
        : <KeyframeProperty>[
            KeyframeProperty.positionX,
            KeyframeProperty.positionY,
            KeyframeProperty.scale,
            KeyframeProperty.rotation,
            KeyframeProperty.opacity,
            if (clip.clipType == ClipType.audio || clip.clipType == ClipType.video)
              KeyframeProperty.volume,
          ];

    for (int i = 0; i < propsToAdd.length; i++) {
      final p = propsToAdd[i];
      final double currentValue = switch (p) {
        KeyframeProperty.positionX => getInterpolatedKeyframeValue(clip, p, relTime, clip.positionX),
        KeyframeProperty.positionY => getInterpolatedKeyframeValue(clip, p, relTime, clip.positionY),
        KeyframeProperty.scale => getInterpolatedKeyframeValue(clip, p, relTime, clip.scale),
        KeyframeProperty.rotation => getInterpolatedKeyframeValue(clip, p, relTime, clip.rotation),
        KeyframeProperty.opacity => getInterpolatedKeyframeValue(clip, p, relTime, clip.opacity),
        KeyframeProperty.volume => getInterpolatedKeyframeValue(clip, p, relTime, clip.volume),
      };

      updatedKeyframes.removeWhere(
          (k) => k.property == p && (k.time.inMilliseconds - relTime.inMilliseconds).abs() < 100);
      updatedKeyframes.add(Keyframe(
        id: 'kf_${stamp}_$i',
        time: relTime,
        property: p,
        value: currentValue,
      ));
    }

    _project.clips[index] = clip.copyWith(keyframes: updatedKeyframes);
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
    final clip = _project.clips[index];

    if (clip.clipType == ClipType.caption) {
      for (int i = 0; i < _project.clips.length; i++) {
        if (_project.clips[i].clipType == ClipType.caption) {
          final c = _project.clips[i];
          _project.clips[i] = c.copyWith(
            positionX: positionX ?? c.positionX,
            positionY: positionY ?? c.positionY,
            scale: scale ?? c.scale,
            rotation: rotation ?? c.rotation,
            opacity: opacity ?? c.opacity,
            anchorX: anchorX ?? c.anchorX,
            anchorY: anchorY ?? c.anchorY,
          );
        }
      }
    } else {
      final relTime = playhead - clip.start;
      final bool hasKeyframes = clip.keyframes.isNotEmpty;
      final bool inRange = !relTime.isNegative && relTime <= clip.duration;

      if (hasKeyframes && inRange) {
        final updatedKeyframes = List<Keyframe>.from(clip.keyframes);
        final stamp = DateTime.now().millisecondsSinceEpoch;

        void updateOrAddKf(KeyframeProperty prop, double val) {
          updatedKeyframes.removeWhere((k) =>
              k.property == prop && (k.time.inMilliseconds - relTime.inMilliseconds).abs() < 100);
          updatedKeyframes.add(Keyframe(
            id: 'kf_${stamp}_${prop.name}',
            time: relTime,
            property: prop,
            value: val,
          ));
        }

        if (positionX != null) updateOrAddKf(KeyframeProperty.positionX, positionX);
        if (positionY != null) updateOrAddKf(KeyframeProperty.positionY, positionY);
        if (scale != null) updateOrAddKf(KeyframeProperty.scale, scale);
        if (rotation != null) updateOrAddKf(KeyframeProperty.rotation, rotation);
        if (opacity != null) updateOrAddKf(KeyframeProperty.opacity, opacity);

        _project.clips[index] = clip.copyWith(
          positionX: positionX ?? clip.positionX,
          positionY: positionY ?? clip.positionY,
          scale: scale ?? clip.scale,
          rotation: rotation ?? clip.rotation,
          opacity: opacity ?? clip.opacity,
          anchorX: anchorX ?? clip.anchorX,
          anchorY: anchorY ?? clip.anchorY,
          keyframes: updatedKeyframes,
        );
      } else {
        _project.clips[index] = clip.copyWith(
          positionX: positionX ?? clip.positionX,
          positionY: positionY ?? clip.positionY,
          scale: scale ?? clip.scale,
          rotation: rotation ?? clip.rotation,
          opacity: opacity ?? clip.opacity,
          anchorX: anchorX ?? clip.anchorX,
          anchorY: anchorY ?? clip.anchorY,
        );
      }
    }
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
    final current = _project.clips[index];
    if (current.clipType == ClipType.caption) {
      for (int i = 0; i < _project.clips.length; i++) {
        if (_project.clips[i].clipType == ClipType.caption) {
          final c = _project.clips[i];
          _project.clips[i] = c.copyWith(
            inAnimation: inAnimation ?? c.inAnimation,
            outAnimation: outAnimation ?? c.outAnimation,
            loopAnimation: loopAnimation ?? c.loopAnimation,
          );
        }
      }
    } else {
      _project.clips[index] = current.copyWith(
        inAnimation: inAnimation ?? current.inAnimation,
        outAnimation: outAnimation ?? current.outAnimation,
        loopAnimation: loopAnimation ?? current.loopAnimation,
      );
    }
    _autosave();
    notifyListeners();
  }

  void applyEffect(VideoEffect effect) {
    if (_selectedClipId == null) return;

    final index = _project.clips.indexWhere(
      (TimelineClip clip) => clip.id == _selectedClipId,
    );
    if (index == -1) return;

    _saveState();
    final current = _project.clips[index];
    if (current.clipType == ClipType.caption) {
      for (int i = 0; i < _project.clips.length; i++) {
        if (_project.clips[i].clipType == ClipType.caption) {
          _project.clips[i] = _project.clips[i].copyWith(effect: effect);
        }
      }
    } else {
      _project.clips[index] = current.copyWith(effect: effect);
    }
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
  // Color Grading
  // ---------------------------------------------------------------------------
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
    final clipId = 'audio_${DateTime.now().millisecondsSinceEpoch}';
    final initialDuration = duration ?? const Duration(seconds: 15);
    final clip = TimelineClip(
      id: clipId,
      label: name,
      start: playhead,
      end: playhead + initialDuration,
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

    if (duration == null || duration == Duration.zero) {
      _probeAudioDuration(clipId, sourcePath);
    }
  }

  Future<void> _probeAudioDuration(String clipId, String path) async {
    try {
      final meta = await ExportService().probe(path);
      final durMs = (meta['durationMs'] as num?)?.toInt() ?? 0;
      if (durMs > 0) {
        final idx = _project.clips.indexWhere((c) => c.id == clipId);
        if (idx != -1) {
          final clip = _project.clips[idx];
          _project.clips[idx] = clip.copyWith(
            end: clip.start + Duration(milliseconds: durMs),
          );
          _autosave();
          notifyListeners();
        }
      }
    } catch (e) {
      AppLogger.warning('Audio probe error for $path: $e', tag: 'EditorController');
    }
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
  void splitCaptionClip() {
    final current = selectedClip;
    if (current == null || (current.clipType != ClipType.caption && current.clipType != ClipType.text)) return;
    if (playhead <= current.start || playhead >= current.end) return;

    _saveState();
    final leftText = current.label;
    final rightText = current.label;

    final left = current.copyWith(
      id: '${current.id}_cap1',
      end: playhead,
      label: leftText,
    );

    final right = current.copyWith(
      id: '${current.id}_cap2',
      start: playhead,
      label: rightText,
    );

    final index = _project.clips.indexOf(current);
    _project.clips
      ..removeAt(index)
      ..insertAll(index, <TimelineClip>[left, right]);

    _selectedClipId = right.id;
    _autosave();
    notifyListeners();
  }

  void mergeNextCaptionClip() {
    final current = selectedClip;
    if (current == null || (current.clipType != ClipType.caption && current.clipType != ClipType.text)) return;

    final captions = _project.clips
        .where((c) => c.clipType == current.clipType && c.layerIndex == current.layerIndex)
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    final index = captions.indexWhere((c) => c.id == current.id);
    if (index == -1 || index >= captions.length - 1) return;

    final nextClip = captions[index + 1];
    _saveState();

    final mergedClip = current.copyWith(
      end: nextClip.end,
      label: '${current.label} ${nextClip.label}'.trim(),
    );

    _project.clips.removeWhere((c) => c.id == current.id || c.id == nextClip.id);
    _project.clips.add(mergedClip);
    _selectedClipId = mergedClip.id;

    _autosave();
    notifyListeners();
  }

  Future<void> generateAutoCaptions({String? language}) async {
    await generateWhisperCaptions(language: language);
  }

  /// Generates captions using OpenAI Whisper Large (v3) via Pollinations API.
  Future<void> generateWhisperCaptions({
    String? audioFilePath,
    WhisperService? whisperService,
    String? language,
  }) async {
    _saveState();
    _project.captions.clear();
    _project.clips.removeWhere((TimelineClip c) => c.clipType == ClipType.caption);

    String? path = audioFilePath ?? selectedClip?.sourcePath;
    if (path == null || path.isEmpty) {
      for (final clip in _project.clips) {
        if ((clip.clipType == ClipType.video || clip.clipType == ClipType.audio) &&
            clip.sourcePath != null &&
            clip.sourcePath!.isNotEmpty) {
          path = clip.sourcePath;
          break;
        }
      }
    }

    if (path == null || path.isEmpty) {
      throw Exception('No video or audio clip found on timeline to transcribe.');
    }

    String targetPath = path;
    if (path.startsWith('assets/')) {
      final byteData = await rootBundle.load(path);
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/${path.split('/').last}');
      await tempFile.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
      targetPath = tempFile.path;
    }

    final whisper = whisperService ?? WhisperService();
    final newCaptions = await whisper.transcribeAudio(
      audioFilePath: targetPath,
      language: language,
    );

    // Filter/clamp generated caption cues to the main clip(s) duration on timeline.
    final mainClips = _project.clips
        .where((c) => (c.clipType == ClipType.video || c.clipType == ClipType.image) && c.layerIndex == 0)
        .toList();

    List<CaptionCue> boundedCaptions = <CaptionCue>[];
    if (mainClips.isNotEmpty) {
      Duration mainStart = mainClips.first.start;
      Duration mainEnd = mainClips.first.end;
      for (final mc in mainClips) {
        if (mc.start < mainStart) mainStart = mc.start;
        if (mc.end > mainEnd) mainEnd = mc.end;
      }

      for (final cue in newCaptions) {
        if (cue.end <= mainStart || cue.start >= mainEnd) {
          continue; // Out of bounds of main clip(s)
        }
        final cueStart = cue.start < mainStart ? mainStart : cue.start;
        final cueEnd = cue.end > mainEnd ? mainEnd : cue.end;
        final clampedWords = cue.words
            .where((w) => w.end > cueStart && w.start < cueEnd)
            .toList();

        boundedCaptions.add(cue.copyWith(
          start: cueStart,
          end: cueEnd,
          words: clampedWords,
        ));
      }
    } else {
      boundedCaptions = newCaptions;
    }

    _project.captions.addAll(boundedCaptions);

    for (final cue in boundedCaptions) {
      final clip = TimelineClip(
        id: 'caption_${cue.id}',
        label: cue.text,
        start: cue.start,
        end: cue.end,
        clipType: ClipType.caption,
        layerIndex: _freeOverlayLayer(4, cue.start, cue.end),
        fontFamily: 'Ubuntu Sans',
        words: cue.words,
      );
      _project.addClip(clip);
    }

    _autosave();
    notifyListeners();
  }

  /// Imports a caption file (.srt, .vtt, .json) and adds cues to project.
  Future<int> importCaptionFile() async {
    final importer = CaptionImportService();
    final newCues = await importer.pickAndImportCaptionFile();
    if (newCues == null || newCues.isEmpty) return 0;

    _saveState();
    _project.captions.addAll(newCues);

    for (final cue in newCues) {
      final clip = TimelineClip(
        id: 'caption_${cue.id}',
        label: cue.text,
        start: cue.start,
        end: cue.end,
        clipType: ClipType.caption,
        layerIndex: _freeOverlayLayer(4, cue.start, cue.end),
        fontFamily: 'Ubuntu Sans',
        words: cue.words,
      );
      _project.addClip(clip);
    }

    _autosave();
    notifyListeners();
    return newCues.length;
  }

  void updateCaptionCue(CaptionCue updatedCue) {
    final idx = _project.captions.indexWhere((c) => c.id == updatedCue.id);
    if (idx != -1) {
      _project.captions[idx] = updatedCue;
    }

    final clipIdx = _project.clips.indexWhere(
      (c) => c.id == updatedCue.id || c.id == 'caption_${updatedCue.id}',
    );
    if (clipIdx != -1) {
      _project.clips[clipIdx] = _project.clips[clipIdx].copyWith(
        label: updatedCue.text,
        start: updatedCue.start,
        end: updatedCue.end,
        words: updatedCue.words,
      );
    }
    _autosave();
    notifyListeners();
  }

  void deleteCaptionCue(String cueId) {
    _saveState();
    _project.captions.removeWhere((c) => c.id == cueId);
    _project.clips.removeWhere((c) => c.id == cueId || c.id == 'caption_$cueId');
    _autosave();
    notifyListeners();
  }

  void addCaptionCue(CaptionCue cue) {
    _saveState();
    _project.captions.add(cue);
    final clip = TimelineClip(
      id: 'caption_${cue.id}',
      label: cue.text,
      start: cue.start,
      end: cue.end,
      clipType: ClipType.caption,
      layerIndex: _freeOverlayLayer(4, cue.start, cue.end),
      fontFamily: 'Ubuntu Sans',
      words: cue.words,
    );
    _project.addClip(clip);
    _selectedClipId = clip.id;
    _autosave();
    notifyListeners();
  }

  void applyCaptionStyleToAll(TextStyleProperties style) {
    _saveState();
    for (int i = 0; i < _project.clips.length; i++) {
      if (_project.clips[i].clipType == ClipType.caption) {
        _project.clips[i] = _project.clips[i].copyWith(textStyle: style);
      }
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
    _exportStatus = ExportStatus.exporting;
    notifyListeners();

    try {
      AppLogger.info('Starting timeline export for project ${_project.id}', tag: 'EditorController');
      final exportService = ExportService();
      final dto = TimelineDto.fromProject(_project, _exportSettings);
      final resultPath = await exportService.exportTimeline(dto.toJson());
      _isExporting = false;
      _exportProgress = 1.0;
      _exportStatus = ExportStatus.done;
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
      _exportStatus = ExportStatus.failed;
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