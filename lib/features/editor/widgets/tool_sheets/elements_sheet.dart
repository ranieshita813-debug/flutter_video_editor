// pubspec.yaml additions:
//   flutter_svg: ^2.0.10
//   xml: ^6.5.0
//   path_drawing: ^1.0.1
//   file_picker: ^8.0.0
//
// EditorController needs one new method (see bottom of file).

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';
import 'package:flutter_video_editor/features/editor/widgets/tool_search_header.dart';
import 'package:flutter_video_editor/core/models/svg_model.dart';
import 'package:flutter_video_editor/features/editor/widgets/svg_editor.dart';

const _accent = Color(0xFF9999FF); // Premiere purple
const _panel = Color(0xFF232323);
const _bg = Color(0xFF181818);
const _lbl = TextStyle(color: Color(0xFFB4B4B4), fontSize: 11, fontFamily: 'Poppins');

// ───────────────────────── ELEMENTS LIBRARY SHEET ─────────────────────────

class _Asset {
  _Asset(this.name, this.svg);
  final String name;
  final String svg;
}

String svgForShape(ElementShape s) {
  const o = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">';
  const f = 'fill="#9999FF"';
  switch (s.name.toLowerCase()) {
    case 'circle':
      return '$o<circle cx="50" cy="50" r="42" $f/></svg>';
    case 'ellipse':
      return '$o<ellipse cx="50" cy="50" rx="46" ry="30" $f/></svg>';
    case 'triangle':
      return '$o<polygon points="50,8 94,90 6,90" $f/></svg>';
    case 'star':
      return '$o<polygon points="50,5 61,38 95,38 67,58 78,92 50,71 22,92 33,58 5,38 39,38" $f/></svg>';
    case 'heart':
      return '$o<path d="M50 88 C10 60 5 30 28 18 C40 12 50 20 50 30 C50 20 60 12 72 18 C95 30 90 60 50 88Z" $f/></svg>';
    case 'arrow':
      return '$o<polygon points="10,40 60,40 60,20 95,50 60,80 60,60 10,60" $f/></svg>';
    case 'hexagon':
    case 'polygon':
      return '$o<polygon points="50,5 90,27 90,73 50,95 10,73 10,27" $f/></svg>';
    case 'line':
      return '$o<line x1="8" y1="50" x2="92" y2="50" stroke="#9999FF" stroke-width="6"/></svg>';
    default:
      return '$o<rect x="10" y="10" width="80" height="80" rx="10" $f/></svg>';
  }
}

class ElementsSheet extends StatefulWidget {
  const ElementsSheet({super.key});
  @override
  State<ElementsSheet> createState() => _ElementsSheetState();
}

class _ElementsSheetState extends State<ElementsSheet> {
  String _searchQuery = '';
  String _selectedTag = 'All';
  int _tab = 0; // 0 = Shapes, 1 = My SVG
  final List<_Asset> _mine = [];

  Future<void> _importFile() async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['svg'], withData: true);
    final f = res?.files.single;
    if (f?.bytes == null) return;
    _addImported(f!.name.replaceAll(RegExp(r'\.svg$', caseSensitive: false), ''), utf8.decode(f.bytes!));
  }

  Future<void> _pasteCode() async {
    final c = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _panel,
        title: const Text('Paste SVG code', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: TextField(
          controller: c,
          maxLines: 8,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
          decoration: const InputDecoration(hintText: '<svg ...>', hintStyle: TextStyle(color: Colors.white38)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Import')),
        ],
      ),
    );
    if (code != null && code.trim().isNotEmpty) _addImported('Pasted SVG', code);
  }

  void _addImported(String name, String svg) {
    try {
      SvgDoc.parse(svg); // validate
      setState(() {
        _mine.insert(0, _Asset(name, svg));
        _tab = 1;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invalid SVG: $e')));
    }
  }

  Future<void> _draw() async {
    final editor = context.read<EditorController>();
    final out = await Navigator.of(context).push<String>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const SvgEditorPage(
            source: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200"></svg>',
            title: 'New graphic')));
    if (out == null) return;
    setState(() => _mine.insert(0, _Asset('Drawing ${_mine.length + 1}', out)));
    editor.addSvgElementClip(out, 'Drawing');
  }

  Future<void> _edit(_Asset a) async {
    final editor = context.read<EditorController>();
    final out = await Navigator.of(context).push<String>(MaterialPageRoute(
        fullscreenDialog: true, builder: (_) => SvgEditorPage(source: a.svg, title: a.name)));
    if (out == null) return;
    setState(() => _mine.insert(0, _Asset('${a.name} (edited)', out)));
    editor.addSvgElementClip(out, a.name);
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    final q = _searchQuery.toLowerCase();
    final assets = _tab == 0
        ? ElementShape.values.map((s) => _Asset(s.name, svgForShape(s))).toList()
        : _mine;
    final filtered = assets.where((a) => a.name.toLowerCase().contains(q)).toList();

    return Container(
      color: _bg,
      child: Column(children: [
        ToolSearchHeader(
          onSearchChanged: (q) => setState(() => _searchQuery = q),
          onTagSelected: (t) => setState(() => _selectedTag = t),
          selectedTag: _selectedTag,
          placeholder: 'Search graphics...',
        ),
        // Premiere-style panel tabs
        Row(children: [
          _tabBtn('Shapes', 0),
          _tabBtn('My SVG (${_mine.length})', 1),
          const Spacer(),
          IconButton(
              tooltip: 'Draw new (pen tool)',
              onPressed: _draw,
              icon: const Icon(Icons.draw_outlined, size: 18, color: Colors.white70)),
          IconButton(
              tooltip: 'Paste SVG code',
              onPressed: _pasteCode,
              icon: const Icon(Icons.code, size: 18, color: Colors.white70)),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: _accent, foregroundColor: Colors.black, visualDensity: VisualDensity.compact),
              onPressed: _importFile,
              icon: const Icon(Icons.file_upload_outlined, size: 16),
              label: const Text('Import SVG', style: TextStyle(fontSize: 12)),
            ),
          ),
        ]),
        const Divider(height: 1, color: Colors.white12),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(_tab == 1 ? 'Import or paste an SVG to start' : 'No results',
                      style: _lbl.copyWith(fontSize: 13)))
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.05),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final a = filtered[i];
                    return GestureDetector(
                      onTap: () => editor.addSvgElementClip(a.svg, a.name),
                      child: Container(
                        decoration: BoxDecoration(
                          color: EditorTokens.elevated,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: EditorTokens.border),
                        ),
                        child: Stack(children: [
                          Positioned.fill(
                              child: Padding(
                                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 26),
                                  child: SvgPicture.string(a.svg, fit: BoxFit.contain))),
                          Positioned(
                              left: 8,
                              right: 8,
                              bottom: 6,
                              child: Text(a.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: EditorTokens.text, fontSize: 10.5, fontFamily: 'Poppins'))),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: InkWell(
                              onTap: () => _edit(a),
                              child: const Padding(
                                  padding: EdgeInsets.all(5),
                                  child: Icon(Icons.edit_outlined, size: 15, color: _accent)),
                            ),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  Widget _tabBtn(String t, int i) => InkWell(
        onTap: () => setState(() => _tab = i),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: _tab == i ? _accent : Colors.transparent, width: 2))),
          child: Text(t,
              style: TextStyle(
                  color: _tab == i ? Colors.white : Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins')),
        ),
      );
}