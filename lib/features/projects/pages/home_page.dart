import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/controllers/auth_controller.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/media_picker/pages/media_picker_page.dart';
import 'package:flutter_video_editor/features/projects/controllers/projects_controller.dart';

const Color _accent = Color(0xFF00C4D6); // Crisp cyan accent for light theme
const Color _homeBg = Color(0xFFFFFFFF);
const Color _homeSurface = Color(0xFFF5F5F7);
const Color _homeCard = Color(0xFFFFFFFF);
const Color _homeBorder = Color(0xFFE5E5EA);
const Color _homeText = Color(0xFF1C1C1E);
const Color _homeMuted = Color(0xFF8E8E93);
const Color _homeFaint = Color(0xFFC7C7CC);

const List<String> _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _fmt(Duration d) {
  final int s = d.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

String _fmtDate(DateTime d) => '${_months[d.month - 1]} ${d.day}';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 1; // 0: Template, 1: Home, 2: Projects

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
      backgroundColor: _homeCard,
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
                              color: _homeText),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_fmt(project.duration)} · ${_fmtDate(project.updatedAt)}',
                          style: const TextStyle(
                              fontSize: 12, color: _homeMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _homeBorder),
            ListTile(
              leading: const PhosphorIcon(
                PhosphorIconsBold.pencilSimple,
                color: _homeText,
                size: 18,
              ),
              title: const Text('Rename', style: TextStyle(color: _homeText, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameDialog(context, project);
              },
            ),
            ListTile(
              leading: const PhosphorIcon(
                PhosphorIconsBold.copy,
                color: _homeText,
                size: 18,
              ),
              title: const Text('Duplicate', style: TextStyle(color: _homeText, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                controller.duplicateProject(project.id);
              },
            ),
            ListTile(
              leading: const PhosphorIcon(
                PhosphorIconsBold.trash,
                color: Colors.redAccent,
                size: 18,
              ),
              title: const Text('Delete', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
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
        backgroundColor: _homeCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Delete project',
            style: TextStyle(
                color: _homeText,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
        content: Text('"${project.name}" will be removed from your projects.',
            style: const TextStyle(color: _homeMuted, fontSize: 14)),
        actions: <Widget>[
          TextButton(
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: _homeMuted, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
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
        backgroundColor: _homeCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Rename project',
            style: TextStyle(
                color: _homeText,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
        content: TextField(
          controller: input,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => submit(ctx),
          style: const TextStyle(color: _homeText),
          cursorColor: _accent,
          decoration: const InputDecoration(
            hintText: 'Project name',
            hintStyle: TextStyle(color: _homeFaint),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: _homeBorder)),
            focusedBorder:
                UnderlineInputBorder(borderSide: BorderSide(color: _accent)),
          ),
        ),
        actions: <Widget>[
          TextButton(
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: _homeMuted, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
            onPressed: () => submit(ctx),
            child: const Text('Rename',
                style: TextStyle(color: _accent, fontWeight: FontWeight.w700)),
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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: _homeBg,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: _homeBg,
      ),
      child: Scaffold(
        backgroundColor: _homeBg,
        body: SafeArea(
          child: IndexedStack(
            index: _currentIndex,
            children: <Widget>[
              _buildTemplateTab(context),
              _buildHomeTab(context, projects, projectsController),
              _buildProjectsTab(context, projects, projectsController),
            ],
          ),
        ),
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  Widget _buildBottomNav() {
    const items = <(IconData, IconData, String)>[
      (PhosphorIconsBold.gridFour, PhosphorIconsFill.gridFour, 'Template'),
      (PhosphorIconsBold.house, PhosphorIconsFill.house, 'Home'),
      (PhosphorIconsBold.folder, PhosphorIconsFill.folder, 'Projects'),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: _homeBg,
        border: Border(top: BorderSide(color: _homeBorder)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: <Widget>[
              for (int i = 0; i < items.length; i++)
                Expanded(
                  child: InkResponse(
                    onTap: () => setState(() => _currentIndex = i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        PhosphorIcon(
                          i == _currentIndex ? items[i].$2 : items[i].$1,
                          size: 22,
                          color: i == _currentIndex ? _homeText : _homeMuted,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          items[i].$3,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: i == _currentIndex ? FontWeight.w800 : FontWeight.w600,
                            color: i == _currentIndex
                                ? _homeText
                                : _homeMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomeTab(
    BuildContext context,
    List<Project> projects,
    ProjectsController projectsController,
  ) {
    return CustomScrollView(
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
    );
  }

  Widget _buildProjectsTab(
    BuildContext context,
    List<Project> projects,
    ProjectsController projectsController,
  ) {
    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(child: _buildHeader(context)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  'All projects (${projects.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _homeText,
                  ),
                ),
                IconButton(
                  onPressed: () => _createNewProject(context),
                  icon: const PhosphorIcon(
                    PhosphorIconsBold.plus,
                    color: _homeText,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (projects.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _buildEmptyState(context),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 16,
                childAspectRatio: 0.72,
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
    );
  }

  void _createProjectFromTemplate(BuildContext context, String templateName, String ratioStr) {
    final projectsCtrl = Provider.of<ProjectsController>(context, listen: false);
    final editor = Provider.of<EditorController>(context, listen: false);

    final project = projectsCtrl.createProject(
      name: '$templateName (${DateTime.now().millisecond})',
    );

    editor.loadProject(project);

    // Seed preset text or element based on template
    editor.addTextOverlay('Sample $templateName Title');
    editor.addCaptionCue(CaptionCue(
      id: 'tmpl_cue_1',
      start: Duration.zero,
      end: const Duration(seconds: 4),
      text: 'Welcome to $templateName!',
      words: const [
        CaptionWord(word: 'Welcome', start: Duration.zero, end: Duration(seconds: 1)),
        CaptionWord(word: 'to', start: Duration(seconds: 1), end: Duration(milliseconds: 1500)),
        CaptionWord(word: 'motionGr', start: Duration(milliseconds: 1500), end: Duration(seconds: 3)),
      ],
    ));

    Navigator.of(context).pushNamed('/editor');
  }

  Widget _buildTemplateTab(BuildContext context) {
    final templates = [
      {
        'title': 'Vlog Reel',
        'desc': 'Dynamic vertical layout with colorful captions',
        'ratio': '9:16',
        'tag': 'Popular',
        'color': const Color(0xFF00C4D6),
        'icon': PhosphorIconsBold.filmStrip,
      },
      {
        'title': 'TikTok Shorts',
        'desc': 'Fast-paced text animations & neon glow effects',
        'ratio': '9:16',
        'tag': 'Trending',
        'color': const Color(0xFFFF007F),
        'icon': PhosphorIconsBold.sparkle,
      },
      {
        'title': 'Cinematic Intro',
        'desc': 'Widescreen cinematic filter & bold titles',
        'ratio': '16:9',
        'tag': 'Pro',
        'color': const Color(0xFFD97706),
        'icon': PhosphorIconsBold.videoCamera,
      },
      {
        'title': 'Cyberpunk Beat',
        'desc': 'Glitch transitions & futuristic text badge',
        'ratio': '9:16',
        'tag': 'New',
        'color': const Color(0xFF059669),
        'icon': PhosphorIconsBold.lightning,
      },
      {
        'title': 'Karaoke Story',
        'desc': 'Word-by-word active speech highlighting',
        'ratio': '9:16',
        'tag': 'Featured',
        'color': const Color(0xFFA855F7),
        'icon': PhosphorIconsBold.musicNote,
      },
      {
        'title': 'Minimalist Vlog',
        'desc': 'Square 1:1 clean aesthetic for social posts',
        'ratio': '1:1',
        'tag': 'Minimal',
        'color': const Color(0xFF4B5563),
        'icon': PhosphorIconsBold.textbox,
      },
    ];

    return Column(
      children: <Widget>[
        _buildHeader(context),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Templates',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _homeText,
                fontFamily: 'Ubuntu Sans',
              ),
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.85,
            ),
            itemCount: templates.length,
            itemBuilder: (ctx, idx) {
              final tmpl = templates[idx];
              final Color tmplColor = tmpl['color'] as Color;

              return GestureDetector(
                onTap: () => _createProjectFromTemplate(
                  context,
                  tmpl['title'] as String,
                  tmpl['ratio'] as String,
                ),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _homeSurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _homeBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: tmplColor.withValues(alpha: 0.16),
                              shape: BoxShape.circle,
                            ),
                            child: PhosphorIcon(
                              tmpl['icon'] as IconData,
                              size: 20,
                              color: tmplColor,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _homeBorder,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              tmpl['tag'] as String,
                              style: const TextStyle(
                                color: _homeText,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        tmpl['title'] as String,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _homeText,
                          fontFamily: 'Ubuntu Sans',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tmpl['desc'] as String,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: _homeMuted,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            tmpl['ratio'] as String,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _homeMuted,
                            ),
                          ),
                          const Text(
                            'Use template',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: _homeText,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
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
                'assets/logo_black.svg',
                height: 40,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Account',
            onPressed: () => _openAccount(context),
            icon: CircleAvatar(
              radius: 14,
              backgroundColor: _homeText,
              child: Text(
                initial,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => _openSettings(context),
            icon: const PhosphorIcon(
              PhosphorIconsBold.gear,
              color: _homeText,
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
      child: GestureDetector(
        onTap: () => _createNewProject(context),
        child: Container(
          height: 92,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: _homeText,
            borderRadius: BorderRadius.circular(999),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: PhosphorIcon(
                    PhosphorIconsBold.plus,
                    color: _homeText,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'New project',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Import videos and photos',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const PhosphorIcon(
                PhosphorIconsBold.caretRight,
                color: Colors.white70,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 12, 8),
      child: Row(
        children: <Widget>[
          const Text('Projects',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _homeText)),
          const SizedBox(width: 8),
          Text('$count',
              style: const TextStyle(fontSize: 13, color: _homeMuted)),
          const Spacer(),
          if (count > 0)
            TextButton(
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              ),
              onPressed: () => setState(() => _currentIndex = 2),
              child: const Text('See all',
                  style: TextStyle(
                      color: _homeMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
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
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: _homeSurface,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: PhosphorIcon(
                PhosphorIconsBold.videoCamera,
                color: _homeMuted,
                size: 32,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Start your first project',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _homeText)),
          const SizedBox(height: 8),
          const Text(
            'Import videos and photos, then trim, add text, and export.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.4, color: _homeMuted),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => _createNewProject(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: _homeText,
              side: const BorderSide(color: _homeText, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
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
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Container(
                    color: _homeSurface,
                    child: const Center(
                      child: PhosphorIcon(
                        PhosphorIconsFill.play,
                        size: 24,
                        color: _homeMuted,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _fmt(project.duration),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _showProjectActions(context, project, controller),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: PhosphorIcon(
                            PhosphorIconsBold.dotsThreeVertical,
                            size: 14,
                            color: _homeText,
                          ),
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
                fontWeight: FontWeight.w700,
                color: _homeText),
          ),
          const SizedBox(height: 1),
          Text(
            _fmtDate(project.updatedAt),
            maxLines: 1,
            style: const TextStyle(fontSize: 10, color: _homeMuted),
          ),
        ],
      ),
    );
  }
}