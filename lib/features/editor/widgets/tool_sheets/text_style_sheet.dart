// lib/features/editor/widgets/text_style_sheet.dart
//
// Text style tool, CapCut x Premiere Pro hybrid (same language as
// AdjustSheet / SpeedSheet).
//  - CapCut: underline tabs (Font / Effects / Color / Layout), visual
//    tiles for fonts and effect presets, round color swatches.
//  - Premiere: hairline section bars, boxed scrubbable value fields,
//    triangle-thumb sliders, joined icon segmented control.
//
// Font tab: filter chips (All / Imported / Sans / Serif / Display / Script /
// Mono) and an "Import" tile that loads a .ttf / .otf from the device.
// Search has been removed.
//
// New dependencies (pubspec.yaml):
//   file_picker: ^8.0.0
//   path_provider: ^2.1.0
//   path: ^1.9.0

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';

const Color _card = Color(0xFF232327);
const Color _field = Color(0xFF18181B);
const Color _line = Color(0xFF2C2C31);
const Color _track = Color(0xFF45454C);
const Color _accent = Color(0xFF2DE2E6);

// ----------------------------------------------------------------------------
// Imported font library
// ----------------------------------------------------------------------------

@immutable
class ImportedFont {
  const ImportedFont({required this.name, required this.path});
  final String name;
  final String path;

  Map<String, dynamic> toJson() => <String, dynamic>{'name': name, 'path': path};

  static ImportedFont? fromJson(Object? j) {
    if (j is! Map) return null;
    final Object? n = j['name'];
    final Object? f = j['path'];
    if (n is String && f is String) return ImportedFont(name: n, path: f);
    return null;
  }
}

/// Keeps fonts the user imported from local storage.
///
/// Files are copied into `<documents>/imported_fonts/`, registered with the
/// engine through [FontLoader] (so `TextStyle(fontFamily: name)` works
/// everywhere, including the preview), and listed in `index.json` so they
/// survive restarts. Use [pathFor] when exporting with FFmpeg's drawtext
/// (`fontfile=`).
class FontLibrary extends ChangeNotifier {
  FontLibrary._();
  static final FontLibrary instance = FontLibrary._();

  final List<ImportedFont> _fonts = <ImportedFont>[];
  Future<void>? _init;

  List<ImportedFont> get fonts => List<ImportedFont>.unmodifiable(_fonts);
  bool has(String name) => _fonts.any((f) => f.name == name);
  String? pathFor(String name) {
    for (final f in _fonts) {
      if (f.name == name) return f.path;
    }
    return null;
  }

