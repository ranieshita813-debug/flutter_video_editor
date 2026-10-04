import 'package:file_picker/file_picker.dart';
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
    this.path,
    this.isAudio = false,
  });

  final String id;
  final String name;
  final Duration duration;
  final bool isVid;
  final bool isAudio;
  final String category; // 'Recent', 'Videos', 'Photos', 'Audio'
  final String? path;
}

class MediaPickerPage extends StatefulWidget {
  const MediaPickerPage({super.key});

  @override
  State<MediaPickerPage> createState() => _MediaPickerPageState();
}

class _MediaPickerPageState extends State<MediaPickerPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<MediaAsset> _pickedAssets = <MediaAsset>[];
  final List<MediaAsset> _selectedAssets = <MediaAsset>[];
  bool _isLoading = false;

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

  Future<void> _pickFilesFromDevice({FileType type = FileType.any}) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final result = await FilePicker.pickFiles(
        type: type,
        allowedExtensions: type == FileType.custom
            ? <String>['mp4', 'mov', 'avi', 'mkv', 'jpg', 'jpeg', 'png', 'mp3', 'wav', 'm4a']
            : null,
      );

      if (result.isNotEmpty) {
        for (final file in result) {
          final ext = file.extension?.toLowerCase() ?? '';
          final isVid = <String>['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'].contains(ext);
          final isAud = <String>['mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg'].contains(ext);

          final asset = MediaAsset(
            id: 'file_${DateTime.now().microsecondsSinceEpoch}_${file.name.hashCode}',
            name: file.name,
            duration: isVid ? const Duration(seconds: 10) : (isAud ? const Duration(seconds: 15) : Duration.zero),
            isVid: isVid,
            isAudio: isAud,
            category: isVid ? 'Videos' : (isAud ? 'Audio' : 'Photos'),
            path: file.path,
          );

          if (!_pickedAssets.any((a) => a.path == file.path && file.path != null)) {
            _pickedAssets.add(asset);
            _selectedAssets.add(asset);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking file: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
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
      final ClipType clipType = asset.isAudio
          ? ClipType.audio
          : (asset.isVid ? ClipType.video : ClipType.image);

      final clipDuration = asset.isVid && asset.duration > Duration.zero
          ? asset.duration
          : (asset.isAudio ? asset.duration : const Duration(seconds: 4));

      clips.add(
        TimelineClip(
          id: 'clip_${DateTime.now().millisecondsSinceEpoch}_$i',
          label: asset.name,
          start: currentOffset,
          end: currentOffset + clipDuration,
          clipType: clipType,
          layerIndex: asset.isAudio ? 1 : 0,
          sourcePath: asset.path,
        ),
      );

      if (!asset.isAudio) {
        currentOffset += clipDuration;
      }
    }

    final projectsController =
        Provider.of<ProjectsController>(context, listen: false);
    final editorController =
        Provider.of<EditorController>(context, listen: false);

    final newProj = projectsController.createProject(
      name: _selectedAssets.first.name,
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
        actions: <Widget>[
          TextButton.icon(
            onPressed: () => _pickFilesFromDevice(),
            icon: const Icon(Icons.add_a_photo_outlined, color: AppColors.accent, size: 20),
            label: const Text('Browse Files', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const <Widget>[
            Tab(text: 'All Items'),
            Tab(text: 'Videos'),
            Tab(text: 'Photos'),
            Tab(text: 'Audio'),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (_isLoading)
              const LinearProgressIndicator(color: AppColors.accent),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: <Widget>[
                  _buildGrid(_pickedAssets),
                  _buildGrid(_pickedAssets.where((a) => a.isVid).toList()),
                  _buildGrid(_pickedAssets.where((a) => !a.isVid && !a.isAudio).toList()),
                  _buildGrid(_pickedAssets.where((a) => a.isAudio).toList()),
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
                        ? 'Tap items or Browse Files to select'
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.perm_media_outlined, size: 64, color: AppColors.textDisabled),
            const SizedBox(height: 16),
            const Text(
              'No media files selected',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _pickFilesFromDevice(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('Browse Files from Storage'),
            ),
          ],
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
                      asset.isVid
                          ? Icons.videocam
                          : (asset.isAudio ? Icons.audiotrack : Icons.image),
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

              // Duration Badge for videos & audio
              if (asset.isVid || asset.isAudio)
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
}
