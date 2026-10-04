import 'package:flutter/material.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';

class EditorController extends ChangeNotifier {
  EditorController() {
    _project = VideoProject(
      projectName: 'motionGr Pro Studio',
      clips: <TimelineClip>[
        TimelineClip(
          id: 'clip_1',
          label: 'Main Camera Shot',
          start: Duration.zero,
          end: const Duration(seconds: 8),
          clipType: ClipType.video,
          layerIndex: 0,
          effect: VideoEffect.cinematic,
          colorGrading: const ColorGradingSettings(
            brightness: 0.1,
            contrast: 1.15,
            saturation: 1.2,
            temperature: 0.05,
          ),
        ),
        TimelineClip(
          id: 'clip_2',
          label: 'B-Roll Cut',
          start: const Duration(seconds: 8),
          end: const Duration(seconds: 16),
          clipType: ClipType.video,
          layerIndex: 0,
          effect: VideoEffect.warm,
        ),
        TimelineClip(
          id: 'clip_3',
          label: 'Background Music Track',
          start: Duration.zero,
          end: const Duration(seconds: 16),
          clipType: ClipType.audio,
          layerIndex: 1,
          audioProperties: const AudioProperties(volume: 0.7, pitch: 1.0),
        ),
        TimelineClip(
          id: 'clip_4',
          label: 'Title Overlay',
          start: const Duration(seconds: 1),
          end: const Duration(seconds: 5),
          clipType: ClipType.text,
          layerIndex: 2,
          fontFamily: 'Montserrat',
          textAnimationStyle: TextAnimationStyle.typewriter,
        ),
      ],
    );

    _selectedClipId = 'clip_1';
  }

  late VideoProject _project;

  Duration _playhead = Duration.zero;
  bool _isPlaying = false;
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
  void addTextOverlay(String text, {String fontFamily = 'Roboto', TextAnimationStyle animationStyle = TextAnimationStyle.fadeIn}) {
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

  void updateSelectedTextProperties({String? text, String? fontFamily, TextAnimationStyle? textAnimationStyle}) {
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
    _project.clips[index] = _project.clips[index].copyWith(colorGrading: colorGrading);
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
      label: 'Vector Drawing ${_project.clips.where((c) => c.clipType == ClipType.drawing).length + 1}',
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
    _project.clips[index] = _project.clips[index].copyWith(trackingData: trackingData);
    notifyListeners();
  }

  // Auto Captions Generator
  void generateAutoCaptions() {
    _saveState();
    _project.captions.clear();

    final sampleCaptions = <CaptionCue>[
      CaptionCue(
        id: 'cap_1',
        start: const Duration(seconds: 0),
        end: const Duration(seconds: 3),
        text: 'Welcome to motionGr Video Editor Pro!',
      ),
      CaptionCue(
        id: 'cap_2',
        start: const Duration(seconds: 3),
        end: const Duration(seconds: 7),
        text: 'Create stunning cinematic videos easily.',
      ),
      CaptionCue(
        id: 'cap_3',
        start: const Duration(seconds: 7),
        end: const Duration(seconds: 12),
        text: 'Includes custom fonts, vector tools, and fast export.',
      ),
    ];

    _project.captions.addAll(sampleCaptions);

    for (final cue in sampleCaptions) {
      final clip = TimelineClip(
        id: 'caption_${cue.id}',
        label: 'CC: ${cue.text}',
        start: cue.start,
        end: cue.end,
        clipType: ClipType.caption,
        layerIndex: 4,
        fontFamily: 'Roboto',
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

  Future<void> startExport({required VoidCallback onComplete}) async {
    _isExporting = true;
    _exportProgress = 0.0;
    notifyListeners();

    for (int i = 1; i <= 100; i++) {
      await Future.delayed(const Duration(milliseconds: 25));
      _exportProgress = i / 100.0;
      notifyListeners();
    }

    _isExporting = false;
    notifyListeners();
    onComplete();
  }

  void reset() {
    _playhead = Duration.zero;
    _isPlaying = false;
    _selectedClipId = null;
    _zoom = 1.0;
    _activeDrawingStrokes.clear();
    notifyListeners();
  }
}
