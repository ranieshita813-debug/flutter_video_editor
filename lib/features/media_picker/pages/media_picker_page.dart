import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/projects/controllers/projects_controller.dart';

// -----------------------------------------------------------------------------
// Tokens (monochrome, CapCut-like)
// -----------------------------------------------------------------------------

const Color _bg = Color(0xFF000000);
const Color _surface = Color(0xFF111111);
const Color _elevated = Color(0xFF1C1C1C);
const Color _border = Color(0xFF2A2A2A);
const Color _text = Color(0xFFFFFFFF);
const Color _muted = Color(0xFF8C8C8C);
const Color _accent = Color(0xFFFFFFFF); // white accent (monochrome)
const Color _onAccent = Color(0xFF000000);

String _fmt(Duration d) {
  final int s = d.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
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
        type: e.type == AssetType.video
            ? ClipType.video
            : (e.type == AssetType.audio ? ClipType.audio : ClipType.image),
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

  List<AssetPathEntity> _albums = <AssetPathEntity>[];
  AssetPathEntity? _album;

  RequestType get _type => switch (_tabs.index) {
        0 => RequestType.common,
        1 => RequestType.video,
        2 => RequestType.image,
        _ => RequestType.audio,
      };

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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (BuildContext sheetCtx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            for (final AssetPathEntity a in _albums)
              ListTile(
                title: Text(a.isAll ? 'Recent' : a.name,
                    style: const TextStyle(color: _text, fontSize: 15)),
                trailing: FutureBuilder<int>(
                  future: a.assetCountAsync,
                  builder: (_, AsyncSnapshot<int> s) => Text('${s.data ?? ''}',
                      style: const TextStyle(color: _muted, fontSize: 13)),
                ),
                selected: a.id == _album?.id,
                selectedColor: _accent,
                onTap: () => Navigator.of(sheetCtx).pop(a),
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
    });
  }

  /// Fallback for audio on platforms where the gallery can't list it (iOS),
  /// or for files outside the media library.
  Future<void> _browseFiles() async {
    try {
      final FilePickerResult? res = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
      );
      if (res == null || res.files.isEmpty) return;
      final List<PlatformFile> files = res.files;
      setState(() {
        for (final PlatformFile file in files) {
          final String ext = file.extension?.toLowerCase() ?? '';
          final bool isVid =
              <String>['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'].contains(ext);
          final bool isAud =
              <String>['mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg'].contains(ext);
          final String id = 'file_${file.path ?? file.name}';
          if (_indexOf(id) >= 0) continue;
          _selected.add(_Picked(
            id: id,
            name: file.name,
            duration: isVid
                ? const Duration(seconds: 10)
                : (isAud ? const Duration(seconds: 15) : Duration.zero),
            type: isVid
                ? ClipType.video
                : (isAud ? ClipType.audio : ClipType.image),
            path: file.path,
          ));
        }
      });
    } catch (e) {
      _snack('Error picking file: $e');
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ---- Add to project --------------------------------------------------------

  Future<void> _addMediaToProject() async {
    if (_selected.isEmpty || _adding) return;
    setState(() => _adding = true);

    try {
      final List<TimelineClip> clips = <TimelineClip>[];
      Duration offset = Duration.zero;
      final int stamp = DateTime.now().millisecondsSinceEpoch;

      for (int i = 0; i < _selected.length; i++) {
        final _Picked p = _selected[i];
        final String? path = p.path ?? (await p.entity?.file)?.path;
        final bool isAudio = p.type == ClipType.audio;
        final bool isVideo = p.type == ClipType.video;

        final Duration d = (isVideo || isAudio) && p.duration > Duration.zero
            ? p.duration
            : (isAudio
                ? const Duration(seconds: 15)
                : (isVideo
                    ? const Duration(seconds: 10)
                    : const Duration(seconds: 4)));

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
      final EditorController editor =
          Provider.of<EditorController>(context, listen: false);

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
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _header(),
            if (_perm == _Perm.granted) _tabBar(),
            if (_limited && _perm == _Perm.granted) _limitedBanner(),
            Expanded(child: _body()),
            if (_perm == _Perm.granted) ...<Widget>[
              if (_selected.isNotEmpty) _tray(),
              _bottomBar(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return SizedBox(
      height: 52,
      child: Row(
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.close_rounded, color: _text),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Center(
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _albums.isEmpty ? null : _chooseAlbum,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        _album == null
                            ? 'Gallery'
                            : (_album!.isAll ? 'Recent' : _album!.name),
                        style: const TextStyle(
                            color: _text,
                            fontSize: 16,
                            fontWeight: FontWeight.w700),
                      ),
                      if (_albums.isNotEmpty)
                        const Icon(Icons.keyboard_arrow_down_rounded,
                            color: _text),
                    ],
                  ),
                ),
              ),
            ),
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
    return TabBar(
      controller: _tabs,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      indicatorColor: _accent,
      indicatorWeight: 2,
      indicatorSize: TabBarIndicatorSize.label,
      labelColor: _text,
      unselectedLabelColor: _muted,
      dividerColor: _border,
      overlayColor: WidgetStateProperty.all(Colors.transparent),
      labelPadding: const EdgeInsets.symmetric(horizontal: 18),
      labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      unselectedLabelStyle:
          const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      tabs: const <Widget>[
        Tab(text: 'All'),
        Tab(text: 'Videos'),
        Tab(text: 'Photos'),
        Tab(text: 'Audio'),
      ],
    );
  }

  Widget _limitedBanner() {
    return Container(
      color: _elevated,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
            child: const Text('Manage', style: TextStyle(color: _text)),
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
            const Icon(Icons.perm_media_outlined, size: 56, color: _muted),
            const SizedBox(height: 12),
            const Text('Nothing here yet',
                style: TextStyle(color: _muted, fontSize: 15)),
            if (_tabs.index == 3) ...<Widget>[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _browseFiles,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _text,
                  side: const BorderSide(color: _border),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
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
      padding: const EdgeInsets.all(1),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 1,
        mainAxisSpacing: 1,
      ),
      itemCount: _assets.length,
      itemBuilder: (BuildContext context, int i) {
        final AssetEntity e = _assets[i];
        final int idx = _indexOf(e.id);
        return _Cell(
          key: ValueKey<String>(e.id),
          entity: e,
          order: idx >= 0 ? idx + 1 : null,
          onTap: () => _toggle(_Picked.fromEntity(e)),
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
          const Icon(Icons.photo_library_outlined, size: 56, color: _muted),
          const SizedBox(height: 16),
          const Text('Allow access to your gallery',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: _text, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
            'Photos, videos and audio are shown right here, so you never have to leave the app to pick them.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 13),
          ),
          const SizedBox(height: 28),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: _onAccent,
              elevation: 0,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
            ),
            onPressed: _init,
            child: const Text('Allow access',
                style: TextStyle(fontWeight: FontWeight.w700)),
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

  Widget _tray() {
    return Container(
      height: 76,
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        itemCount: _selected.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int i) {
          final _Picked p = _selected[i];
          return SizedBox(
            width: 56,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (p.entity != null && p.type != ClipType.audio)
                    _Thumb(entity: p.entity!, size: 160)
                  else
                    Container(
                      color: _elevated,
                      child: Icon(
                        p.type == ClipType.audio
                            ? Icons.music_note_rounded
                            : Icons.image_outlined,
                        color: _muted,
                        size: 22,
                      ),
                    ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: GestureDetector(
                      onTap: () => _toggle(p),
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(200),
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
          );
        },
      ),
    );
  }

  Widget _bottomBar() {
    final bool enabled = _selected.isNotEmpty && !_adding;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(
        color: _bg,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              _selected.isEmpty
                  ? 'Select items to add'
                  : '${_selected.length} selected',
              style: const TextStyle(color: _muted, fontSize: 13),
            ),
          ),
          SizedBox(
            height: 42,
            child: ElevatedButton(
              onPressed: enabled ? _addMediaToProject : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: _onAccent,
                disabledBackgroundColor: _elevated,
                disabledForegroundColor: _muted,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 28),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(21)),
              ),
              child: _adding
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _onAccent),
                    )
                  : Text('Add (${_selected.length})',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
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
    required this.onTap,
  });

  final AssetEntity entity;
  final int? order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool sel = order != null;
    final bool isAudio = entity.type == AssetType.audio;
    final bool hasDuration = entity.type != AssetType.image;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (isAudio)
            Container(
              color: _elevated,
              padding: const EdgeInsets.all(6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Icon(Icons.music_note_rounded, color: _muted, size: 26),
                  const SizedBox(height: 4),
                  Text(entity.title ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _text, fontSize: 10)),
                ],
              ),
            )
          else
            _Thumb(entity: entity, size: 300),
          if (sel) Container(color: Colors.black.withAlpha(110)),
          if (sel)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration:
                      BoxDecoration(border: Border.all(color: _accent, width: 2)),
                ),
              ),
            ),
          if (hasDuration)
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(150),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  _fmt(entity.videoDuration),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          Positioned(
            top: 5,
            right: 5,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: sel ? _accent : Colors.black.withAlpha(90),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: sel
                  ? Center(
                      child: Text('$order',
                          style: const TextStyle(
                              color: _onAccent,
                              fontSize: 11,
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

class _Thumb extends StatefulWidget {
  const _Thumb({required this.entity, required this.size});

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
    if (old.entity.id != widget.entity.id) {
      _data = null;
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