  Future<Directory> _dir() async {
    final Directory root = await getApplicationDocumentsDirectory();
    final Directory d = Directory(p.join(root.path, 'imported_fonts'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<void> init() => _init ??= _load();

  Future<void> _load() async {
    try {
      final Directory d = await _dir();
      final File index = File(p.join(d.path, 'index.json'));
      if (!await index.exists()) return;
      final Object? raw = jsonDecode(await index.readAsString());
      if (raw is! List) return;
      for (final Object? e in raw) {
        final ImportedFont? f = ImportedFont.fromJson(e);
        if (f == null || !await File(f.path).exists()) continue;
        try {
          await _register(f.name, f.path);
          _fonts.add(f);
        } catch (e) {
          debugPrint('Skipping broken font ${f.name}: $e');
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Font library load failed: $e');
    }
  }

  Future<void> _register(String name, String path) async {
    final Uint8List bytes = await File(path).readAsBytes();
    final FontLoader loader = FontLoader(name)
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
  }

  Future<void> _save() async {
    final Directory d = await _dir();
    await File(p.join(d.path, 'index.json')).writeAsString(
      jsonEncode(_fonts.map((f) => f.toJson()).toList()),
    );
  }

  /// Opens the system file picker. Returns the imported font, or null when
  /// the user cancelled. Throws [FormatException] with a readable message
  /// when the file can't be used.
  Future<ImportedFont?> importFromDevice({
    required Set<String> takenNames,
  }) async {
    await init();
    final FilePickerResult? res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['ttf', 'otf'],
    );
    final String? src = res?.files.single.path;
    if (src == null) return null;

    final String ext = p.extension(src).toLowerCase();
    String base = p
        .basenameWithoutExtension(src)
        .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '_')
        .trim();
    if (base.isEmpty) base = 'Imported font';

    String name = base;
    int n = 2;
    while (takenNames.contains(name) || has(name)) {
      name = '$base ($n)';
      n++;
    }

    final Directory d = await _dir();
    final String dest = p.join(d.path, '${name.replaceAll(' ', '_')}$ext');
    await File(src).copy(dest);
    try {
      await _register(name, dest);
    } catch (_) {
      await File(dest).delete();
      throw const FormatException("That file isn't a valid font");
    }

    final ImportedFont f = ImportedFont(name: name, path: dest);
    _fonts.add(f);
    await _save();
    notifyListeners();
    return f;
  }

  /// Removes the file and the list entry. The engine can't unregister a
  /// family until the app restarts, so clips already using it keep rendering
  /// for this session.
  Future<void> remove(String name) async {
    final int i = _fonts.indexWhere((f) => f.name == name);
    if (i < 0) return;
    final ImportedFont f = _fonts.removeAt(i);
    try {
      final File file = File(f.path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
    await _save();
    notifyListeners();
  }
}

// ----------------------------------------------------------------------------
// Font filters
// ----------------------------------------------------------------------------

enum _FontFilter {
  all('All'),
  imported('Imported'),
  sans('Sans'),
  serif('Serif'),
  display('Display'),
  script('Script'),
  mono('Mono');

  const _FontFilter(this.label);
  final String label;
}

/// Category for the fonts that ship with the app. Names not listed here
/// still show up under "All".
const Map<String, _FontFilter> _categories = <String, _FontFilter>{
  'poppins': _FontFilter.sans,
  'roboto': _FontFilter.sans,
  'raleway': _FontFilter.sans,
  'montserrat': _FontFilter.sans,
  'inter': _FontFilter.sans,
  'open sans': _FontFilter.sans,
  'lato': _FontFilter.sans,
  'nunito': _FontFilter.sans,
  'playfair display': _FontFilter.serif,
  'playfair': _FontFilter.serif,
  'merriweather': _FontFilter.serif,
  'lora': _FontFilter.serif,
  'times new roman': _FontFilter.serif,
  'oswald': _FontFilter.display,
  'anton': _FontFilter.display,
  'bebas neue': _FontFilter.display,
  'bebas': _FontFilter.display,
  'impact': _FontFilter.display,
  'lobster': _FontFilter.script,
  'pacifico': _FontFilter.script,
  'caveat': _FontFilter.script,
  'dancing script': _FontFilter.script,
  'courier': _FontFilter.mono,
  'courier new': _FontFilter.mono,
  'roboto mono': _FontFilter.mono,
  'space mono': _FontFilter.mono,
  'fira code': _FontFilter.mono,
};

@immutable
class _FontEntry {
  const _FontEntry(this.name, this.category, this.imported);
  final String name;
  final _FontFilter? category;
  final bool imported;

  bool matches(_FontFilter f) => switch (f) {
        _FontFilter.all => true,
        _FontFilter.imported => imported,
        _ => category == f,
      };
}

// ----------------------------------------------------------------------------
// Sheet
// ----------------------------------------------------------------------------

enum _Tab {
  font('Font'),
  effects('Effects'),
  color('Color'),
  layout('Layout');

  const _Tab(this.label);
  final String label;
}

class TextStyleSheet extends StatefulWidget {
  const TextStyleSheet({super.key});

  @override
  State<TextStyleSheet> createState() => _TextStyleSheetState();
}

class _TextStyleSheetState extends State<TextStyleSheet> {
  _Tab _tab = _Tab.font;
  _FontFilter _filter = _FontFilter.all;
  bool _importing = false;

  final FontLibrary _library = FontLibrary.instance;

  final List<Color> _colors = const [
    Colors.white,
    Colors.black,
    Color(0xFFFF3B30),
    Color(0xFFFF9500),
    Color(0xFFFFCC00),
    Color(0xFF34C759),
    Color(0xFF00E5FF),
    Color(0xFF007AFF),
    Color(0xFF5856D6),
    Color(0xFFAF52DE),
    Color(0xFFFF2D55),
  ];

  final List<String> _textEffects = const [
    'none',
    'outline',
    'shadow',
    'glow',
    'neon',
    '3d',
  ];

  @override
  void initState() {
    super.initState();
    _library.addListener(_onLibrary);
    _library.init();
  }

  @override
  void dispose() {
    _library.removeListener(_onLibrary);
    super.dispose();
  }

  void _onLibrary() {
    if (mounted) setState(() {});
  }

  // ---- Fonts ----------------------------------------------------------------

  List<_FontEntry> _allFonts(EditorController editor) {
    final Set<String> imported = _library.fonts.map((f) => f.name).toSet();
    return <_FontEntry>[
      for (final String n in editor.availableFonts)
        if (!imported.contains(n)) _FontEntry(n, _categories[n.toLowerCase()], false),
      for (final ImportedFont f in _library.fonts) _FontEntry(f.name, null, true),
    ];
  }

  void _toast(String msg) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _import(EditorController editor) async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final ImportedFont? f = await _library.importFromDevice(
        takenNames: editor.availableFonts.toSet(),
      );
      if (f == null || !mounted) return;
      editor.updateSelectedClipFont(f.name);
      setState(() => _filter = _FontFilter.imported);
    } on FormatException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast("Couldn't import that font. Try another file");
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  // ---- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final clip = context.select<EditorController, TimelineClip?>((e) => e.selectedClip);
    final editor = context.read<EditorController>();
    if (clip == null || (clip.clipType != ClipType.text && clip.clipType != ClipType.caption)) {
      return Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: const Text(
          'Select a text clip to customize style',
          style: TextStyle(color: EditorTokens.muted, fontFamily: 'Poppins'),
        ),
      );
    }

    final ts = clip.textStyle;

    final Widget body = switch (_tab) {
      _Tab.font => _fontTab(editor, clip),
      _Tab.effects => _effectsTab(editor, ts),
      _Tab.color => _colorTab(editor, ts),
      _Tab.layout => _layoutTab(editor, ts),
    };

    return Column(
      children: [
        _tabBar(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24),
            child: body,
          ),
        ),
      ],
    );
  }

