import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/projects/controllers/projects_controller.dart';

// -----------------------------------------------------------------------------
// Design tokens
//
// CapCut        -> true-black canvas, tight 2px grid, numbered selection badges
// Premiere Pro  -> label colors per media type, timecode type, source monitor
// Filmora       -> teal/blue gradient call to action, pill tabs, rounded panels
// -----------------------------------------------------------------------------

const Color _bg = Color(0xFF08080A);
const Color _surface = Color(0xFF131316);
const Color _elevated = Color(0xFF1D1D22);
const Color _border = Color(0xFF2B2B32);
const Color _text = Color(0xFFF5F5F7);
const Color _muted = Color(0xFF8E8E98);
const Color _accent = Color(0xFF22E5C9);
const Color _onAccent = Color(0xFF031412);

// Premiere-style label colors, one per media type.
const Color _cVideo = Color(0xFF7C8CFF);
const Color _cImage = Color(0xFF34D399);
const Color _cAudio = Color(0xFFFFB454);


const TextStyle _timecode = TextStyle(
  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
);

String _fmt(Duration d) {
  final int s = d.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

Color _typeColor(ClipType t) => switch (t) {
      ClipType.video => _cVideo,
      ClipType.audio => _cAudio,
      _ => _cImage,
    };

IconData _typeIcon(ClipType t) => switch (t) {
      ClipType.video => Icons.videocam_rounded,
      ClipType.audio => Icons.music_note_rounded,
      _ => Icons.image_rounded,
    };

String _typeName(ClipType t) => switch (t) {
      ClipType.video => 'Video',
      ClipType.audio => 'Audio',
      _ => 'Photo',
    };

ClipType _clipOf(AssetType t) => switch (t) {
      AssetType.video => ClipType.video,
      AssetType.audio => ClipType.audio,
      _ => ClipType.image,
    };

class MediaPickerArgs {
  const MediaPickerArgs({
    this.appendToCurrent = false,
    this.isOverlay = false,
  });

  final bool appendToCurrent;
  final bool isOverlay;
}

/// Kept for compatibility with other files that may import it.
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

/// One selected item: either a gallery entity or a file chosen via "Files".
class _Picked {
  _Picked({
    required this.id,
    required this.name,
    required this.duration,
    required this.type,
    this.entity,
    this.path,
  });

  factory _Picked.fromEntity(AssetEntity e) => _Picked(
        id: e.id,
        name: e.title ?? e.id,
        duration: e.type == AssetType.image ? Duration.zero : e.videoDuration,
        type: _clipOf(e.type),
        entity: e,
      );

  final String id;
  final String name;
  final Duration duration;
  final ClipType type;
  final AssetEntity? entity;
  final String? path;
}

enum _Perm { checking, granted, denied }

class MediaPickerPage extends StatefulWidget {
  const MediaPickerPage({super.key});

  /// Call this early (app start, home screen, first project tap) so the
  /// permission dialog is already answered when the gallery opens.
  static Future<bool> ensurePermission() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    return ps.hasAccess;
  }

  @override
  State<MediaPickerPage> createState() => _MediaPickerPageState();
}

