import 'package:flutter/material.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';

class ProjectsController extends ChangeNotifier {
  ProjectsController();

  final List<Project> _projects = <Project>[];

  List<Project> get projects => List<Project>.unmodifiable(_projects);

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