  // ---- Tabs -----------------------------------------------------------------

  Widget _tabBar() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final t in _Tab.values)
            Semantics(
              button: true,
              selected: t == _tab,
              label: t.label,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _tab = t);
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        t.label,
                        style: TextStyle(
                          color: t == _tab ? EditorTokens.text : EditorTokens.muted,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Poppins',
                        ),
                      ),
                      const SizedBox(height: 7),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        height: 2.5,
                        width: 22,
                        decoration: BoxDecoration(
                          color: t == _tab ? _accent : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Premiere-style hairline section bar.
  Widget _bar(String title) => Container(
        height: 32,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.centerLeft,
        decoration: const BoxDecoration(
          color: _card,
          border: Border(top: BorderSide(color: _line), bottom: BorderSide(color: _line)),
        ),
        child: Text(
          title,
          style: const TextStyle(
            color: EditorTokens.text,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            fontFamily: 'Poppins',
          ),
        ),
      );

  // ---- Font tab -------------------------------------------------------------

  Widget _fontTab(EditorController editor, dynamic clip) {
    final List<_FontEntry> all = _allFonts(editor);
    final List<_FontEntry> shown = all.where((f) => f.matches(_filter)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _filterChips(),
        if (shown.isEmpty)
          _emptyState(editor)
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: LayoutBuilder(builder: (context, box) {
              const int cols = 4;
              const double gap = 8;
              final double w = (box.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  _importTile(editor, w),
                  for (final _FontEntry font in shown)
                    _fontTile(
                      font,
                      w,
                      clip.fontFamily == font.name,
                      () => editor.updateSelectedClipFont(font.name),
                    ),
                ],
              );
            }),
          ),
      ],
    );
  }

  Widget _filterChips() {
    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _FontFilter.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final _FontFilter f = _FontFilter.values[i];
          final bool on = f == _filter;
          return Semantics(
            button: true,
            selected: on,
            label: '${f.label} fonts',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _filter = f);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? _accent.withAlpha(30) : _card,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: on ? _accent : Colors.transparent),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (f == _FontFilter.imported) ...[
                      Icon(Icons.file_upload_outlined,
                          size: 14, color: on ? _accent : EditorTokens.muted),
                      const SizedBox(width: 5),
                    ],
                    Text(
                      f.label,
                      style: TextStyle(
                        color: on ? _accent : EditorTokens.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ).withTopPadding(12);
  }

  Widget _emptyState(EditorController editor) {
    final bool imp = _filter == _FontFilter.imported;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 0),
      child: Column(
        children: [
          Text(
            imp
                ? 'Import a .ttf or .otf from your device to use it in your text.'
                : 'No fonts in this category',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: EditorTokens.muted, fontSize: 12, fontFamily: 'Poppins'),
          ),
          if (imp) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _importing ? null : () => _import(editor),
              icon: const Icon(Icons.file_upload_outlined, size: 18),
              label: const Text('Import font'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _accent,
                side: const BorderSide(color: _accent),
                backgroundColor: _card,
                minimumSize: const Size(0, 40),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Dashed "Import" tile, always the first item in the grid.
  Widget _importTile(EditorController editor, double w) {
    return Semantics(
      button: true,
      label: 'Import font from device',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          _import(editor);
        },
        child: CustomPaint(
          painter: _DashedRRectPainter(color: _track, radius: 8),
          child: SizedBox(
            width: w,
            height: 68,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_importing)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
                  )
                else
                  const Icon(Icons.note_add_outlined, size: 22, color: _accent),
                const SizedBox(height: 6),
                const Text('Import',
                    style: TextStyle(
                        color: _accent,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Poppins')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fontTile(_FontEntry font, double w, bool on, VoidCallback f) {
    return Semantics(
      button: true,
      selected: on,
      label: font.name,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          f();
        },
        child: Container(
          width: w,
          height: 68,
          decoration: BoxDecoration(
            color: on ? _accent.withAlpha(28) : _card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: on ? _accent : Colors.transparent, width: 1.4),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Aa',
                        style: TextStyle(
                            color: on ? _accent : EditorTokens.text,
                            fontSize: 22,
                            fontFamily: font.name)),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(font.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: on ? _accent : EditorTokens.muted,
                              fontSize: 9.5,
                              fontFamily: 'Poppins')),
                    ),
                  ],
                ),
              ),
              if (font.imported)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Semantics(
                    button: true,
                    label: 'Remove ${font.name}',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _library.remove(font.name);
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(5),
                        child: Icon(Icons.close_rounded, size: 13, color: EditorTokens.muted),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Effects tab ----------------------------------------------------------

  Widget _effectsTab(EditorController editor, TextStyleProperties ts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _bar('Presets'),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: SizedBox(
            height: 86,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _textEffects.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) => _effectTile(editor, ts, _textEffects[i]),
            ),
          ),
        ),
        _bar('Stroke'),
        _ParamSlider(
          label: 'Width',
          value: ts.strokeWidth,
          min: 0,
          max: 10,
          resetTo: 0,
          onChanged: (val) => editor.updateSelectedClipTextStyle(
            ts.copyWith(
              strokeWidth: val,
              strokeColor: val > 0 && ts.strokeColor == Colors.transparent
                  ? Colors.black
                  : ts.strokeColor,
            ),
          ),
        ),
        _swatches(
          ts.strokeColor,
          (c) => editor.updateSelectedClipTextStyle(
            ts.copyWith(
              strokeColor: c,
              strokeWidth: ts.strokeWidth == 0 ? 2.0 : ts.strokeWidth,
            ),
          ),
        ),
        _bar('Shadow'),
        _ParamSlider(
          label: 'Blur',
          value: ts.shadowBlurRadius,
          min: 0,
          max: 20,
          resetTo: 0,
          onChanged: (val) => editor.updateSelectedClipTextStyle(
            ts.copyWith(
              shadowBlurRadius: val,
              shadowColor: val > 0 && ts.shadowColor == Colors.transparent
                  ? Colors.black87
                  : ts.shadowColor,
            ),
          ),
        ),
      ],
    );
  }

  /// Preview tile: "Ab" drawn with an approximation of the effect.
  Widget _effectTile(EditorController editor, TextStyleProperties ts, String effect) {
    final bool on = ts.textEffect == effect;
    const Color cyan = Color(0xFF00E5FF);
    final List<Shadow> shadows = switch (effect) {
      'outline' => const [
          Shadow(color: Colors.black, offset: Offset(-1.2, -1.2)),
          Shadow(color: Colors.black, offset: Offset(1.2, -1.2)),
          Shadow(color: Colors.black, offset: Offset(-1.2, 1.2)),
          Shadow(color: Colors.black, offset: Offset(1.2, 1.2)),
        ],
      'shadow' => const [Shadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 3)],
      'glow' => const [Shadow(color: cyan, blurRadius: 10)],
      'neon' => const [Shadow(color: cyan, blurRadius: 4), Shadow(color: cyan, blurRadius: 12)],
      '3d' => const [
          Shadow(color: Color(0xFF777777), offset: Offset(1, 1)),
          Shadow(color: Color(0xFF555555), offset: Offset(2, 2)),
          Shadow(color: Color(0xFF333333), offset: Offset(3, 3)),
        ],
      _ => const <Shadow>[],
    };
    return Semantics(
      button: true,
      selected: on,
      label: '$effect effect',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          TextStyleProperties updated = ts.copyWith(textEffect: effect);
          if (effect == 'outline') {
            updated = updated.copyWith(strokeColor: Colors.black, strokeWidth: 3.0);
          } else if (effect == 'shadow') {
            updated = updated.copyWith(
              shadowColor: Colors.black,
              shadowBlurRadius: 6.0,
              shadowOffsetX: 2.0,
              shadowOffsetY: 2.0,
            );
          } else if (effect == 'glow') {
            updated = updated.copyWith(
              shadowColor: const Color(0xFF00E5FF),
              shadowBlurRadius: 12.0,
            );
          } else if (effect == 'neon') {
            updated = updated.copyWith(
              textColor: const Color(0xFF00E5FF),
              shadowColor: const Color(0xFF00E5FF),
              shadowBlurRadius: 16.0,
            );
          }
          editor.updateSelectedClipTextStyle(updated);
        },
        child: Container(
          width: 66,
          decoration: BoxDecoration(
            color: _field,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: on ? _accent : _line, width: on ? 1.5 : 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Ab',
                style: TextStyle(
                  color: effect == 'neon' ? cyan : Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Poppins',
                  shadows: shadows,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                effect == 'none' ? 'None' : effect[0].toUpperCase() + effect.substring(1),
                style: TextStyle(
                  color: on ? _accent : EditorTokens.muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Color tab ------------------------------------------------------------

  Widget _colorTab(EditorController editor, TextStyleProperties ts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _bar('Text color'),
        _swatches(
          ts.textColor,
          (c) => editor.updateSelectedClipTextStyle(ts.copyWith(textColor: c)),
        ),
      ],
    );
  }

  Widget _swatches(Color selected, ValueChanged<Color> onPick) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final c in _colors)
            Semantics(
              button: true,
              selected: selected.toARGB32() == c.toARGB32(),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onPick(c);
                },
                child: Container(
                  width: 36,
                  height: 36,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected.toARGB32() == c.toARGB32() ? _accent : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(color: EditorTokens.border),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---- Layout tab -----------------------------------------------------------

  Widget _layoutTab(EditorController editor, TextStyleProperties ts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _bar('Alignment'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _alignSegments(editor, ts),
        ),
        _bar('Size & spacing'),
        _ParamSlider(
          label: 'Text size',
          value: ts.fontSize,
          min: 10,
          max: 100,
          step: 1,
          decimals: 0,
          onChanged: (val) => editor.updateSelectedClipTextStyle(ts.copyWith(fontSize: val)),
        ),
        _ParamSlider(
          label: 'Line height',
          value: ts.lineHeight,
          min: 0.8,
          max: 3.0,
          onChanged: (val) => editor.updateSelectedClipTextStyle(ts.copyWith(lineHeight: val)),
        ),
        _bar('Background'),
        _ParamSlider(
          label: 'Padding',
          value: ts.backgroundPadding,
          min: 0,
          max: 24,
          resetTo: 0,
          onChanged: (val) =>
              editor.updateSelectedClipTextStyle(ts.copyWith(backgroundPadding: val)),
        ),
      ],
    );
  }

  /// Joined icon segmented control, like Premiere's paragraph panel.
  Widget _alignSegments(EditorController editor, TextStyleProperties ts) {
    final items = <(TextAlign, dynamic, String)>[
      (TextAlign.left, HugeIcons.strokeRoundedTextAlignLeft, 'Align left'),
      (TextAlign.center, HugeIcons.strokeRoundedTextAlignCenter, 'Align center'),
      (TextAlign.right, HugeIcons.strokeRoundedTextAlignRight, 'Align right'),
    ];
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: _field,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line),
      ),
      child: Row(
        children: [
          for (int i = 0; i < items.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: ts.textAlign == items[i].$1,
                label: items[i].$3,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    editor.updateSelectedClipTextStyle(ts.copyWith(textAlign: items[i].$1));
                  },
                  child: Container(
                    margin: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: ts.textAlign == items[i].$1 ? _accent.withAlpha(30) : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: ts.textAlign == items[i].$1 ? _accent : Colors.transparent,
                      ),
                    ),
                    child: Center(
                      child: HugeIcon(
                        icon: items[i].$2,
                        color: ts.textAlign == items[i].$1 ? _accent : EditorTokens.text,
                        size: 18.0,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

extension on Widget {
  Widget withTopPadding(double v) => Padding(padding: EdgeInsets.only(top: v), child: this);
}

/// Dashed rounded-rect outline for the Import tile.
class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final Path path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(radius),
      ));
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    const double dash = 5, gap = 4;
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter old) =>
      old.color != color || old.radius != radius;
}

