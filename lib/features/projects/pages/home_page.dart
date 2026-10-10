import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/controllers/auth_controller.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';
import 'package:flutter_video_editor/features/media_picker/pages/media_picker_page.dart';
import 'package:flutter_video_editor/features/projects/controllers/projects_controller.dart';

const List<String> _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _fmt(Duration d) {
  final int s = d.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

String _fmtDate(DateTime d) => '${_months[d.month - 1]} ${d.day}';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  void _createNewProject(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MediaPickerPage()),
    );
  }

  void _openProject(BuildContext context, Project project) {
    Provider.of<EditorController>(context, listen: false).loadProject(project);
    Navigator.of(context).pushNamed('/editor');
  }

  void _openAccount(BuildContext context) {
    Navigator.of(context).pushNamed('/auth');
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).pushNamed('/settings');
  }

  RoundedRectangleBorder get _sheetShape => const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      );

  void _showProjectActions(
    BuildContext context,
    Project project,
    ProjectsController controller,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: EditorTokens.surface,
      showDragHandle: true,
      shape: _sheetShape,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          project.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: EditorTokens.text),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_fmt(project.duration)} · ${_fmtDate(project.updatedAt)}',
                          style: const TextStyle(
                              fontSize: 12, color: EditorTokens.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: EditorTokens.border),
            ListTile(
              leading: const HugeIcon(
                icon: HugeIcons.strokeRoundedEdit02,
                color: EditorTokens.text,
                size: 20,
              ),
              title: const Text('Rename', style: TextStyle(color: EditorTokens.text)),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameDialog(context, project);
              },
            ),
            ListTile(
              leading: const HugeIcon(
                icon: HugeIcons.strokeRoundedCopy01,
                color: EditorTokens.text,
                size: 20,
              ),
              title: const Text('Duplicate', style: TextStyle(color: EditorTokens.text)),
              onTap: () {
                Navigator.pop(ctx);
                controller.duplicateProject(project.id);
              },
            ),
            ListTile(
              leading: const HugeIcon(
                icon: HugeIcons.strokeRoundedDelete02,
                color: Colors.redAccent,
                size: 20,
              ),
              title: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(context, project, controller);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    Project project,
    ProjectsController controller,
  ) {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: EditorTokens.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete project',
            style: TextStyle(
                color: EditorTokens.text,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
        content: Text('"${project.name}" will be removed from your projects.',
            style: const TextStyle(color: EditorTokens.muted, fontSize: 14)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: EditorTokens.muted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              controller.deleteProject(project.id);
            },
            child: const Text('Delete',
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, Project project) {
    final TextEditingController input = TextEditingController(text: project.name);

    void submit(BuildContext ctx) {
      final String newName = input.text.trim();
      if (newName.isNotEmpty) {
        Provider.of<ProjectsController>(context, listen: false)
            .renameProject(project.id, newName);
      }
      Navigator.pop(ctx);
    }

    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: EditorTokens.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Rename project',
            style: TextStyle(
                color: EditorTokens.text,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
        content: TextField(
          controller: input,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => submit(ctx),
          style: const TextStyle(color: EditorTokens.text),
          cursorColor: EditorTokens.text,
          decoration: const InputDecoration(
            hintText: 'Project name',
            hintStyle: TextStyle(color: EditorTokens.faint),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: EditorTokens.border)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: EditorTokens.text)),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: EditorTokens.muted)),
          ),
          TextButton(
            onPressed: () => submit(ctx),
            child: const Text('Rename',
                style: TextStyle(
                    color: EditorTokens.text, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    ).whenComplete(input.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final ProjectsController projectsController =
        Provider.of<ProjectsController>(context);
    final List<Project> projects = projectsController.projects;

    return Scaffold(
      backgroundColor: EditorTokens.bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: <Widget>[
            SliverToBoxAdapter(child: _buildHeader(context)),
            SliverToBoxAdapter(child: _buildNewProjectButton(context)),
            SliverToBoxAdapter(child: _buildSectionHeader(projects.length)),
            if (projects.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmptyState(context),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 14,
                    childAspectRatio: 0.48,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) => _buildProjectCard(
                      context,
                      projects[index],
                      projectsController,
                    ),
                    childCount: projects.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final user = context.watch<AuthController>().currentUser;
    final String initial = (user != null && user.displayName.isNotEmpty)
        ? user.displayName.substring(0, 1).toUpperCase()
        : 'U';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: SvgPicture.asset(
                'assets/logo.svg',
                height: 28,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Account',
            onPressed: () => _openAccount(context),
            icon: CircleAvatar(
              radius: 14,
              backgroundColor: EditorTokens.accent,
              child: Text(
                initial,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800, color: Colors.black),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => _openSettings(context),
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedSettings02,
              color: EditorTokens.text,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewProjectButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton.icon(
          onPressed: () => _createNewProject(context),
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedAdd01,
            color: Colors.black,
            size: 22,
          ),
          label: const Text('New project'),
          style: ElevatedButton.styleFrom(
            backgroundColor: EditorTokens.text,
            foregroundColor: Colors.black,
            elevation: 0,
            shape: const StadiumBorder(),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          const Text('Your projects',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: EditorTokens.text)),
          const SizedBox(width: 8),
          Text('$count',
              style: const TextStyle(fontSize: 13, color: EditorTokens.muted)),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const HugeIcon(
            icon: HugeIcons.strokeRoundedVideo01,
            color: EditorTokens.faint,
            size: 48,
          ),
          const SizedBox(height: 16),
          const Text('Start your first project',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: EditorTokens.text)),
          const SizedBox(height: 8),
          const Text(
            'Import videos and photos, then trim, add text, and export.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.4, color: EditorTokens.muted),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => _createNewProject(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: EditorTokens.text,
              side: const BorderSide(color: EditorTokens.border),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Create project',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildProjectCard(
    BuildContext context,
    Project project,
    ProjectsController controller,
  ) {
    return GestureDetector(
      onTap: () => _openProject(context, project),
      onLongPress: () => _showProjectActions(context, project, controller),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Container(
                    color: EditorTokens.elevated,
                    child: const Center(
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedPlay,
                        size: 28,
                        color: EditorTokens.faint,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 5,
                    bottom: 5,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _fmt(project.duration),
                        style: const TextStyle(
                            color: EditorTokens.text,
                            fontSize: 10,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _showProjectActions(context, project, controller),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const HugeIcon(
                          icon: HugeIcons.strokeRoundedMoreHorizontal,
                          size: 16,
                          color: EditorTokens.text,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            project.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: EditorTokens.text),
          ),
          const SizedBox(height: 1),
          Text(
            _fmtDate(project.updatedAt),
            maxLines: 1,
            style: const TextStyle(fontSize: 10, color: EditorTokens.muted),
          ),
        ],
      ),
    );
  }
}
