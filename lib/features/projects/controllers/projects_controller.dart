import 'package:flutter/material.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/core/services/project_storage_service.dart';

class ProjectsController extends ChangeNotifier {
  ProjectsController() {
    _loadProjectsFromStorage();
  }

  final List<Project> _projects = <Project>[];
  bool _isLoading = false;

  List<Project> get projects => List<Project>.unmodifiable(_projects);
  bool get isLoading => _isLoading;

  Future<void> _loadProjectsFromStorage() async {
    _isLoading = true;
    notifyListeners();
    final loaded = await ProjectStorageService.instance.loadAllProjects();
    _projects.clear();
    _projects.addAll(loaded);
    _isLoading = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    await _loadProjectsFromStorage();
  }

  Project createProject({
    String? name,
    AspectRatioPreset aspectRatio = AspectRatioPreset.nineSixteen,
    List<TimelineClip>? clips,
  }) {
    final id = 'proj_${DateTime.now().millisecondsSinceEpoch}';
    final project = Project(
      id: id,
      name: name ?? 'New Project ${_projects.length + 1}',
      aspectRatio: aspectRatio,
      clips: clips,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _projects.insert(0, project);
    ProjectStorageService.instance.saveProject(project);
    notifyListeners();
    return project;
  }

  void renameProject(String id, String newName) {
    final index = _projects.indexWhere((p) => p.id == id);
    if (index != -1) {
      final updated = _projects[index].copyWith(
        name: newName,
        updatedAt: DateTime.now(),
      );
      _projects[index] = updated;
      ProjectStorageService.instance.saveProject(updated);
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
      ProjectStorageService.instance.saveProject(duplicated);
      notifyListeners();
      return duplicated;
    }
    return null;
  }

  void deleteProject(String id) {
    _projects.removeWhere((p) => p.id == id);
    ProjectStorageService.instance.deleteProject(id);
    notifyListeners();
  }

  void saveProject(Project updatedProject) {
    final updated = updatedProject.copyWith(updatedAt: DateTime.now());
    final index = _projects.indexWhere((p) => p.id == updated.id);
    if (index != -1) {
      _projects[index] = updated;
    } else {
      _projects.insert(0, updated);
    }
    ProjectStorageService.instance.saveProject(updated);
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
