import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/projects/controllers/projects_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProjectsController Unit Tests', () {
    late ProjectsController controller;

    setUp(() {
      controller = ProjectsController();
    });

    test('Initial projects list starts empty', () {
      expect(controller.projects.isEmpty, isTrue);
    });

    test('Creates a new project and inserts at top', () {
      final newProj = controller.createProject(
        name: 'Vlog Demo',
        aspectRatio: AspectRatioPreset.nineSixteen,
      );

      expect(controller.projects.length, equals(1));
      expect(controller.projects.first.id, equals(newProj.id));
      expect(controller.projects.first.name, equals('Vlog Demo'));
    });

    test('Renames an existing project', () {
      final created = controller.createProject(name: 'Original Name');
      controller.renameProject(created.id, 'Renamed Masterpiece');

      final updated = controller.getProject(created.id);
      expect(updated, isNotNull);
      expect(updated!.name, equals('Renamed Masterpiece'));
    });

    test('Duplicates an existing project', () {
      final original = controller.createProject(name: 'Travel Video');
      final initialCount = controller.projects.length;
      final duplicated = controller.duplicateProject(original.id);

      expect(duplicated, isNotNull);
      expect(controller.projects.length, equals(initialCount + 1));
      expect(duplicated!.name, equals('${original.name} (Copy)'));
    });

    test('Deletes a project', () {
      final created = controller.createProject(name: 'To Be Deleted');
      final initialCount = controller.projects.length;
      controller.deleteProject(created.id);

      expect(controller.projects.length, equals(initialCount - 1));
      expect(controller.getProject(created.id), isNull);
    });

    test('detectAspectRatio selects correct ratio based on dimensions', () {
      expect(detectAspectRatio(1080, 1920), equals(AspectRatioPreset.nineSixteen));
      expect(detectAspectRatio(1920, 1080), equals(AspectRatioPreset.sixteenNine));
      expect(detectAspectRatio(1080, 1080), equals(AspectRatioPreset.oneOne));
      expect(detectAspectRatio(1080, 1350), equals(AspectRatioPreset.fourFive));
      expect(detectAspectRatio(2560, 1080), equals(AspectRatioPreset.twentyOneNine));
    });
  });
}
