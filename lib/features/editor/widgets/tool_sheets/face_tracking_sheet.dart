import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/face_tracking_model.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/core/services/face_tracking_service.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/utils/editor_helpers.dart';

/// Effect option shown as a square tile (CapCut-style tool row).
class _FxDef {
  const _FxDef(this.label, this.icon, this.type);
  final String label;
  final PhosphorIconData icon;
  final PersonEffectType type;
}

class FaceTrackingSheet extends StatefulWidget {
  const FaceTrackingSheet({super.key});

  @override
  State<FaceTrackingSheet> createState() => _FaceTrackingSheetState();
}

class _FaceTrackingSheetState extends State<FaceTrackingSheet>
    with SingleTickerProviderStateMixin {
  // ---- analysis state ----
  bool _isAnalyzing = false;
  double _progress = 0.0;
  String _statusText = '';

  // ---- selection state ----
  String? _selectedPersonId;
  bool _mergeMode = false;
  final Set<String> _selectedForMerge = {};

  // Bumped when a preset text is tapped so the text field rebuilds with new text.
  int _textRevision = 0;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  static const List<String> _stickerOptions = [
    '😎', '🥸', '🎭', '🤡', '🤖', '🐱', '🔥', '✨',
  ];

  static const List<String> _textPresets = ['Anonymous', 'Guest', 'Me', 'Hidden'];

  static const List<Color> _palette = [
    Color(0xFF25F4EE),
    Color(0xFFFE2C55),
    Color(0xFFFFC300),
    Color(0xFF7C5CFF),
    Color(0xFF34D399),
    Color(0xFFFF8A3D),
  ];

  static final List<_FxDef> _fxDefs = [
    const _FxDef('None', PhosphorIconsRegular.prohibit, PersonEffectType.none),
    const _FxDef('Blur', PhosphorIconsRegular.dropHalf, PersonEffectType.blur),
    const _FxDef('Mosaic', PhosphorIconsRegular.gridFour, PersonEffectType.mosaic),
    const _FxDef('Text', PhosphorIconsRegular.textAa, PersonEffectType.text),
    const _FxDef('Sticker', PhosphorIconsRegular.smiley, PersonEffectType.sticker),
  ];

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Actions
  // ------------------------------------------------------------------

  Future<bool> _promptDownloadPermission() async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surfaceToken,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Download tracking models',
          style: TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'Face tracking needs a one-time download of AI model files (~2.5 MB). Allow download?',
          style: TextStyle(color: mutedToken, fontSize: 13, height: 1.4),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: mutedToken)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: accentToken,
              foregroundColor: Colors.black,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Download & start',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _startTracking(EditorController editor) async {
    if (!FaceTrackingService.isModelDownloaded) {
      final bool granted = await _promptDownloadPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Tracking cancelled. Model files are required for face tracking.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      _pulse.repeat(reverse: true);
      setState(() {
        _isAnalyzing = true;
        _progress = 0.1;
        _statusText = 'Downloading tracking model files...';
        _mergeMode = false;
        _selectedForMerge.clear();
      });

      await Future<void>.delayed(const Duration(milliseconds: 300));
      FaceTrackingService.setModelDownloaded(true);
    } else {
      _pulse.repeat(reverse: true);
      setState(() {
        _isAnalyzing = true;
        _progress = 0.0;
        _statusText = 'Initializing face detection...';
        _mergeMode = false;
        _selectedForMerge.clear();
      });
    }

    try {
      final FaceTrackingData? result =
          await editor.runFaceTrackingOnSelectedClip(
        stepDelays: false,
        onProgress: (p, status) {
          if (mounted) {
            setState(() {
              _progress = p;
              _statusText = status;
            });
          }
        },
      );

      if (mounted && result != null && result.persons.isNotEmpty) {
        setState(() => _selectedPersonId = result.persons.first.id);
      }
    } finally {
      _pulse.stop();
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  PersonEffect _defaultEffect(PersonEffectType type, Person person) {
    switch (type) {
      case PersonEffectType.none:
        return const PersonEffect(type: PersonEffectType.none);
      case PersonEffectType.blur:
        return const PersonEffect(type: PersonEffectType.blur, intensity: 10.0);
      case PersonEffectType.mosaic:
        return const PersonEffect(type: PersonEffectType.mosaic, intensity: 16.0);
      case PersonEffectType.text:
        return PersonEffect(type: PersonEffectType.text, text: person.name);
      case PersonEffectType.sticker:
        return const PersonEffect(
            type: PersonEffectType.sticker, stickerAsset: '😎');
    }
  }

  void _applyToAll(EditorController editor, List<Person> persons, PersonEffect fx) {
    for (final p in persons) {
      final PersonEffect next =
          fx.type == PersonEffectType.text ? fx.copyWith(text: p.name) : fx;
      editor.updatePersonEffect(p.id, next);
    }
  }

  void _exitMerge() {
    setState(() {
      _mergeMode = false;
      _selectedForMerge.clear();
    });
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final TimelineClip? clip = editor.selectedClip;

    if (clip == null) return _buildNoClip();
    if (_isAnalyzing) return _buildScanning();

    final FaceTrackingData tracking = clip.faceTrackingData;
    if (!tracking.isProcessed || tracking.persons.isEmpty) {
      return _buildIntro(editor);
    }

    return _buildEditor(editor, tracking);
  }

  // ------------------------------------------------------------------
  // States: no clip / intro / scanning
  // ------------------------------------------------------------------

  Widget _buildNoClip() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: cardToken,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: PhosphorIcon(PhosphorIconsRegular.userFocus,
                    size: 30, color: mutedToken),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No clip selected',
              style: TextStyle(
                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tap a video or image clip on the timeline to use face tracking.',
              textAlign: TextAlign.center,
              style: TextStyle(color: mutedToken, fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntro(EditorController editor) {
    Widget feature(PhosphorIconData icon, String title, String sub) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: cardToken,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                  child: PhosphorIcon(icon, size: 19, color: accentToken)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 1),
                  Text(sub,
                      style: const TextStyle(color: mutedToken, fontSize: 11.5)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _grabber(),
          const SizedBox(height: 18),
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accentToken.withValues(alpha: 0.35),
                  accentToken.withValues(alpha: 0.05),
                ],
              ),
              border: Border.all(color: accentToken.withValues(alpha: 0.5)),
            ),
            child: const Center(
              child: PhosphorIcon(PhosphorIconsRegular.userFocus,
                  size: 40, color: accentToken),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Face tracking',
            style: TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Detect every face and follow it through the clip.',
            textAlign: TextAlign.center,
            style: TextStyle(color: mutedToken, fontSize: 12.5),
          ),
          const SizedBox(height: 18),
          feature(PhosphorIconsRegular.scan, 'Auto detect',
              'Finds faces frame by frame'),
          feature(PhosphorIconsRegular.users, 'Smart grouping',
              'Same person stays in one track'),
          feature(PhosphorIconsRegular.dropHalf, 'Per-face effects',
              'Blur, mosaic, text or stickers'),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: accentToken,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999)),
              ),
              onPressed: () {
                tapFeedback();
                _startTracking(editor);
              },
              icon: const PhosphorIcon(PhosphorIconsBold.scan, size: 18),
              label: const Text('Scan faces',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanning() {
    final stages = <String>['Extracting', 'Detecting', 'Tracking'];
    int active = 0;
    if (_progress >= 0.75) {
      active = 2;
    } else if (_progress >= 0.33) {
      active = 1;
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 128,
              height: 128,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ScaleTransition(
                    scale: Tween(begin: 0.92, end: 1.0).animate(
                      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                    ),
                    child: Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accentToken.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: CircularProgressIndicator(
                      value: _progress.clamp(0.0, 1.0),
                      strokeWidth: 5,
                      strokeCap: StrokeCap.round,
                      backgroundColor: cardToken,
                      color: accentToken,
                    ),
                  ),
                  Text(
                    '${(_progress * 100).round()}%',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _statusText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: List.generate(stages.length, (i) {
                final bool done = i < active;
                final bool now = i == active;
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: now ? accentToken.withValues(alpha: 0.18) : cardToken,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: now ? accentToken : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (done)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(Icons.check_rounded,
                              size: 12, color: accentToken),
                        ),
                      Text(
                        stages[i],
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: (done || now) ? Colors.white : mutedToken,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Main editor
  // ------------------------------------------------------------------

  Widget _grabber() {
    return Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: dividerToken,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildEditor(EditorController editor, FaceTrackingData tracking) {
    final List<Person> persons = tracking.persons;

    if (_selectedPersonId == null ||
        !persons.any((p) => p.id == _selectedPersonId)) {
      _selectedPersonId = persons.first.id;
    }
    _selectedForMerge.removeWhere((id) => !persons.any((p) => p.id == id));

    final int activeIndex = persons.indexWhere((p) => p.id == _selectedPersonId);
    final Person activePerson = persons[activeIndex];
    final Color activeColor = _palette[activeIndex % _palette.length];
    final PersonEffect currentFx = activePerson.effects.isNotEmpty
        ? activePerson.effects.first
        : const PersonEffect();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _grabber(),
        ),
        _buildHeader(editor, persons.length),
        _buildFaceStrip(persons),
        const Divider(height: 1, color: dividerToken),
        Expanded(
          child: IgnorePointer(
            ignoring: _mergeMode,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 160),
              opacity: _mergeMode ? 0.35 : 1,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                children: [
                  _buildPersonInfo(editor, activePerson, activeColor),
                  const SizedBox(height: 14),
                  _buildEffectRow(editor, activePerson, currentFx),
                  const SizedBox(height: 14),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    alignment: Alignment.topCenter,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: KeyedSubtree(
                        key: ValueKey('${activePerson.id}_${currentFx.type}'),
                        child: _buildParams(editor, activePerson, currentFx),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _mergeMode
            ? _buildMergeBar(editor)
            : _buildBottomBar(editor, persons, currentFx),
      ],
    );
  }

  Widget _buildHeader(EditorController editor, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _mergeMode
                  ? 'Select faces to merge'
                  : '$count ${count == 1 ? 'person' : 'people'} found',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
          if (!_mergeMode) ...[
            if (count > 1)
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () {
                  tapFeedback();
                  setState(() => _mergeMode = true);
                },
                icon: const PhosphorIcon(PhosphorIconsRegular.gitMerge, size: 16),
                label: const Text('Merge',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            IconButton(
              tooltip: 'Re-scan',
              visualDensity: VisualDensity.compact,
              icon: const PhosphorIcon(PhosphorIconsRegular.arrowsClockwise,
                  color: mutedToken, size: 20),
              onPressed: () {
                tapFeedback();
                _startTracking(editor);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFaceStrip(List<Person> persons) {
    return SizedBox(
      height: 98,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: persons.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, idx) {
          final Person p = persons[idx];
          final Color color = _palette[idx % _palette.length];
          final bool isSelected = p.id == _selectedPersonId;
          final bool isMerge = _selectedForMerge.contains(p.id);
          final bool hasFx =
              p.effects.isNotEmpty && p.effects.first.type != PersonEffectType.none;
          final bool ringOn = isMerge || (isSelected && !_mergeMode);

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              tapFeedback();
              setState(() {
                if (_mergeMode) {
                  isMerge
                      ? _selectedForMerge.remove(p.id)
                      : _selectedForMerge.add(p.id);
                } else {
                  _selectedPersonId = p.id;
                }
              });
            },
            onLongPress: () {
              tapFeedback();
              setState(() {
                _mergeMode = true;
                _selectedForMerge.add(p.id);
              });
            },
            child: SizedBox(
              width: 58,
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 58,
                        height: 58,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: ringOn
                                ? (isMerge ? Colors.amber : color)
                                : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                color.withValues(alpha: 0.5),
                                color.withValues(alpha: 0.14),
                              ],
                            ),
                          ),
                          child: const Center(
                            child: PhosphorIcon(PhosphorIconsRegular.user,
                                size: 24, color: Colors.white),
                          ),
                        ),
                      ),
                      if (isMerge)
                        Positioned(
                          right: -1,
                          top: -1,
                          child: _badge(Colors.amber, Icons.check_rounded),
                        )
                      else if (hasFx)
                        Positioned(
                          right: -1,
                          top: -1,
                          child: _badge(color, Icons.auto_awesome),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ringOn ? Colors.white : mutedToken,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
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

  Widget _badge(Color color, IconData icon) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: surfaceToken, width: 2),
      ),
      child: Icon(icon, size: 10, color: Colors.black),
    );
  }

  Widget _buildPersonInfo(
      EditorController editor, Person person, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            person.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          '${person.tracks.length} ${person.tracks.length == 1 ? 'track' : 'tracks'}',
          style: const TextStyle(color: mutedToken, fontSize: 11.5),
        ),
        if (person.tracks.length > 1) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              tapFeedback();
              editor.splitPersonTrack(person.id, person.tracks.last.id);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: cardToken,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PhosphorIcon(PhosphorIconsRegular.arrowsSplit,
                      size: 13, color: Colors.white),
                  SizedBox(width: 4),
                  Text('Split',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// CapCut-style tool row: square tiles, label underneath.
  Widget _buildEffectRow(
      EditorController editor, Person person, PersonEffect currentFx) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: _fxDefs.map((fx) {
          final bool selected = currentFx.type == fx.type;
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                tapFeedback();
                if (selected) return;
                editor.updatePersonEffect(
                    person.id, _defaultEffect(fx.type, person));
                setState(() => _textRevision++);
              },
              child: SizedBox(
                width: 60,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: selected
                            ? accentToken.withValues(alpha: 0.16)
                            : cardToken,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected ? accentToken : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: PhosphorIcon(
                          fx.icon,
                          size: 22,
                          color: selected ? accentToken : Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      fx.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? accentToken : mutedToken,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Parameter panels
  // ------------------------------------------------------------------

  Widget _panel({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: cardToken.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }

  Widget _chip(String text, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        tapFeedback();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? accentToken.withValues(alpha: 0.18) : surfaceToken,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? accentToken : Colors.transparent),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: active ? accentToken : Colors.white70,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildParams(
      EditorController editor, Person person, PersonEffect fx) {
    switch (fx.type) {
      case PersonEffectType.none:
        return _panel(
          child: const Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: mutedToken),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pick an effect above to apply it to this face.',
                  style: TextStyle(color: mutedToken, fontSize: 12),
                ),
              ),
            ],
          ),
        );

      case PersonEffectType.blur:
      case PersonEffectType.mosaic:
        final bool isBlur = fx.type == PersonEffectType.blur;
        final double base = isBlur ? 10.0 : 16.0;
        final double value = fx.intensity.clamp(2.0, 50.0);
        return _panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    isBlur ? 'Blur radius' : 'Tile size',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  Container(
                    constraints: const BoxConstraints(minWidth: 36),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: surfaceToken,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      value.round().toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: accentToken,
                          fontSize: 12,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Reset',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(6),
                    icon: const Icon(Icons.restart_alt_rounded,
                        size: 18, color: mutedToken),
                    onPressed: () {
                      tapFeedback();
                      editor.updatePersonEffect(
                          person.id, fx.copyWith(intensity: base));
                    },
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  activeTrackColor: accentToken,
                  inactiveTrackColor: surfaceToken,
                  thumbColor: Colors.white,
                  overlayColor: accentToken.withValues(alpha: 0.15),
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 9),
                ),
                child: Slider(
                  value: value,
                  min: 2.0,
                  max: 50.0,
                  onChanged: (val) => editor.updatePersonEffect(
                      person.id, fx.copyWith(intensity: val)),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Subtle',
                        style: TextStyle(color: mutedToken, fontSize: 10.5)),
                    Text('Strong',
                        style: TextStyle(color: mutedToken, fontSize: 10.5)),
                  ],
                ),
              ),
            ],
          ),
        );

      case PersonEffectType.text:
        return _panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Label',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _LabelField(
                key: ValueKey('${person.id}_$_textRevision'),
                initialText: fx.text,
                onChanged: (val) => editor.updatePersonEffect(
                    person.id, fx.copyWith(text: val)),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [person.name, ..._textPresets].map((t) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _chip(t, fx.text == t, () {
                        editor.updatePersonEffect(
                            person.id, fx.copyWith(text: t));
                        setState(() => _textRevision++);
                      }),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );

      case PersonEffectType.sticker:
        return _panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Sticker',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _stickerOptions.map((st) {
                    final bool selected = fx.stickerAsset == st;
                    return Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: GestureDetector(
                        onTap: () {
                          tapFeedback();
                          editor.updatePersonEffect(
                              person.id, fx.copyWith(stickerAsset: st));
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: selected
                                ? accentToken.withValues(alpha: 0.18)
                                : surfaceToken,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color:
                                  selected ? accentToken : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Center(
                            child:
                                Text(st, style: const TextStyle(fontSize: 26)),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
    }
  }

  // ------------------------------------------------------------------
  // Bottom bars
  // ------------------------------------------------------------------

  Widget _barShell({required Widget child}) {
    return Container(
      decoration: const BoxDecoration(
        color: surfaceToken,
        border: Border(top: BorderSide(color: dividerToken)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: child,
        ),
      ),
    );
  }

  Widget _buildBottomBar(
      EditorController editor, List<Person> persons, PersonEffect fx) {
    final bool canApplyAll =
        persons.length > 1 && fx.type != PersonEffectType.none;

    return _barShell(
      child: SizedBox(
        width: double.infinity,
        height: 46,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            disabledForegroundColor: mutedToken,
            side: const BorderSide(color: dividerToken),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999)),
          ),
          onPressed: canApplyAll
              ? () {
                  tapFeedback();
                  _applyToAll(editor, persons, fx);
                }
              : null,
          icon: const PhosphorIcon(PhosphorIconsRegular.users, size: 16),
          label: const Text('Apply to all faces',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  Widget _buildMergeBar(EditorController editor) {
    final int n = _selectedForMerge.length;
    return _barShell(
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 46,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: dividerToken),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999)),
                ),
                onPressed: () {
                  tapFeedback();
                  _exitMerge();
                },
                child: const Text('Cancel',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 46,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentToken,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: cardToken,
                  disabledForegroundColor: mutedToken,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999)),
                ),
                onPressed: n >= 2
                    ? () {
                        tapFeedback();
                        editor.mergeSelectedPersons(_selectedForMerge.toList());
                        _exitMerge();
                      }
                    : null,
                icon: const PhosphorIcon(PhosphorIconsRegular.gitMerge, size: 16),
                label: Text(n >= 2 ? 'Merge $n faces' : 'Pick 2 or more',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Text field that owns its controller, so the cursor no longer jumps while typing.
class _LabelField extends StatefulWidget {
  const _LabelField({super.key, required this.initialText, required this.onChanged});

  final String initialText;
  final ValueChanged<String> onChanged;

  @override
  State<_LabelField> createState() => _LabelFieldState();
}

class _LabelFieldState extends State<_LabelField> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      maxLength: 24,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      cursorColor: accentToken,
      decoration: InputDecoration(
        counterText: '',
        hintText: 'Type a label…',
        hintStyle: const TextStyle(color: mutedToken, fontSize: 13),
        filled: true,
        fillColor: surfaceToken,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accentToken, width: 1.5),
        ),
      ),
      onChanged: widget.onChanged,
    );
  }
}