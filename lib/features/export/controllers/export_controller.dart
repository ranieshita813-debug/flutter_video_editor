import 'dart:async';
import 'package:flutter/material.dart';

import 'package:flutter_video_editor/core/models/project_model.dart' hide ExportSettings;
import 'package:flutter_video_editor/features/export/models/export_settings.dart';
import 'package:flutter_video_editor/features/export/models/timeline_dto.dart';
import 'package:flutter_video_editor/features/export/services/export_service.dart';

enum ExportStatus {
  idle,
  preparing,
  exporting,
  done,
  failed,
  cancelled,
}

class ExportController extends ChangeNotifier {
  ExportController({ExportService? exportService})
      : _exportService = exportService ?? ExportService() {
    _subscription = _exportService.progressStream.listen(_onProgressEvent, onError: _onProgressError);
  }

  final ExportService _exportService;
  StreamSubscription<Map<String, dynamic>>? _subscription;

  ExportStatus _status = ExportStatus.idle;
  double _progress = 0.0;
  String _stage = '';
  String? _outputPath;
  String? _errorMessage;
  ExportSettings _exportSettings = const ExportSettings();

  ExportStatus get status => _status;
  bool get isExporting => _status == ExportStatus.preparing || _status == ExportStatus.exporting;
  double get progress => _progress;
  String get stage => _stage;
  String? get outputPath => _outputPath;
  String? get errorMessage => _errorMessage;
  ExportSettings get exportSettings => _exportSettings;

  void updateSettings(ExportSettings settings) {
    _exportSettings = settings;
    notifyListeners();
  }

  void _onProgressEvent(Map<String, dynamic> data) {
    if (_status == ExportStatus.cancelled || _status == ExportStatus.failed) return;

    final p = (data['progress'] as num?)?.toDouble() ?? 0.0;
    final s = (data['stage'] as String?) ?? '';

    _progress = p.clamp(0.0, 1.0);
    _stage = s;
    if (_status == ExportStatus.preparing && p > 0.0) {
      _status = ExportStatus.exporting;
    }
    notifyListeners();
  }

  void _onProgressError(dynamic error) {
    _status = ExportStatus.failed;
    _errorMessage = error.toString();
    notifyListeners();
  }

  Future<String?> startExport(Project project, [ExportSettings? settings]) async {
    if (settings != null) {
      _exportSettings = settings;
    }

    _status = ExportStatus.preparing;
    _progress = 0.0;
    _stage = 'Preparing timeline...';
    _outputPath = null;
    _errorMessage = null;
    notifyListeners();

    try {
      final dto = TimelineDto.fromProject(project, _exportSettings);
      _status = ExportStatus.exporting;
      notifyListeners();

      final resultPath = await _exportService.exportTimeline(dto.toJson());

      if (_status != ExportStatus.cancelled) {
        _status = ExportStatus.done;
        _progress = 1.0;
        _stage = 'Completed';
        _outputPath = resultPath;
        notifyListeners();
        return resultPath;
      }
    } catch (e) {
      if (_status != ExportStatus.cancelled) {
        _status = ExportStatus.failed;
        _errorMessage = e.toString();
        notifyListeners();
      }
    }
    return null;
  }

  Future<void> cancelExport() async {
    if (!isExporting) return;
    _status = ExportStatus.cancelled;
    _stage = 'Cancelled';
    notifyListeners();
    await _exportService.cancelExport();
  }

  Future<Map<String, dynamic>> probe(String path) {
    return _exportService.probe(path);
  }

  Future<List<String>> thumbnails(String path, int count, int height) {
    return _exportService.thumbnails(path, count, height);
  }

  Future<List<double>> waveform(String path, int buckets) {
    return _exportService.waveform(path, buckets);
  }

  void resetStatus() {
    _status = ExportStatus.idle;
    _progress = 0.0;
    _stage = '';
    _outputPath = null;
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _exportService.dispose();
    super.dispose();
  }
}
