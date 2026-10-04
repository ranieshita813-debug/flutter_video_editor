import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/projects/controllers/projects_controller.dart';

void main() {
  group('ProjectsController Unit Tests', () {
    late ProjectsController controller;

    setUp(() {
      controller = ProjectsController();
    });

    test('Loads initial sample projects', () {
      expect(controller.projects.isNotEmpty, isTrue);
      expect(controller.projects.length, equals(3));
    });

    test('Creates a new project and inserts at top', () {
      final initialCount = controller.projects.length;
      final newProj = controller.createProject(
        name: 'Vlog Demo',
        aspectRatio: AspectRatioPreset.nineSixteen,
      );

      expect(controller.projects.length, equals(initialCount + 1));
      expect(controller.projects.first.id, equals(newProj.id));
      expect(controller.projects.first.name, equals('Vlog Demo'));
    });

    test('Renames an existing project', () {
      final projectToRename = controller.projects.first;
      controller.renameProject(projectToRename.id, 'Renamed Masterpiece');

      final updated = controller.getProject(projectToRename.id);
      expect(updated, isNotNull);
      expect(updated!.name, equals('Renamed Masterpiece'));
    });

    test('Duplicates an existing project', () {
      final initialCount = controller.projects.length;
      final original = controller.projects.first;
      final duplicated = controller.duplicateProject(original.id);

      expect(duplicated, isNotNull);
      expect(controller.projects.length, equals(initialCount + 1));
      expect(duplicated!.name, equals('${original.name} (Copy)'));
    });

    test('Deletes a project', () {
      final initialCount = controller.projects.length;
      final projectToDelete = controller.projects.first;
      controller.deleteProject(projectToDelete.id);

      expect(controller.projects.length, equals(initialCount - 1));
      expect(controller.getProject(projectToDelete.id), isNull);
    });
  });
}
