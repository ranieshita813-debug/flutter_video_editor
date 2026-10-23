import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/core/services/media_optimization_service.dart';
import 'package:flutter_video_editor/core/widgets/loading_wave.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_sheets/editor_tool_sheets.dart';
import 'package:flutter_video_editor/features/projects/controllers/projects_controller.dart';

// -----------------------------------------------------------------------------
// Design tokens (monochrome, matches the rest of the app)
// -----------------------------------------------------------------------------

const Color _bg = Color(0xFFFFFFFF);
const Color _surface = Color(0xFFF5F5F5);
const Color _elevated = Color(0xFFEBEBEB);
const Color _text = Color(0xFF000000);
const Color _muted = Color(0xFF6B6B6B);
const Color _accent = Color(0xFF000000);
const Color _onAccent = Color(0xFFFFFFFF);

const TextStyle _timecode = TextStyle(
  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
);

const List<String> _videoExt = <String>[
  'mp4', 'mov', 'avi', 'mkv', 'webm', '3gp', 'm4v',
];
const List<String> _audioExt = <String>[
  'mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg',
];
const List<String> _imageExt = <String>[
  'jpg', 'jpeg', 'png', 'webp', 'heic', 'gif',
];

String _fmt(Duration d) {
  final int s = d.inSeconds;
  final int h = s ~/ 3600;
  final String mm = ((s % 3600) ~/ 60).toString();
  final String ss = (s % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${mm.padLeft(2, '0')}:$ss' : '$mm:$ss';
}

IconData _typeIcon(ClipType t) => switch (t) {
      ClipType.video => PhosphorIconsBold.videoCamera,
      ClipType.audio => PhosphorIconsBold.musicNote,
      _ => PhosphorIconsBold.image,
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
  String? _error;
  int _page = 0;
  int _gen = 0;
  int _lastTab = 0;

  /// Grid density (3, 4 or 5 columns).
  int _cols = 3;

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

  /// Clears the grid and invalidates any in-flight page request.
  int _resetGrid() {
    final int gen = ++_gen;
    _busy = false;
    _assets.clear();
    _page = 0;
    _hasMore = true;
    _error = null;
    _loading = true;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    return gen;
  }

  Future<void> _loadAlbums() async {
    late final int gen;
    setState(() => gen = _resetGrid());

    try {
      final List<AssetPathEntity> albums =
          await PhotoManager.getAssetPathList(type: _type, onlyAll: false);
      if (!mounted || gen != _gen) return;
      setState(() {
        _albums = albums;
        _album = albums.isNotEmpty ? albums.first : null;
        _hasMore = _album != null;
        if (_album == null) _loading = false;
      });
      await _loadMore();
    } catch (e) {
      if (mounted && gen == _gen) {
        setState(() {
          _loading = false;
          _error = 'Couldn\'t load your gallery. Try again.';
        });
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
        setState(() {
          _loading = false;
          _error = 'Couldn\'t load media. Try again.';
        });
      }
    } finally {
      if (gen == _gen) _busy = false;
    }
  }

  Future<void> _chooseAlbum() async {
    final AssetPathEntity? picked = await showModalBottomSheet<AssetPathEntity>(
      context: context,
      backgroundColor: _bg,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                      color: _text, fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  for (final AssetPathEntity a in _albums)
                    ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: a.id == _album?.id ? _accent : _surface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          a.isAll
                              ? PhosphorIconsRegular.clockCounterClockwise
                              : PhosphorIconsRegular.folder,
                          size: 20,
                          color: a.id == _album?.id ? _onAccent : _muted,
                        ),
                      ),
                      title: Text(a.isAll ? 'Recent' : a.name,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                      trailing: FutureBuilder<int>(
                        future: a.assetCountAsync,
                        builder: (_, AsyncSnapshot<int> s) => Text(
                            s.hasData ? '${s.data}' : '',
                            style: _timecode.copyWith(
                                color: _muted, fontSize: 13)),
                      ),
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
    late final int gen;
    setState(() {
      gen = _resetGrid();
      _album = picked;
    });
    if (gen == _gen) await _loadMore();
  }

  // ---- Selection -------------------------------------------------------------

  int _indexOf(String id) => _selected.indexWhere((p) => p.id == id);

  /// Reuses the already-selected object so name/path stay consistent.
  _Picked _pickedOf(AssetEntity e) {
    final int i = _indexOf(e.id);
    return i >= 0 ? _selected[i] : _Picked.fromEntity(e);
  }

  void _toggle(_Picked p) {
    HapticFeedback.selectionClick();
    setState(() {
      final int i = _indexOf(p.id);
      if (i >= 0) {
        _selected.removeAt(i);
      } else {
        _selected.add(p);
        if (p.entity != null && p.entity!.width > 0 && p.entity!.height > 0) {
          canvasRatioNotifier.value = detectCanvasRatio(p.entity!.width, p.entity!.height);
        }
      }
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

  /// Duration used for a clip on the timeline.
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
        type: FileType.custom,
        allowedExtensions: <String>[
          ..._videoExt,
          ..._audioExt,
          ..._imageExt,
        ],
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;

      int skipped = 0;
      setState(() {
        for (final PlatformFile file in result.files) {
          final String ext = file.extension?.toLowerCase() ?? '';
          final bool isVid = _videoExt.contains(ext);
          final bool isAud = _audioExt.contains(ext);
          final bool isImg = _imageExt.contains(ext);
          if (file.path == null || !(isVid || isAud || isImg)) {
            skipped++;
            continue;
          }
          final String id = 'file_${file.path}';
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
      if (skipped > 0) {
        _snack('$skipped file${skipped == 1 ? '' : 's'} not supported');
      }
    } catch (e) {
      _snack('Couldn\'t open that file');
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(m, style: const TextStyle(color: _onAccent)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _text,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
  }

  // ---- Preview ---------------------------------------------------------------

  Future<void> _preview(_Picked p) async {
    HapticFeedback.mediumImpact();
    final AssetEntity? e = p.entity;
    final bool isAudio = p.type == ClipType.audio;
    final double aspect = (e != null && e.width > 0 && e.height > 0)
        ? (e.width / e.height).clamp(0.6, 1.8)
        : 16 / 9;
    final double maxH = MediaQuery.of(context).size.height * 0.5;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _bg,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext ctx) {
        final bool sel = _indexOf(p.id) >= 0;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxH),
                    child: AspectRatio(
                      aspectRatio: isAudio ? 16 / 9 : aspect,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            if (e != null && !isAudio)
                              _Thumb(entity: e, size: 900)
                            else
                              Container(
                                color: _surface,
                                child: Icon(_typeIcon(p.type),
                                    color: _muted, size: 44),
                              ),
                            if (p.type == ClipType.video)
                              Center(
                                child: Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withAlpha(150),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(PhosphorIconsRegular.play,
                                      color: Colors.white, size: 26),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: _text,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    _TypePill(type: p.type),
                    const SizedBox(width: 10),
                    if (p.type != ClipType.image)
                      Text(_fmt(_effective(p)),
                          style: _timecode.copyWith(
                              color: _muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    if (e != null && !isAudio) ...<Widget>[
                      const SizedBox(width: 10),
                      Text('${e.width} × ${e.height}',
                          style: _timecode.copyWith(
                              color: _muted, fontSize: 13)),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                _PrimaryButton(
                  label: sel ? 'Remove from selection' : 'Select',
                  wide: true,
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _toggle(p);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---- Add to project --------------------------------------------------------

  Future<String?> _resolvePath(_Picked p) async {
    if (p.path != null) return p.path;
    final AssetEntity? e = p.entity;
    if (e == null) return null;
    // `file` can be null for cloud/transcoded items; fall back to the original.
    final f = (await e.file) ?? (await e.originFile);
    return f?.path;
  }

  Future<List<String>> _resolveAllSelectedPaths() async {
    final paths = <String>[];
    for (final p in _selected) {
      final path = await _resolvePath(p);
      if (path != null && path.isNotEmpty) {
        paths.add(path);
      }
    }
    return paths;
  }

  Future<void> _addMediaToProject() async {
    if (_selected.isEmpty || _adding) return;
    setState(() => _adding = true);

    try {
      final paths = await _resolveAllSelectedPaths();
      if (paths.isEmpty) {
        _snack('Couldn\'t read the selected media');
        setState(() => _adding = false);
        return;
      }

      double progressValue = 0.0;
      String progressMsg = 'Optimizing media…';
      void Function(void Function())? dialogStateSetter;

      if (!mounted) return;

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.8),
        builder: (ctx) {
          return StatefulBuilder(
            builder: (context, setSt) {
              dialogStateSetter = setSt;
              return Dialog(
                backgroundColor: const Color(0xFF1C1C1C),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 72,
                        height: 72,
                        child: CircularProgressIndicator(
                          value: progressValue > 0 ? progressValue : null,
                          strokeWidth: 4.5,
                          backgroundColor: const Color(0xFF333333),
                          color: const Color(0xFFFFD700),
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextShimmerWave(
                        progressMsg,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        baseColor: const Color(0xFF888888),
                        waveColor: Colors.white,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );

      final optimizer = MediaOptimizationService();
      final optimized = await optimizer.optimizeMedia(
        paths,
        onProgress: (prog) {
          if (mounted && dialogStateSetter != null) {
            dialogStateSetter!(() {
              progressValue = prog.progress;
              progressMsg = prog.message;
            });
          }
        },
      );

      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      final Map<String, OptimizedMediaItem> optMap = {
        for (final item in optimized) item.originalPath: item
      };

      if (!mounted) return;

      final MediaPickerArgs? pickerArgs = _args;
      final EditorController editor = Provider.of<EditorController>(context, listen: false);

      if (pickerArgs != null && pickerArgs.appendToCurrent) {
        for (final _Picked p in List<_Picked>.of(_selected)) {
          final String? path = await _resolvePath(p);
          if (path == null || path.isEmpty) continue;
          final optItem = optMap[path];
          Duration? customDur;
          if (optItem?.durationMs != null && optItem!.durationMs! > 0) {
            customDur = Duration(milliseconds: optItem.durationMs!);
          }

          if (p.type == ClipType.audio) {
            editor.addAudioTrack(
              path,
              trackName: p.name,
              duration: customDur ?? (p.duration > Duration.zero ? p.duration : null),
            );
          } else if (pickerArgs.isOverlay) {
            editor.addOverlayClip(path);
          } else {
            editor.addMediaClip(path);
          }
        }
        if (!mounted) return;
        Navigator.of(context).pop(true);
        return;
      }

      if (_selected.isNotEmpty) {
        final firstWithDim = _selected.firstWhere(
          (p) => p.entity != null && p.entity!.width > 0,
          orElse: () => _selected.first,
        );
        if (firstWithDim.entity != null &&
            firstWithDim.entity!.width > 0 &&
            firstWithDim.entity!.height > 0) {
          canvasRatioNotifier.value = detectCanvasRatio(
            firstWithDim.entity!.width,
            firstWithDim.entity!.height,
          );
        }
      }

      final List<TimelineClip> clips = <TimelineClip>[];
      Duration offset = Duration.zero;
      final int stamp = DateTime.now().millisecondsSinceEpoch;

      for (int i = 0; i < _selected.length; i++) {
        final _Picked p = _selected[i];
        final String? path = await _resolvePath(p);
        if (path == null || path.isEmpty) continue;

        final optItem = optMap[path];
        final bool isAudio = p.type == ClipType.audio;
        Duration d = _effective(p);
        if (optItem?.durationMs != null && optItem!.durationMs! > 0) {
          d = Duration(milliseconds: optItem.durationMs!);
        }

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
      if (clips.isEmpty) {
        _snack('Couldn\'t read the selected media');
        setState(() => _adding = false);
        return;
      }

      final ProjectsController projects = Provider.of<ProjectsController>(context, listen: false);
      final newProj = projects.createProject(
        name: _selected.first.name,
        clips: clips,
      );
      editor.loadProject(newProj);

      Navigator.of(context).pushReplacementNamed('/editor');
    } catch (e) {
      _snack('Couldn\'t add media. Try again.');
      if (mounted) setState(() => _adding = false);
    }
  }

  // ---- Build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bool granted = _perm == _Perm.granted;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: _bg,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: _bg,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: _bg,
      ),
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Column(
            children: <Widget>[
              _header(),
              if (granted) _tabBar(),
              if (_limited && granted) _limitedBanner(),
              Expanded(child: _body()),
              if (granted) _dock(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final String title = _album == null
        ? 'Gallery'
        : (_album!.isAll ? 'Recent' : _album!.name);
    return SizedBox(
      height: 60,
      child: Row(
        children: <Widget>[
          IconButton(
            icon: const Icon(PhosphorIconsBold.x, color: _text),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Center(
              child: Material(
                color: _surface,
                borderRadius: BorderRadius.circular(22),
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: _albums.isEmpty ? null : _chooseAlbum,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                            if (_albums.isNotEmpty) ...<Widget>[
                              const SizedBox(width: 2),
                              const Icon(PhosphorIconsBold.caretDown,
                                  color: _text, size: 16),
                            ],
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
            icon: const Icon(PhosphorIconsBold.folderOpen, color: _text),
            tooltip: 'Browse files',
            onPressed: _browseFiles,
          ),
        ],
      ),
    );
  }

  Widget _tabBar() {
    Tab tab(IconData icon, String label) => Tab(
          height: 36,
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
      padding: const EdgeInsets.fromLTRB(10, 0, 4, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              padding: EdgeInsets.zero,
              indicator: BoxDecoration(
                color: _text,
                borderRadius: BorderRadius.circular(18),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: EdgeInsets.zero,
              labelColor: _onAccent,
              unselectedLabelColor: _muted,
              dividerColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              labelPadding: const EdgeInsets.symmetric(horizontal: 3),
              labelStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              unselectedLabelStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              tabs: <Widget>[
                tab(PhosphorIconsBold.gridFour, 'All'),
                tab(PhosphorIconsBold.videoCamera, 'Videos'),
                tab(PhosphorIconsBold.image, 'Photos'),
                tab(PhosphorIconsBold.musicNote, 'Audio'),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              _cols == 3
                  ? PhosphorIconsBold.gridFour
                  : (_cols == 4
                      ? PhosphorIconsBold.squaresFour
                      : PhosphorIconsBold.gridNine),
              color: _text,
              size: 22,
            ),
            tooltip: 'Grid size',
            onPressed: _cycleDensity,
          ),
        ],
      ),
    );
  }

  Widget _limitedBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          const Icon(PhosphorIconsRegular.info, size: 16, color: _muted),
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

  Widget _body() {
    if (_perm == _Perm.checking) {
      return const Center(child: TextShimmerWave('Checking permissions…'));
    }
    if (_perm == _Perm.denied) return _deniedView();

    if (_error != null && _assets.isEmpty) {
      return _message(
        icon: PhosphorIconsRegular.warningCircle,
        title: _error!,
        action: 'Retry',
        onAction: _loadAlbums,
      );
    }

    if (_loading && _assets.isEmpty) {
      return const Center(child: TextShimmerWave('Loading media…'));
    }

    if (_assets.isEmpty) {
      final bool audioTab = _tabs.index == 3;
      return _message(
        icon: audioTab
            ? PhosphorIconsRegular.musicNote
            : PhosphorIconsRegular.images,
        title: audioTab ? 'No audio in your gallery' : 'Nothing here yet',
        body: audioTab
            ? 'Add music or voice recordings from your files.'
            : 'Media you add to this album will show up here.',
        action: audioTab ? 'Browse audio files' : null,
        onAction: audioTab ? _browseFiles : null,
      );
    }

    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 12),
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
          thumbSize: _thumbSize,
          onTap: () => _toggle(_pickedOf(e)),
          onLongPress: () => _preview(_pickedOf(e)),
        );
      },
    );
  }

  Widget _message({
    required IconData icon,
    required String title,
    String? body,
    String? action,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
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
              child: Icon(icon, size: 38, color: _muted),
            ),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: _text, fontSize: 16, fontWeight: FontWeight.w700)),
            if (body != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _muted, fontSize: 13)),
            ],
            if (action != null) ...<Widget>[
              const SizedBox(height: 18),
              _PrimaryButton(label: action, onPressed: onAction),
            ],
          ],
        ),
      ),
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
              child: const Icon(PhosphorIconsRegular.images,
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
            'Photos, videos and audio show up right here, so you never have to leave the app to pick them.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 28),
          _PrimaryButton(label: 'Allow access', onPressed: _init, wide: true),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => PhotoManager.openSetting(),
            child: const Text('Open settings', style: TextStyle(color: _muted)),
          ),
        ],
      ),
    );
  }

  // ---- Bottom dock: sequence tray + action bar --------------------------------

  Widget _dock() {
    return Container(
      decoration: const BoxDecoration(
        color: _bg,
        border: Border(top: BorderSide(color: _elevated)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _selected.isEmpty
                ? const SizedBox(width: double.infinity)
                : _tray(),
          ),
          _actionBar(),
        ],
      ),
    );
  }

  Widget _tray() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 0, 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: <Widget>[
                const Text('Sequence',
                    style: TextStyle(
                        color: _text,
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
                const Spacer(),
                if (_selected.length > 1)
                  const Text('Hold and drag to reorder',
                      style: TextStyle(color: _muted, fontSize: 11)),
                const SizedBox(width: 12),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(_selected.clear),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('Clear',
                        style: TextStyle(
                            color: _text,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline)),
                  ),
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
              // ignore: deprecated_member_use
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
    final bool hasThumb = p.entity != null && p.type != ClipType.audio;

    return ReorderableDelayedDragStartListener(
      key: ValueKey<String>(p.id),
      index: i,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => _preview(p),
          child: SizedBox(
            width: 64,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (hasThumb)
                    _Thumb(entity: p.entity!, size: 200)
                  else
                    Container(
                      color: _surface,
                      child: Icon(_typeIcon(p.type), color: _muted, size: 22),
                    ),
                  // Soft scrim so the timecode stays readable on any photo.
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 24,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[Colors.transparent, Color(0xAA000000)],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 5,
                    bottom: 4,
                    child: Text(
                      _fmt(_effective(p)),
                      style: _timecode.copyWith(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 4,
                    top: 4,
                    child: _NumberBadge(number: i + 1, size: 18, fontSize: 10),
                  ),
                  Positioned(
                    top: 3,
                    right: 3,
                    child: GestureDetector(
                      onTap: () => _toggle(p),
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(180),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(PhosphorIconsBold.x,
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

  Widget _actionBar() {
    final bool enabled = _selected.isNotEmpty && !_adding;
    final int audios =
        _selected.where((_Picked p) => p.type == ClipType.audio).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _selected.isEmpty
                ? const Text('Tap to select · hold to preview',
                    style: TextStyle(color: _muted, fontSize: 13))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        '${_selected.length} selected',
                        style: const TextStyle(
                            color: _text,
                            fontSize: 14,
                            fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_fmt(_totalVideo)} video'
                        '${audios > 0 ? ' · $audios audio' : ''}',
                        style:
                            _timecode.copyWith(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: 12),
          _PrimaryButton(
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

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
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
          color: on ? _text : _elevated,
          borderRadius: BorderRadius.circular(999),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: loading ? null : onPressed,
          child: SizedBox(
            height: 48,
            width: wide ? double.infinity : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (loading)
                    TextShimmerWave(
                      'Adding…',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                      baseColor: _onAccent.withAlpha(128),
                      waveColor: _onAccent,
                    )
                  else
                    Text(
                      label,
                      style: TextStyle(
                        color: on ? _onAccent : _muted,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(_typeIcon(type), size: 12, color: _text),
          const SizedBox(width: 4),
          Text(_typeName(type),
              style: const TextStyle(
                  color: _text, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Black circle with a white ring and white number: readable on any thumbnail.
class _NumberBadge extends StatelessWidget {
  const _NumberBadge({
    required this.number,
    this.size = 22,
    this.fontSize = 11.5,
  });

  final int number;
  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _text,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Text('$number',
          style: TextStyle(
              color: _onAccent,
              fontSize: fontSize,
              height: 1,
              fontWeight: FontWeight.w800)),
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
    required this.thumbSize,
    required this.onTap,
    required this.onLongPress,
  });

  final AssetEntity entity;
  final int? order;
  final int thumbSize;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final bool sel = order != null;
    final bool isAudio = entity.type == AssetType.audio;
    final bool isVideo = entity.type == AssetType.video;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // The thumbnail shrinks slightly when selected: a clear state change
          // that doesn't depend on color.
          AnimatedPadding(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            padding: EdgeInsets.all(sel ? 6 : 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(sel ? 8 : 0),
              child: isAudio
                  ? _audioTile()
                  : _Thumb(entity: entity, size: thumbSize),
            ),
          ),

          if (isVideo || isAudio)
            Positioned(
              left: sel ? 10 : 4,
              bottom: sel ? 10 : 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(150),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      isVideo
                          ? PhosphorIconsFill.play
                          : PhosphorIconsBold.musicNote,
                      size: 10,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      _fmt(entity.videoDuration),
                      style: _timecode.copyWith(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          Positioned(
            top: sel ? 9 : 5,
            right: sel ? 9 : 5,
            child: sel
                ? _NumberBadge(number: order!)
                : Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withAlpha(60),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _audioTile() {
    return Container(
      color: _surface,
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
      child: Column(
        children: <Widget>[
          Expanded(
            child: CustomPaint(
              size: Size.infinite,
              painter: _WavePainter(
                seed: entity.id.hashCode & 0x7fffffff,
                color: const Color(0xFF9A9A9A),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(entity.title ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _text, fontSize: 10)),
          const SizedBox(height: 14),
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
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 120),
      child: _data == null
          ? const ColoredBox(
              key: ValueKey<int>(0),
              color: _surface,
            )
          : Image.memory(
              _data!,
              key: const ValueKey<int>(1),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              width: double.infinity,
              height: double.infinity,
            ),
    );
  }
}