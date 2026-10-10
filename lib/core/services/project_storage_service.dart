import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter_video_editor/core/logger/app_logger.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';

class ProjectStorageService {
  ProjectStorageService._();
  static final ProjectStorageService instance = ProjectStorageService._();

  Directory? _projectsDir;

  Future<Directory> _getProjectsDirectory() async {
    if (_projectsDir != null && await _projectsDir!.exists()) {
      return _projectsDir!;
    }
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${docsDir.path}/motionGr_projects');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _projectsDir = dir;
      return dir;
    } catch (_) {
      final tempDir = Directory('${Directory.systemTemp.path}/motionGr_projects');
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }
      _projectsDir = tempDir;
      return tempDir;
    }
  }

  Future<List<Project>> loadAllProjects() async {
    try {
      final dir = await _getProjectsDirectory();
      final List<FileSystemEntity> entities = await dir.list().toList();
      final List<Project> projects = <Project>[];

      for (final entity in entities) {
        if (entity is File && entity.path.endsWith('.json') && !entity.path.contains('recovery_')) {
          try {
            final content = await entity.readAsString();
            final Map<String, dynamic> jsonMap = jsonDecode(content) as Map<String, dynamic>;
            projects.add(Project.fromJson(jsonMap));
          } catch (e, stack) {
            AppLogger.error('Failed to parse project file ${entity.path}', tag: 'ProjectStorage', error: e, stackTrace: stack);
          }
        }
      }

      projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return projects;
    } on MissingPluginException catch (_) {
      return <Project>[];
    } catch (e, stack) {
      AppLogger.error('Failed to load projects from storage', tag: 'ProjectStorage', error: e, stackTrace: stack);
      return <Project>[];
    }
  }

  Future<void> saveProject(Project project) async {
    try {
      final dir = await _getProjectsDirectory();
      final tempFile = File('${dir.path}/${project.id}.tmp');
      final targetFile = File('${dir.path}/${project.id}.json');
      final jsonMap = project.toJson();
      jsonMap['schemaVersion'] = 1;
      final jsonStr = jsonEncode(jsonMap);

      await tempFile.writeAsString(jsonStr, flush: true);
      await tempFile.rename(targetFile.path);
      AppLogger.info('Saved project ${project.id} to local storage atomically', tag: 'ProjectStorage');
    } on MissingPluginException catch (_) {
      // Ignored in test environment without native channel
    } catch (e, stack) {
      AppLogger.error('Failed to save project ${project.id}', tag: 'ProjectStorage', error: e, stackTrace: stack);
    }
  }

  Future<void> deleteProject(String projectId) async {
    try {
      final dir = await _getProjectsDirectory();
      final file = File('${dir.path}/$projectId.json');
      if (await file.exists()) {
        await file.delete();
        AppLogger.info('Deleted project $projectId from local storage', tag: 'ProjectStorage');
      }
    } on MissingPluginException catch (_) {
      // Ignored in test environment
    } catch (e, stack) {
      AppLogger.error('Failed to delete project $projectId', tag: 'ProjectStorage', error: e, stackTrace: stack);
    }
  }

  Future<void> saveRecoveryState(Project project) async {
    try {
      final dir = await _getProjectsDirectory();
      final tempFile = File('${dir.path}/recovery_active.tmp');
      final targetFile = File('${dir.path}/recovery_active.json');
      final jsonMap = project.toJson();
      jsonMap['schemaVersion'] = 1;
      final jsonStr = jsonEncode(jsonMap);

      await tempFile.writeAsString(jsonStr, flush: true);
      await tempFile.rename(targetFile.path);
    } on MissingPluginException catch (_) {
      // Ignored in test environment
    } catch (e, stack) {
      AppLogger.error('Failed to save recovery state', tag: 'ProjectStorage', error: e, stackTrace: stack);
    }
  }

  Future<Project?> loadRecoveryState() async {
    try {
      final dir = await _getProjectsDirectory();
      final file = File('${dir.path}/recovery_active.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final Map<String, dynamic> jsonMap = jsonDecode(content) as Map<String, dynamic>;
        return Project.fromJson(jsonMap);
      }
    } on MissingPluginException catch (_) {
      return null;
    } catch (e, stack) {
      AppLogger.error('Failed to load recovery state', tag: 'ProjectStorage', error: e, stackTrace: stack);
    }
    return null;
  }

  Future<void> clearRecoveryState() async {
    try {
      final dir = await _getProjectsDirectory();
      final file = File('${dir.path}/recovery_active.json');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
