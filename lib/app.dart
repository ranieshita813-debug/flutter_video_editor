import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/theme/app_theme.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/pages/editor_page.dart';

class VideoEditorApp extends StatelessWidget {
  const VideoEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => EditorController(),
      child: MaterialApp(
        title: 'Video Editor Pro',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const EditorPage(),
      ),
    );
  }
}
