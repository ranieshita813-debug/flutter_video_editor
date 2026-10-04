import 'package:flutter/material.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';

class ProjectsController extends ChangeNotifier {
  ProjectsController() {
    _loadSampleProjects();
  }

  final List<Project> _projects = <Project>[];

  List<Project> get projects => List<Project>.unmodifiable(_projects);

  void _loadSampleProjects() {
    final now = DateTime.now();
    _projects.addAll(<Project>[
      Project(
        id: 'proj_1',
        name: 'Cyberpunk Vlog 2025',
        aspectRatio: AspectRatioPreset.nineSixteen,
        resolution: ExportResolution.res1080p,
        thumbnail: 'assets/thumb_cyberpunk.png',
        createdAt: now.subtract(const Duration(days: 2)),
        updatedAt: now.subtract(const Duration(hours: 3)),
        clips: <TimelineClip>[
          TimelineClip(
            id: 'c1',
            label: 'Intro Shot',
            start: Duration.zero,
            end: const Duration(seconds: 5),
            clipType: ClipType.video,
          ),
          TimelineClip(
            id: 'c2',
            label: 'Main Beat Track',
            start: Duration.zero,
            end: const Duration(seconds: 15),
            clipType: ClipType.audio,
          ),
        ],
      ),
      Project(
        id: 'proj_2',
        name: 'Travel Reel - Tokyo',
        aspectRatio: AspectRatioPreset.nineSixteen,
        resolution: ExportResolution.res4k,
        thumbnail: 'assets/thumb_tokyo.png',
        createdAt: now.subtract(const Duration(days: 5)),
        updatedAt: now.subtract(const Duration(days: 1)),
        clips: <TimelineClip>[
          TimelineClip(
            id: 'c3',
            label: 'Shibuya Crossing',
            start: Duration.zero,
            end: const Duration(seconds: 12),
            clipType: ClipType.video,
          ),
        ],
      ),
      Project(
        id: 'proj_3',
        name: 'Product Showcase 16:9',
        aspectRatio: AspectRatioPreset.sixteenNine,
        resolution: ExportResolution.res1080p,
        thumbnail: 'assets/thumb_product.png',
        createdAt: now.subtract(const Duration(days: 10)),
        updatedAt: now.subtract(const Duration(days: 4)),
        clips: <TimelineClip>[
          TimelineClip(
            id: 'c4',
            label: 'Studio Angle 1',
            start: Duration.zero,
            end: const Duration(seconds: 20),
            clipType: ClipType.video,
          ),
        ],
      ),
    ]);
  }

  Project createProject({
    String? name,
    AspectRatioPreset aspectRatio = AspectRatioPreset.nineSixteen,
    List<TimelineClip>? clips,
  }) {
    final id = 'proj_${DateTime.now().millisecondsSinceEpoch}';
    final project = Project(
      id: id,
      name: name ?? 'New Project ${projects.length + 1}',
      aspectRatio: aspectRatio,
      clips: clips,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _projects.insert(0, project);
    notifyListeners();
    return project;
  }

  void renameProject(String id, String newName) {
    final index = _projects.indexWhere((p) => p.id == id);
    if (index != -1) {
      _projects[index] = _projects[index].copyWith(
        name: newName,
        updatedAt: DateTime.now(),
      );
      notifyListeners();
    }
  }

  Project? duplicateProject(String id) {
    final index = _projects.indexWhere((p) => p.id == id);
    if (index != -1) {
      final original = _projects[index];
      final duplicated = original.copyWith(
        id: 'proj_${DateTime.now().millisecondsSinceEpoch}',
        name: '${original.name} (Copy)',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      _projects.insert(index + 1, duplicated);
      notifyListeners();
      return duplicated;
    }
    return null;
  }

  void deleteProject(String id) {
    _projects.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  void saveProject(Project updatedProject) {
    final index = _projects.indexWhere((p) => p.id == updatedProject.id);
    if (index != -1) {
      _projects[index] = updatedProject.copyWith(updatedAt: DateTime.now());
    } else {
      _projects.insert(0, updatedProject.copyWith(updatedAt: DateTime.now()));
    }
    notifyListeners();
  }

  Project? getProject(String id) {
    try {
      return _projects.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }
}
