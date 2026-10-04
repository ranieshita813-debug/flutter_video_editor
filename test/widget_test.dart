import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/theme/app_theme.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/pages/editor_page.dart';
import 'package:flutter_video_editor/features/splash/pages/splash_screen.dart';

Widget createTestWidget(Widget child) {
  return ChangeNotifierProvider<EditorController>(
    create: (_) => EditorController(),
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      routes: {
        '/editor': (_) => const EditorPage(),
      },
      home: child,
    ),
  );
}

void main() {
  testWidgets('SplashScreen renders title motionGr', (WidgetTester tester) async {
    await tester.pumpWidget(createTestWidget(const SplashScreen()));

    expect(find.text('motionGr'), findsOneWidget);
    expect(find.text('Professional Video Editing at Your Fingertips'), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 4));
  });

  testWidgets('EditorPage renders workspace, inspector and toolbar', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(createTestWidget(const EditorPage()));

    expect(find.text('CapCut & Pro Studio Edition'), findsOneWidget);
    expect(find.text('Clip Inspector'), findsOneWidget);
    expect(find.text('Multi-Layer Timeline'), findsOneWidget);

    expect(find.text('Split'), findsWidgets);
    expect(find.text('Vector Draw'), findsOneWidget);
    expect(find.text('Text & Font'), findsOneWidget);
    expect(find.text('Color Grade'), findsOneWidget);
    expect(find.text('Audio Tools'), findsOneWidget);
    expect(find.text('Camera & Track'), findsOneWidget);
  });

  testWidgets('Opening Export Modal works', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(createTestWidget(const EditorPage()));

    final exportButton = find.widgetWithText(OutlinedButton, 'Export');
    expect(exportButton, findsOneWidget);

    await tester.tap(exportButton);
    await tester.pumpAndSettle();

    expect(find.text('Fast Export & Render'), findsOneWidget);
    expect(find.text('Resolution'), findsOneWidget);
    expect(find.text('Export Now (Fast Engine)'), findsOneWidget);
  });
}
