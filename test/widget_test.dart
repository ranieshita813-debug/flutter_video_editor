import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/controllers/auth_controller.dart';
import 'package:flutter_video_editor/core/theme/app_theme.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/export/controllers/export_controller.dart';
import 'package:flutter_video_editor/features/editor/pages/editor_page.dart';
import 'package:flutter_video_editor/features/projects/controllers/projects_controller.dart';
import 'package:flutter_video_editor/features/projects/pages/home_page.dart';
import 'package:flutter_video_editor/features/splash/pages/splash_screen.dart';

Widget createTestWidget(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AuthController()),
      ChangeNotifierProvider(create: (_) => ProjectsController()),
      ChangeNotifierProvider(create: (_) => EditorController()),
      ChangeNotifierProvider(create: (_) => ExportController()),
    ],
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      routes: {
        '/home': (_) => const HomePage(),
        '/editor': (_) => const EditorPage(),
      },
      home: child,
    ),
  );
}

void main() {
  testWidgets('SplashScreen renders title motionGr', (WidgetTester tester) async {
    await tester.pumpWidget(createTestWidget(const SplashScreen()));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('m'), findsOneWidget);
    expect(find.text('G'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2000));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  });

  testWidgets('HomePage renders New Project button and project list', (WidgetTester tester) async {
    await tester.pumpWidget(createTestWidget(const HomePage()));

    expect(find.text('motionGr'), findsOneWidget);
    expect(find.text('New project'), findsOneWidget);
    expect(find.text('Your projects'), findsOneWidget);
    expect(find.text('Start your first project'), findsOneWidget);
  });

  testWidgets('EditorPage renders workspace, inspector and toolbar', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(createTestWidget(const EditorPage()));

    expect(find.text('Export'), findsOneWidget);
    expect(find.text('1080p'), findsOneWidget);

    expect(find.text('Draw'), findsWidgets);
    expect(find.text('Text'), findsWidgets);
    expect(find.text('Adjust'), findsWidgets);
    expect(find.text('Audio'), findsWidgets);
    expect(find.text('Track'), findsWidgets);
    expect(find.text('Auto captions'), findsWidgets);
  });

  testWidgets('Opening Export Modal works', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(createTestWidget(const EditorPage()));

    final exportButton = find.text('Export');
    expect(exportButton, findsOneWidget);

    await tester.tap(exportButton);
    await tester.pumpAndSettle();

    expect(find.text('Resolution'), findsOneWidget);
  });
}
