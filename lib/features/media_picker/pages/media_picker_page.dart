import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/core/theme/app_colors.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/projects/controllers/projects_controller.dart';

class MediaAsset {
  MediaAsset({
    required this.id,
    required this.name,
    required this.duration,
    required this.isVid,
    required this.category,
  });

  final String id;
  final String name;
  final Duration duration;
  final bool isVid;
  final String category; // 'Recent', 'Videos', 'Photos', 'Albums'
}

class MediaPickerPage extends StatefulWidget {
  const MediaPickerPage({super.key});

  @override
  State<MediaPickerPage> createState() => _MediaPickerPageState();
}

class _MediaPickerPageState extends State<MediaPickerPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<MediaAsset> _selectedAssets = <MediaAsset>[];

  final List<MediaAsset> _sampleAssets = <MediaAsset>[
    MediaAsset(
      id: 'm1',
      name: 'Sunset Beach',
      duration: const Duration(seconds: 10),
      isVid: true,
      category: 'Videos',
    ),
    MediaAsset(
      id: 'm2',
      name: 'City Drone Shot',
      duration: const Duration(seconds: 15),
      isVid: true,
      category: 'Videos',
    ),
    MediaAsset(
      id: 'm3',
      name: 'Coffee Cafe',
      duration: const Duration(seconds: 8),
      isVid: true,
      category: 'Videos',
    ),
    MediaAsset(
      id: 'm4',
      name: 'Portrait Photo',
      duration: Duration.zero,
      isVid: false,
      category: 'Photos',
    ),
    MediaAsset(
      id: 'm5',
      name: 'Mountain Peak',
      duration: const Duration(seconds: 12),
      isVid: true,
      category: 'Videos',
    ),
    MediaAsset(
      id: 'm6',
      name: 'Neon Cyber City',
      duration: const Duration(seconds: 20),
      isVid: true,
      category: 'Videos',
    ),
    MediaAsset(
      id: 'm7',
      name: 'Studio Setup',
      duration: Duration.zero,
      isVid: false,
      category: 'Photos',
    ),
    MediaAsset(
      id: 'm8',
      name: 'Music Festival',
      duration: const Duration(seconds: 18),
      isVid: true,
      category: 'Videos',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _toggleSelection(MediaAsset asset) {
    setState(() {
      if (_selectedAssets.contains(asset)) {
        _selectedAssets.remove(asset);
      } else {
        _selectedAssets.add(asset);
      }
    });
  }

  void _addMediaToProject() {
    if (_selectedAssets.isEmpty) return;

    final clips = <TimelineClip>[];
    Duration currentOffset = Duration.zero;

    for (int i = 0; i < _selectedAssets.length; i++) {
      final asset = _selectedAssets[i];
      final clipDuration = asset.isVid && asset.duration > Duration.zero
          ? asset.duration
          : const Duration(seconds: 4);

      clips.add(
        TimelineClip(
          id: 'clip_${DateTime.now().millisecondsSinceEpoch}_$i',
          label: asset.name,
          start: currentOffset,
          end: currentOffset + clipDuration,
          clipType: asset.isVid ? ClipType.video : ClipType.image,
          layerIndex: 0,
        ),
      );

      currentOffset += clipDuration;
    }

    final projectsController =
        Provider.of<ProjectsController>(context, listen: false);
    final editorController =
        Provider.of<EditorController>(context, listen: false);

    final newProj = projectsController.createProject(
      name: 'Project ${_selectedAssets.first.name}',
      clips: clips,
    );

    editorController.loadProject(newProj);

    Navigator.of(context).pushReplacementNamed('/editor');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Select Media',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const <Widget>[
            Tab(text: 'Recent'),
            Tab(text: 'Videos'),
            Tab(text: 'Photos'),
            Tab(text: 'Albums'),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: <Widget>[
                  _buildGrid(_sampleAssets),
                  _buildGrid(_sampleAssets.where((a) => a.isVid).toList()),
                  _buildGrid(_sampleAssets.where((a) => !a.isVid).toList()),
                  _buildAlbumsView(),
                ],
              ),
            ),
            // Bottom Bar displaying "Add (N)"
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.divider)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    _selectedAssets.isEmpty
                        ? 'Tap items to select'
                        : '${_selectedAssets.length} item(s) selected',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  ElevatedButton(
                    onPressed:
                        _selectedAssets.isNotEmpty ? _addMediaToProject : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      disabledBackgroundColor: AppColors.surfaceVariant,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: Text(
                      'Add (${_selectedAssets.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(List<MediaAsset> assets) {
    if (assets.isEmpty) {
      return const Center(
        child: Text(
          'No media found',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 1.0,
      ),
      itemCount: assets.length,
      itemBuilder: (context, index) {
        final asset = assets[index];
        final selectedIndex = _selectedAssets.indexOf(asset);
        final isSelected = selectedIndex != -1;

        return GestureDetector(
          onTap: () => _toggleSelection(asset),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                  border: isSelected
                      ? Border.all(color: AppColors.accent, width: 2)
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      asset.isVid ? Icons.videocam : Icons.image,
                      color: AppColors.textSecondary,
                      size: 32,
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Text(
                        asset.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Duration Badge for videos
              if (asset.isVid)
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(200),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      EditorUtils.formatDuration(asset.duration),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 9,
                      ),
                    ),
                  ),
                ),

              // Selection Badge
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? AppColors.accent
                        : Colors.black.withAlpha(120),
                    border: Border.all(
                      color: isSelected ? AppColors.accent : Colors.white,
                      width: 1.5,
                    ),
                  ),
                  child: isSelected
                      ? Center(
                          child: Text(
                            '${selectedIndex + 1}',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAlbumsView() {
    final albums = <Map<String, dynamic>>[
      {'title': 'Camera Roll', 'count': 42},
      {'title': 'Screen Recordings', 'count': 15},
      {'title': 'Downloads', 'count': 8},
      {'title': 'Favorites', 'count': 23},
    ];

    return ListView.builder(
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        return ListTile(
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.folder_outlined, color: AppColors.accent),
          ),
          title: Text(
            album['title'] as String,
            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${album['count']} items',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          onTap: () {
            _tabController.animateTo(0);
          },
        );
      },
    );
  }
}