class _MediaPickerPageState extends State<MediaPickerPage>
    with SingleTickerProviderStateMixin {
  static const int _pageSize = 80;

  late final TabController _tabs = TabController(length: 4, vsync: this);
  final ScrollController _scroll = ScrollController();

  final List<_Picked> _selected = <_Picked>[];
  final List<AssetEntity> _assets = <AssetEntity>[];

  _Perm _perm = _Perm.checking;
  bool _limited = false;
  bool _loading = false;
  bool _busy = false;
  bool _hasMore = true;
  bool _adding = false;
  int _page = 0;
  int _gen = 0;
  int _lastTab = 0;

  /// Grid density (3, 4 or 5 columns).
  int _cols = 4;

  /// Item shown in the source monitor (last tapped / long-pressed).
  _Picked? _focus;

  List<AssetPathEntity> _albums = <AssetPathEntity>[];
  AssetPathEntity? _album;

  RequestType get _type => switch (_tabs.index) {
        0 => RequestType.common,
        1 => RequestType.video,
        2 => RequestType.image,
        _ => RequestType.audio,
      };

  MediaPickerArgs? get _args {
    final Object? a = ModalRoute.of(context)?.settings.arguments;
    return a is MediaPickerArgs ? a : null;
  }

  String get _contextLabel {
    final MediaPickerArgs? a = _args;
    if (a == null) return 'New project';
    if (a.isOverlay) return 'Add overlay';
    return a.appendToCurrent ? 'Add to timeline' : 'New project';
  }

  String get _ctaLabel {
    final MediaPickerArgs? a = _args;
    if (a == null) return 'Create project';
    if (a.isOverlay) return 'Add overlay';
    return a.appendToCurrent ? 'Add to timeline' : 'Create project';
  }

  int get _thumbSize => _cols == 3 ? 420 : (_cols == 4 ? 300 : 220);

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging && _tabs.index != _lastTab) {
        _lastTab = _tabs.index;
        _loadAlbums();
      }
    });
    _scroll.addListener(() {
      if (_scroll.hasClients &&
          _scroll.position.pixels > _scroll.position.maxScrollExtent - 600) {
        _loadMore();
      }
    });
    _init();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---- Permission + loading --------------------------------------------------

  Future<void> _init() async {
    setState(() => _perm = _Perm.checking);
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!mounted) return;
    if (ps.hasAccess) {
      setState(() {
        _perm = _Perm.granted;
        _limited = ps == PermissionState.limited;
      });
      await _loadAlbums();
    } else {
      setState(() => _perm = _Perm.denied);
    }
  }

  Future<void> _loadAlbums() async {
    final int gen = ++_gen;
    setState(() {
      _loading = true;
      _assets.clear();
      _page = 0;
      _hasMore = true;
    });

    try {
      final List<AssetPathEntity> albums =
          await PhotoManager.getAssetPathList(type: _type, onlyAll: false);
      if (!mounted || gen != _gen) return;
      setState(() {
        _albums = albums;
        _album = albums.isNotEmpty ? albums.first : null;
        _hasMore = _album != null;
        if (_album == null) _loading = false; // nothing to load -> stop spinner
      });
      _busy = false;
      await _loadMore();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack('Could not load gallery: $e');
      }
    }
  }

  Future<void> _loadMore() async {
    final AssetPathEntity? album = _album;
    if (album == null || _busy || !_hasMore) return;
    _busy = true;
    final int gen = _gen;
    try {
      final List<AssetEntity> list =
          await album.getAssetListPaged(page: _page, size: _pageSize);
      if (!mounted || gen != _gen) return;
      setState(() {
        _assets.addAll(list);
        _page++;
        _hasMore = list.length == _pageSize;
        _loading = false;
      });
    } catch (e) {
      if (mounted && gen == _gen) {
        setState(() => _loading = false);
        _snack('Could not load media: $e');
      }
    } finally {
      if (gen == _gen) _busy = false;
    }
  }

  Future<void> _chooseAlbum() async {
    final AssetPathEntity? picked = await showModalBottomSheet<AssetPathEntity>(
      context: context,
      backgroundColor: _surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (BuildContext sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Albums',
                  style: TextStyle(
                      color: _text, fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  for (final AssetPathEntity a in _albums)
                    ListTile(
                      leading: Icon(
                        a.isAll
                            ? Icons.history_rounded
                            : Icons.folder_rounded,
                        color: a.id == _album?.id ? _accent : _muted,
                      ),
                      title: Text(a.isAll ? 'Recent' : a.name,
                          style: const TextStyle(fontSize: 15)),
                      trailing: FutureBuilder<int>(
                        future: a.assetCountAsync,
                        builder: (_, AsyncSnapshot<int> s) => Text(
                            '${s.data ?? ''}',
                            style: _timecode.copyWith(
                                color: _muted, fontSize: 13)),
                      ),
                      selected: a.id == _album?.id,
                      selectedColor: _accent,
                      textColor: _text,
                      onTap: () => Navigator.of(sheetCtx).pop(a),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || picked.id == _album?.id) return;
    final int gen = ++_gen;
    setState(() {
      _album = picked;
      _assets.clear();
      _page = 0;
      _hasMore = true;
      _loading = true;
    });
    _busy = false;
    if (gen == _gen) await _loadMore();
  }

  // ---- Selection -------------------------------------------------------------

  int _indexOf(String id) => _selected.indexWhere((p) => p.id == id);

  void _toggle(_Picked p) {
    setState(() {
      final int i = _indexOf(p.id);
      if (i >= 0) {
        _selected.removeAt(i);
      } else {
        _selected.add(p);
      }
      _focus = p;
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final _Picked item = _selected.removeAt(oldIndex);
      _selected.insert(newIndex, item);
    });
  }

  void _cycleDensity() {
    setState(() => _cols = _cols == 3 ? 4 : (_cols == 4 ? 5 : 3));
  }

  /// Duration used for a clip on the timeline (same rules as before).
  Duration _effective(_Picked p) {
    final bool isAudio = p.type == ClipType.audio;
    final bool isVideo = p.type == ClipType.video;
    if ((isVideo || isAudio) && p.duration > Duration.zero) return p.duration;
    if (isAudio) return const Duration(seconds: 15);
    if (isVideo) return const Duration(seconds: 10);
    return const Duration(seconds: 4);
  }

  Duration get _totalVideo {
    Duration t = Duration.zero;
    for (final _Picked p in _selected) {
      if (p.type != ClipType.audio) t += _effective(p);
    }
    return t;
  }

  /// Fallback for audio on platforms where the gallery can't list it (iOS),
  /// or for files outside the media library.
  Future<void> _browseFiles() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );
      if (result == null || result.files.isEmpty) return;
      final List<PlatformFile> files = result.files;
      setState(() {
        for (final PlatformFile file in files) {
          final String ext = file.extension?.toLowerCase() ?? '';
          final bool isVid =
              <String>['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'].contains(ext);
          final bool isAud =
              <String>['mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg'].contains(ext);
          final String id = 'file_${file.path ?? file.name}';
          if (_indexOf(id) >= 0) continue;
          final _Picked p = _Picked(
            id: id,
            name: file.name,
            duration: isVid
                ? const Duration(seconds: 10)
                : (isAud ? const Duration(seconds: 15) : Duration.zero),
            type: isVid
                ? ClipType.video
                : (isAud ? ClipType.audio : ClipType.image),
            path: file.path,
          );
          _selected.add(p);
          _focus = p;
        }
      });
    } catch (e) {
      _snack('Error picking file: $e');
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      behavior: SnackBarBehavior.floating,
      backgroundColor: _elevated,
    ));
  }

  // ---- Add to project --------------------------------------------------------

  Future<void> _addMediaToProject() async {
    if (_selected.isEmpty || _adding) return;
    setState(() => _adding = true);

    try {
      final MediaPickerArgs? pickerArgs = _args;

      final EditorController editor =
          Provider.of<EditorController>(context, listen: false);

      if (pickerArgs != null && pickerArgs.appendToCurrent) {
        for (int i = 0; i < _selected.length; i++) {
          final _Picked p = _selected[i];
          final String? path = p.path ?? (await p.entity?.file)?.path;
          if (path != null && path.isNotEmpty) {
            if (pickerArgs.isOverlay) {
              editor.addOverlayClip(path);
            } else {
              editor.addMediaClip(path);
            }
          }
        }
        if (mounted) {
          Navigator.of(context).pop(true);
        }
        return;
      }

      final List<TimelineClip> clips = <TimelineClip>[];
      Duration offset = Duration.zero;
      final int stamp = DateTime.now().millisecondsSinceEpoch;

      for (int i = 0; i < _selected.length; i++) {
        final _Picked p = _selected[i];
        final String? path = p.path ?? (await p.entity?.file)?.path;
        final bool isAudio = p.type == ClipType.audio;
        final Duration d = _effective(p);

        String name = p.name;
        if (p.entity != null) name = await p.entity!.titleAsync;

        clips.add(TimelineClip(
          id: 'clip_${stamp}_$i',
          label: name,
          start: offset,
          end: offset + d,
          clipType: p.type,
          layerIndex: isAudio ? 1 : 0,
          sourcePath: path,
        ));

        if (!isAudio) offset += d;
      }

      if (!mounted) return;
      final ProjectsController projects =
          Provider.of<ProjectsController>(context, listen: false);

      final newProj = projects.createProject(
        name: _selected.first.name,
        clips: clips,
      );
      editor.loadProject(newProj);

      Navigator.of(context).pushReplacementNamed('/editor');
    } catch (e) {
      _snack('Could not add media: $e');
      if (mounted) setState(() => _adding = false);
    }
  }

  // ---- Build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bool granted = _perm == _Perm.granted;
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _header(),
            if (granted) _tabBar(),
            if (_limited && granted) _limitedBanner(),
            if (granted)
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _monitor(),
              ),
            Expanded(child: _body()),
            if (granted) ...<Widget>[
              if (_selected.isNotEmpty) _tray(),
              _bottomBar(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final String title = _album == null
        ? 'Gallery'
        : (_album!.isAll ? 'Recent' : _album!.name);
    return SizedBox(
      height: 58,
      child: Row(
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.close_rounded, color: _text),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Center(
              child: Material(
                color: _elevated,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _albums.isEmpty ? null : _chooseAlbum,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: _text,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (_albums.isNotEmpty)
                              const Icon(Icons.keyboard_arrow_down_rounded,
                                  color: _text, size: 20),
                          ],
                        ),
                        Text(
                          _contextLabel,
                          style: const TextStyle(
                              color: _muted,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              _cols == 3
                  ? Icons.grid_view_rounded
                  : (_cols == 4 ? Icons.apps_rounded : Icons.grid_on_rounded),
              color: _text,
            ),
            tooltip: 'Grid size',
            onPressed: _cycleDensity,
          ),
          IconButton(
            icon: const Icon(Icons.folder_open_rounded, color: _text),
            tooltip: 'Browse files',
            onPressed: _browseFiles,
          ),
        ],
      ),
    );
  }

  Widget _tabBar() {
    Tab tab(IconData icon, String label) => Tab(
          height: 34,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 16),
                const SizedBox(width: 6),
                Text(label),
              ],
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
      child: TabBar(
        controller: _tabs,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        padding: EdgeInsets.zero,
        indicator: BoxDecoration(
          color: _text,
          borderRadius: BorderRadius.circular(17),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: EdgeInsets.zero,
        labelColor: _onAccent,
        unselectedLabelColor: _muted,
        dividerColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        labelPadding: const EdgeInsets.symmetric(horizontal: 3),
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        tabs: <Widget>[
          tab(Icons.grid_view_rounded, 'All'),
          tab(Icons.videocam_rounded, 'Videos'),
          tab(Icons.image_rounded, 'Photos'),
          tab(Icons.music_note_rounded, 'Audio'),
        ],
      ),
    );
  }

  Widget _limitedBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
      decoration: BoxDecoration(
        color: _elevated,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.info_outline_rounded, size: 16, color: _muted),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Limited access: only selected items are shown.',
                style: TextStyle(color: _muted, fontSize: 12)),
          ),
          TextButton(
            onPressed: () async {
              await PhotoManager.presentLimited();
              _loadAlbums();
            },
            child: const Text('Manage',
                style: TextStyle(color: _accent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  /// Premiere-style "source monitor": large thumbnail plus media info.
  Widget _monitor() {
    final _Picked? f = _focus;
    if (f == null) return const SizedBox(width: double.infinity);
    final bool sel = _indexOf(f.id) >= 0;
    final AssetEntity? e = f.entity;
    final bool hasThumb = e != null && f.type != ClipType.audio;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: SizedBox(
              width: 128,
              height: 72,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (hasThumb)
                    _Thumb(
                      key: ValueKey<String>('mon_${f.id}'),
                      entity: e,
                      size: 480,
                    )
                  else
                    Container(
                      color: _elevated,
                      child: Icon(_typeIcon(f.type),
                          color: _typeColor(f.type), size: 28),
                    ),
                  if (f.type == ClipType.video)
                    Center(
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(140),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 3,
                    child: ColoredBox(color: _typeColor(f.type)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  f.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: _text, fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    _TypePill(type: f.type),
                    const SizedBox(width: 8),
                    Text(
                      _fmt(_effective(f)),
                      style: _timecode.copyWith(
                          color: _muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                if (e != null && f.type != ClipType.audio) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    '${e.width} × ${e.height}',
                    style: _timecode.copyWith(color: _muted, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _toggle(f),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: sel ? Colors.white : _elevated,
                borderRadius: BorderRadius.circular(16),
                border: sel ? null : Border.all(color: _border),
              ),
              child: Text(
                sel ? 'Selected' : 'Select',
                style: TextStyle(
                  color: sel ? Colors.black : _text,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_perm == _Perm.checking) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    if (_perm == _Perm.denied) return _deniedView();

    if (_loading && _assets.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }

    if (_assets.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 84,
              height: 84,
              decoration: const BoxDecoration(
                color: _surface,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.perm_media_outlined,
                  size: 38, color: _muted),
            ),
            const SizedBox(height: 14),
            const Text('Nothing here yet',
                style: TextStyle(
                    color: _text, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              _tabs.index == 3
                  ? 'Audio can be added from your files.'
                  : 'Media you add to this album will show up here.',
              style: const TextStyle(color: _muted, fontSize: 13),
            ),
            if (_tabs.index == 3) ...<Widget>[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _browseFiles,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _text,
                  side: const BorderSide(color: _border),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22)),
                ),
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: const Text('Browse audio files'),
              ),
            ],
          ],
        ),
      );
    }

    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _cols,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: _assets.length,
      itemBuilder: (BuildContext context, int i) {
        final AssetEntity e = _assets[i];
        final int idx = _indexOf(e.id);
        return _Cell(
          key: ValueKey<String>(e.id),
          entity: e,
          order: idx >= 0 ? idx + 1 : null,
          focused: _focus?.id == e.id,
          thumbSize: _thumbSize,
          onTap: () => _toggle(_Picked.fromEntity(e)),
          onLongPress: () => setState(() => _focus = _Picked.fromEntity(e)),
        );
      },
    );
  }

  Widget _deniedView() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: _surface,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.photo_library_outlined,
                  size: 44, color: _accent),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Allow access to your gallery',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: _text, fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            'Photos, videos and audio are shown right here, so you never have to leave the app to pick them.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 28),
          Center(
            child: _GradientButton(
              label: 'Allow access',
              onPressed: _init,
              wide: true,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => PhotoManager.openSetting(),
            child: const Text('Open settings', style: TextStyle(color: _muted)),
          ),
        ],
      ),
    );
  }

  /// Premiere-style sequence strip: reorderable, shows per-clip duration.
  Widget _tray() {
    return Container(
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _border)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: <Widget>[
                const Icon(Icons.view_timeline_rounded,
                    size: 15, color: _muted),
                const SizedBox(width: 6),
                const Text('Sequence',
                    style: TextStyle(
                        color: _text,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                if (_selected.length > 1)
                  const Text('Hold and drag to reorder',
                      style: TextStyle(color: _muted, fontSize: 11)),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => setState(_selected.clear),
                  child: const Text('Clear',
                      style: TextStyle(
                          color: _accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 64,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.only(right: 12),
              itemCount: _selected.length,
              onReorder: _reorder,
              proxyDecorator:
                  (Widget child, int index, Animation<double> animation) =>
                      Material(color: Colors.transparent, child: child),
              itemBuilder: (BuildContext context, int i) => _trayItem(i),
            ),
          ),
        ],
      ),
    );
  }

  Widget _trayItem(int i) {
    final _Picked p = _selected[i];
    final Color tc = _typeColor(p.type);
    final bool hasThumb = p.entity != null && p.type != ClipType.audio;

    return ReorderableDelayedDragStartListener(
      key: ValueKey<String>(p.id),
      index: i,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => setState(() => _focus = p),
          child: SizedBox(
            width: 76,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (hasThumb)
                    _Thumb(entity: p.entity!, size: 200)
                  else
                    Container(
                      color: _elevated,
                      child: Icon(_typeIcon(p.type), color: tc, size: 22),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 3,
                    child: ColoredBox(color: tc),
                  ),
                  Positioned(
                    left: 4,
                    top: 4,
                    child: Container(
                      width: 16,
                      height: 16,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Text('${i + 1}',
                          style: const TextStyle(
                              color: Colors.black,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                  Positioned(
                    left: 5,
                    bottom: 6,
                    child: Text(
                      _fmt(_effective(p)),
                      style: _timecode.copyWith(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        shadows: const <Shadow>[
                          Shadow(color: Colors.black, blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 3,
                    right: 3,
                    child: GestureDetector(
                      onTap: () => _toggle(p),
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(190),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded,
                            size: 12, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final bool enabled = _selected.isNotEmpty && !_adding;
    final int audios =
        _selected.where((_Picked p) => p.type == ClipType.audio).length;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(
        color: _bg,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _selected.isEmpty
                ? const Text('Select items to add',
                    style: TextStyle(color: _muted, fontSize: 13))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        '${_selected.length} selected',
                        style: const TextStyle(
                            color: _text,
                            fontSize: 13,
                            fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_fmt(_totalVideo)} video'
                        '${audios > 0 ? ' · $audios audio' : ''}',
                        style: _timecode.copyWith(
                            color: _muted, fontSize: 11.5),
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: 12),
          _GradientButton(
            label: _ctaLabel,
            onPressed: enabled ? _addMediaToProject : null,
            loading: _adding,
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Small widgets
// -----------------------------------------------------------------------------

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.wide = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final bool on = onPressed != null || loading;
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: on ? Colors.white : _elevated,
          borderRadius: BorderRadius.circular(23),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(23),
          onTap: onPressed,
          child: SizedBox(
            height: 46,
            width: wide ? double.infinity : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (loading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black),
                    )
                  else
                    Text(
                      label,
                      style: TextStyle(
                        color: on ? Colors.black : _muted,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TypePill extends StatelessWidget {
  const _TypePill({required this.type});

  final ClipType type;

  @override
  Widget build(BuildContext context) {
    final Color c = _typeColor(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.withAlpha(36),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(_typeIcon(type), size: 11, color: c),
          const SizedBox(width: 3),
          Text(_typeName(type),
              style: TextStyle(
                  color: c, fontSize: 10.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Grid cell + thumbnail
// -----------------------------------------------------------------------------

class _Cell extends StatelessWidget {
  const _Cell({
    super.key,
    required this.entity,
    required this.order,
    required this.focused,
    required this.thumbSize,
    required this.onTap,
    required this.onLongPress,
  });

  final AssetEntity entity;
  final int? order;
  final bool focused;
  final int thumbSize;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final bool sel = order != null;
    final bool isAudio = entity.type == AssetType.audio;
    final bool hasDuration = entity.type != AssetType.image;
    final Color tc = _typeColor(_clipOf(entity.type));

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (isAudio)
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0xFF26221C), Color(0xFF17150F)],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _WavePainter(
                        seed: entity.id.hashCode & 0x7fffffff,
                        color: _cAudio,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(entity.title ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _text, fontSize: 10)),
                ],
              ),
            )
          else
            _Thumb(entity: entity, size: thumbSize),

          // Dim + frame when selected.
          if (sel) Container(color: Colors.black.withAlpha(95)),
          if (sel || focused)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: sel ? _accent : Colors.white.withAlpha(150),
                      width: sel ? 2.5 : 1.5,
                    ),
                  ),
                ),
              ),
            ),

          // Premiere-style label strip for the media type.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 3,
            child: ColoredBox(color: tc),
          ),

          if (hasDuration)
            Positioned(
              left: 4,
              bottom: 7,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(150),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _fmt(entity.videoDuration),
                  style: _timecode.copyWith(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),

          // Selection badge.
          Positioned(
            top: 5,
            right: 5,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: sel ? Colors.white : Colors.black.withAlpha(90),
                border: sel
                    ? null
                    : Border.all(color: Colors.white, width: 1.5),
              ),
              child: sel
                  ? Center(
                      child: Text('$order',
                          style: const TextStyle(
                              color: Colors.black,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800)),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.seed, required this.color});

  final int seed;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.4;
    const int bars = 13;
    final double gap = size.width / bars;
    int r = seed;
    for (int i = 0; i < bars; i++) {
      r = (r * 1103515245 + 12345) & 0x7fffffff;
      final double h = 0.22 + (r % 100) / 100 * 0.78;
      final double x = gap * i + gap / 2;
      final double half = size.height * h / 2;
      canvas.drawLine(
        Offset(x, size.height / 2 - half),
        Offset(x, size.height / 2 + half),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.seed != seed || old.color != color;
}

class _Thumb extends StatefulWidget {
  const _Thumb({super.key, required this.entity, required this.size});

  final AssetEntity entity;
  final int size;

  @override
  State<_Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<_Thumb> {
  Uint8List? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _Thumb old) {
    super.didUpdateWidget(old);
    if (old.entity.id != widget.entity.id || old.size != widget.size) {
      if (old.entity.id != widget.entity.id) _data = null;
      _load();
    }
  }

  Future<void> _load() async {
    final String id = widget.entity.id;
    final Uint8List? d = await widget.entity
        .thumbnailDataWithSize(ThumbnailSize.square(widget.size));
    if (mounted && id == widget.entity.id) setState(() => _data = d);
  }

  @override
  Widget build(BuildContext context) {
    if (_data == null) return const ColoredBox(color: _elevated);
    return Image.memory(_data!, fit: BoxFit.cover, gaplessPlayback: true);
  }
}