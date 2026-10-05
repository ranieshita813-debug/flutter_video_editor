import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/controllers/auth_controller.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/core/widgets/auth_sheet.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/media_picker/pages/media_picker_page.dart';
import 'package:flutter_video_editor/features/projects/controllers/projects_controller.dart';

// -----------------------------------------------------------------------------
// Tokens (monochrome)
// -----------------------------------------------------------------------------

const Color _bg = Color(0xFF000000);
const Color _surface = Color(0xFF111111);
const Color _elevated = Color(0xFF1C1C1C);
const Color _border = Color(0xFF2A2A2A);
const Color _text = Color(0xFFFFFFFF);
const Color _muted = Color(0xFF8C8C8C);
const Color _faint = Color(0xFF5A5A5A);
const Color _onWhite = Color(0xFF000000);

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

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _createNewProject(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MediaPickerPage()),
    );
  }

  void _openProject(BuildContext context, Project project) {
    Provider.of<EditorController>(context, listen: false).loadProject(project);
    Navigator.of(context).pushNamed('/editor');
  }

  void _openAccount(BuildContext context) => AuthSheet.show(context);

  RoundedRectangleBorder get _sheetShape => const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      );

  void _openSettings(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
      showDragHandle: true,
      shape: _sheetShape,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _tile(Icons.account_circle_outlined, 'Account', 'Sign in or view profile',
                onTap: () {
              Navigator.pop(ctx);
              _openAccount(context);
            }),
            _tile(Icons.hd_outlined, 'Default resolution', '1080p (Full HD)'),
            _tile(Icons.speed_rounded, 'Default frame rate', '30 FPS'),
            _tile(Icons.info_outline_rounded, 'About motionGr', 'Version 1.0.0'),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _tile(IconData icon, String title, String subtitle, {VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: _text),
      title: Text(title, style: const TextStyle(color: _text, fontSize: 15)),
      subtitle: Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12)),
      trailing: onTap == null
          ? null
          : const Icon(Icons.chevron_right_rounded, color: _muted),
      onTap: onTap,
    );
  }

  void _showProjectActions(
    BuildContext context,
    Project project,
    ProjectsController controller,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
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
                              fontSize: 16, fontWeight: FontWeight.w700, color: _text),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_fmt(project.duration)} · ${_fmtDate(project.updatedAt)}',
                          style: const TextStyle(fontSize: 12, color: _muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _border),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: _text),
              title: const Text('Rename', style: TextStyle(color: _text)),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameDialog(context, project);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined, color: _text),
              title: const Text('Duplicate', style: TextStyle(color: _text)),
              onTap: () {
                Navigator.pop(ctx);
                controller.duplicateProject(project.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: _text),
              title: const Text('Delete', style: TextStyle(color: _text)),
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
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete project',
            style: TextStyle(color: _text, fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text('"${project.name}" will be removed from your projects.',
            style: const TextStyle(color: _muted, fontSize: 14)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: _muted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              controller.deleteProject(project.id);
            },
            child: const Text('Delete',
                style: TextStyle(color: _text, fontWeight: FontWeight.w700)),
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
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Rename project',
            style: TextStyle(color: _text, fontSize: 17, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: input,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => submit(ctx),
          style: const TextStyle(color: _text),
          cursorColor: _text,
          decoration: const InputDecoration(
            hintText: 'Project name',
            hintStyle: TextStyle(color: _faint),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: _border)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _text)),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: _muted)),
          ),
          TextButton(
            onPressed: () => submit(ctx),
            child: const Text('Rename',
                style: TextStyle(color: _text, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    ).whenComplete(input.dispose);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ProjectsController projectsController =
        Provider.of<ProjectsController>(context);
    final List<Project> projects = projectsController.projects;

    return Scaffold(
      backgroundColor: _bg,
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
            child: Text(
              'motionGr',
              style: GoogleFonts.unbounded(
                color: _text,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Account',
            onPressed: () => _openAccount(context),
            icon: CircleAvatar(
              radius: 14,
              backgroundColor: _text,
              child: Text(
                initial,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800, color: _onWhite),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => _openSettings(context),
            icon: const Icon(Icons.settings_outlined, color: _text, size: 24),
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
          icon: const Icon(Icons.add_rounded, size: 26),
          label: const Text('New project'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _text,
            foregroundColor: _onWhite,
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
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _text)),
          const SizedBox(width: 8),
          Text('$count', style: const TextStyle(fontSize: 13, color: _muted)),
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
          const Icon(Icons.video_library_outlined, size: 56, color: _faint),
          const SizedBox(height: 16),
          const Text('Start your first project',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _text)),
          const SizedBox(height: 8),
          const Text(
            'Import videos and photos, then trim, add text, and export.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.4, color: _muted),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => _createNewProject(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: _text,
              side: const BorderSide(color: _border),
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
    final bool isPortrait = project.aspectRatio == AspectRatioPreset.nineSixteen;

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
                    color: _elevated,
                    child: Center(
                      child: Icon(
                        isPortrait
                            ? Icons.stay_current_portrait_rounded
                            : Icons.movie_outlined,
                        size: 30,
                        color: _faint,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 5,
                    bottom: 5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(170),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _fmt(project.duration),
                        style: const TextStyle(
                            color: _text, fontSize: 10, fontWeight: FontWeight.w600),
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
                          color: Colors.black.withAlpha(150),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.more_horiz_rounded,
                            size: 16, color: _text),
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
                fontSize: 12, fontWeight: FontWeight.w600, color: _text),
          ),
          const SizedBox(height: 1),
          Text(
            _fmtDate(project.updatedAt),
            maxLines: 1,
            style: const TextStyle(fontSize: 10, color: _muted),
          ),
        ],
      ),
    );
  }
}