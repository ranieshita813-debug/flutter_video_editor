import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/theme/app_theme.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/export/controllers/export_controller.dart';
import 'package:flutter_video_editor/features/editor/pages/editor_page.dart';
import 'package:flutter_video_editor/features/media_picker/pages/media_picker_page.dart';
import 'package:flutter_video_editor/features/projects/controllers/projects_controller.dart';
import 'package:flutter_video_editor/features/projects/pages/home_page.dart';
import 'package:flutter_video_editor/features/splash/pages/splash_screen.dart';

class VideoEditorApp extends StatelessWidget {
  const VideoEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ProjectsController()),
        ChangeNotifierProvider(create: (_) => EditorController()),
        ChangeNotifierProvider(create: (_) => ExportController()),
      ],
      child: MaterialApp(
        title: 'motionGr',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const SplashScreen(),
        routes: <String, WidgetBuilder>{
          '/home': (_) => const HomePage(),
          '/media_picker': (_) => const MediaPickerPage(),
          '/editor': (_) => const EditorPage(),
        },
      ),
    );
  }
}