// ---- Premiere-style parameter row ---------------------------------------------

class _ParamSlider extends StatelessWidget {
  const _ParamSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 0.1,
    this.decimals = 1,
    this.resetTo,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final int decimals;
  final double? resetTo;
  final ValueChanged<double> onChanged;

  double get _v => value.clamp(min, max).toDouble();

  double _snap(double v) =>
      ((v.clamp(min, max).toDouble()) / step).round() * step;

  @override
  Widget build(BuildContext context) {
    final bool changed = resetTo != null && (_v - resetTo!).abs() > 1e-6;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        children: [
          Row(
            children: [
              Text(label,
                  style: TextStyle(
                      color: changed ? EditorTokens.text : EditorTokens.muted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Poppins')),
              if (changed)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onChanged(resetTo!);
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.undo_rounded, size: 14, color: EditorTokens.muted),
                  ),
                ),
              const Spacer(),
              // Drag the box to scrub; double-tap resets (when a default exists).
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: resetTo == null ? null : () => onChanged(resetTo!),
                onHorizontalDragUpdate: (d) =>
                    onChanged(_snap(_v + d.delta.dx * (max - min) / 200)),
                child: Container(
                  width: 64,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _field,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: changed ? _accent.withAlpha(120) : _line),
                  ),
                  child: Text(
                    _v.toStringAsFixed(decimals),
                    style: TextStyle(
                      color: changed ? _accent : EditorTokens.text,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Poppins',
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ],
          ),
          LayoutBuilder(builder: (context, box) {
            final double w = box.maxWidth;
            double fromDx(double dx) {
              final double t = ((dx - _pad) / (w - _pad * 2)).clamp(0.0, 1.0).toDouble();
              return _snap(min + (max - min) * t);
            }

            return Semantics(
              slider: true,
              label: label,
              value: _v.toStringAsFixed(decimals),
              increasedValue: _snap(_v + step).toStringAsFixed(decimals),
              decreasedValue: _snap(_v - step).toStringAsFixed(decimals),
              onIncrease: () => onChanged(_snap(_v + step)),
              onDecrease: () => onChanged(_snap(_v - step)),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => onChanged(fromDx(d.localPosition.dx)),
                onHorizontalDragUpdate: (d) => onChanged(fromDx(d.localPosition.dx)),
                child: SizedBox(
                  height: 40,
                  width: w,
                  child: CustomPaint(painter: _SliderPainter((_v - min) / (max - min))),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  static const double _pad = 10;
}

class _SliderPainter extends CustomPainter {
  _SliderPainter(this.t);
  final double t; // 0..1

  @override
  void paint(Canvas canvas, Size size) {
    const double pad = _ParamSlider._pad;
    final double w = size.width - pad * 2;
    const double y = 13;
    final double x = pad + t * w;

    final Rect bar = Rect.fromLTWH(pad, y - 2, w, 4);
    canvas.drawRRect(
        RRect.fromRectAndRadius(bar, const Radius.circular(2)), Paint()..color = _track);
    if (t > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTRB(pad, y - 2, x, y + 2), const Radius.circular(2)),
        Paint()..color = _accent,
      );
    }

    // Premiere triangle thumb, pointing up at the track.
    canvas.drawPath(
      Path()
        ..moveTo(x, y + 5)
        ..lineTo(x - 7.5, y + 18)
        ..lineTo(x + 7.5, y + 18)
        ..close(),
      Paint()..color = t > 0 ? _accent : Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _SliderPainter old) => old.t != t;
}