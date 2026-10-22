import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:provider/provider.dart';

import 'package:flutter_video_editor/core/models/face_tracking_model.dart';
import 'package:flutter_video_editor/core/models/project_model.dart';
import 'package:flutter_video_editor/features/editor/controllers/editor_controller.dart';
import 'package:flutter_video_editor/features/editor/utils/editor_helpers.dart';

class FaceTrackingSheet extends StatefulWidget {
  const FaceTrackingSheet({super.key});

  @override
  State<FaceTrackingSheet> createState() => _FaceTrackingSheetState();
}

class _FaceTrackingSheetState extends State<FaceTrackingSheet> {
  bool _isAnalyzing = false;
  double _progress = 0.0;
  String _statusText = '';

  String? _selectedPersonId;
  final Set<String> _selectedForMerge = {};

  final TextEditingController _textCtrl = TextEditingController();
  static const List<String> _stickerOptions = ['😎', '🥸', '🎭', '🤡', '🤖', '🐱', '🔥', '✨'];

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _startTracking(EditorController editor) async {
    setState(() {
      _isAnalyzing = true;
      _progress = 0.0;
      _statusText = 'Initializing face detection...';
    });

    try {
      final FaceTrackingData? result = await editor.runFaceTrackingOnSelectedClip(
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
        setState(() {
          _selectedPersonId = result.persons.first.id;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final TimelineClip? clip = editor.selectedClip;

    if (clip == null) {
      return const Center(
        child: Text(
          'Select a video or image clip to enable face tracking.',
          style: TextStyle(color: mutedToken, fontSize: 13),
        ),
      );
    }

    final FaceTrackingData tracking = clip.faceTrackingData;

    if (_isAnalyzing) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: accentToken),
            const SizedBox(height: 16),
            Text(
              _statusText,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: _progress,
              backgroundColor: cardToken,
              color: accentToken,
            ),
            const SizedBox(height: 8),
            Text(
              '${(_progress * 100).round()}%',
              style: const TextStyle(color: mutedToken, fontSize: 12),
            ),
          ],
        ),
      );
    }

    if (!tracking.isProcessed || tracking.persons.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const PhosphorIcon(PhosphorIconsRegular.userFocus, size: 48, color: accentToken),
              const SizedBox(height: 12),
              const Text(
                'Auto Face Detection & Tracking',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Extract frames, detect faces, build continuous tracks, and group people on timeline.',
                textAlign: TextAlign.center,
                style: TextStyle(color: mutedToken, fontSize: 12),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentToken,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: () => _startTracking(editor),
                icon: const PhosphorIcon(PhosphorIconsBold.scan, size: 18),
                label: const Text(
                  'Scan & Detect Faces',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Default select first person if unselected or deleted
    if (_selectedPersonId == null || !tracking.persons.any((p) => p.id == _selectedPersonId)) {
      _selectedPersonId = tracking.persons.first.id;
    }

    final Person activePerson = tracking.persons.firstWhere((p) => p.id == _selectedPersonId);
    final PersonEffect currentFx = activePerson.effects.isNotEmpty
        ? activePerson.effects.first
        : const PersonEffect();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Person Chips Bar
        Row(
          children: [
            Text(
              '${tracking.persons.length} Persons Found',
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            if (_selectedForMerge.length >= 2)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: accentToken),
                onPressed: () {
                  editor.mergeSelectedPersons(_selectedForMerge.toList());
                  setState(() {
                    _selectedForMerge.clear();
                  });
                },
                icon: const PhosphorIcon(PhosphorIconsRegular.gitMerge, size: 16),
                label: Text('Merge (${_selectedForMerge.length})'),
              ),
            IconButton(
              tooltip: 'Re-analyze',
              icon: const PhosphorIcon(PhosphorIconsRegular.arrowsClockwise, color: mutedToken, size: 18),
              onPressed: () => _startTracking(editor),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Persons Horizontal List
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: tracking.persons.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, idx) {
              final Person p = tracking.persons[idx];
              final bool isSelected = p.id == _selectedPersonId;
              final bool isMultiSelected = _selectedForMerge.contains(p.id);

              return GestureDetector(
                onTap: () {
                  tapFeedback();
                  setState(() {
                    _selectedPersonId = p.id;
                  });
                },
                onLongPress: () {
                  tapFeedback();
                  setState(() {
                    if (isMultiSelected) {
                      _selectedForMerge.remove(p.id);
                    } else {
                      _selectedForMerge.add(p.id);
                    }
                  });
                },
                child: Container(
                  width: 64,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isSelected ? accentToken.withValues(alpha: 0.15) : cardToken,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isMultiSelected
                          ? Colors.amber
                          : (isSelected ? accentToken : Colors.transparent),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: surfaceToken,
                          shape: BoxShape.circle,
                          image: p.thumbnailBytes != null
                              ? DecorationImage(
                                  image: MemoryImage(p.thumbnailBytes!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: p.thumbnailBytes == null
                            ? const Center(
                                child: PhosphorIcon(PhosphorIconsRegular.user, size: 18, color: Colors.white70),
                              )
                            : null,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isSelected ? accentToken : Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 20),
        const Divider(color: dividerToken),
        const SizedBox(height: 8),

        // Effect Types Selection
        Row(
          children: [
            Text(
              '${activePerson.name} Effect',
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            if (activePerson.tracks.length > 1)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: dividerToken),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
                onPressed: () {
                  editor.splitPersonTrack(activePerson.id, activePerson.tracks.last.id);
                },
                icon: const PhosphorIcon(PhosphorIconsRegular.arrowsSplit, size: 14),
                label: const Text('Split Track', style: TextStyle(fontSize: 11)),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // Effect Type Chips
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildEffectChip(
              label: 'None',
              icon: PhosphorIconsRegular.prohibit,
              isSelected: currentFx.type == PersonEffectType.none,
              onTap: () {
                editor.updatePersonEffect(activePerson.id, const PersonEffect(type: PersonEffectType.none));
              },
            ),
            _buildEffectChip(
              label: 'Blur',
              icon: PhosphorIconsRegular.dropHalf,
              isSelected: currentFx.type == PersonEffectType.blur,
              onTap: () {
                editor.updatePersonEffect(activePerson.id, const PersonEffect(type: PersonEffectType.blur, intensity: 10.0));
              },
            ),
            _buildEffectChip(
              label: 'Mosaic',
              icon: PhosphorIconsRegular.gridFour,
              isSelected: currentFx.type == PersonEffectType.mosaic,
              onTap: () {
                editor.updatePersonEffect(activePerson.id, const PersonEffect(type: PersonEffectType.mosaic, intensity: 16.0));
              },
            ),
            _buildEffectChip(
              label: 'Text',
              icon: PhosphorIconsRegular.textAa,
              isSelected: currentFx.type == PersonEffectType.text,
              onTap: () {
                editor.updatePersonEffect(activePerson.id, PersonEffect(type: PersonEffectType.text, text: activePerson.name));
              },
            ),
            _buildEffectChip(
              label: 'Sticker',
              icon: PhosphorIconsRegular.smiley,
              isSelected: currentFx.type == PersonEffectType.sticker,
              onTap: () {
                editor.updatePersonEffect(activePerson.id, const PersonEffect(type: PersonEffectType.sticker, stickerAsset: '😎'));
              },
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Parameter Adjustments
        if (currentFx.type == PersonEffectType.blur || currentFx.type == PersonEffectType.mosaic) ...[
          Text(
            currentFx.type == PersonEffectType.blur ? 'Blur Radius' : 'Mosaic Tile Size',
            style: const TextStyle(color: mutedToken, fontSize: 12),
          ),
          Slider(
            value: currentFx.intensity.clamp(2.0, 50.0),
            min: 2.0,
            max: 50.0,
            activeColor: accentToken,
            inactiveColor: cardToken,
            onChanged: (val) {
              editor.updatePersonEffect(activePerson.id, currentFx.copyWith(intensity: val));
            },
          ),
        ] else if (currentFx.type == PersonEffectType.text) ...[
          const Text('Label Text', style: TextStyle(color: mutedToken, fontSize: 12)),
          const SizedBox(height: 6),
          TextField(
            controller: _textCtrl..text = currentFx.text,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              filled: true,
              fillColor: cardToken,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: (val) {
              editor.updatePersonEffect(activePerson.id, currentFx.copyWith(text: val));
            },
          ),
        ] else if (currentFx.type == PersonEffectType.sticker) ...[
          const Text('Sticker Emoji', style: TextStyle(color: mutedToken, fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: _stickerOptions.map((st) {
              final bool isSelected = currentFx.stickerAsset == st;
              return GestureDetector(
                onTap: () {
                  editor.updatePersonEffect(activePerson.id, currentFx.copyWith(stickerAsset: st));
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected ? accentToken.withValues(alpha: 0.2) : cardToken,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isSelected ? accentToken : Colors.transparent),
                  ),
                  child: Text(st, style: const TextStyle(fontSize: 22)),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildEffectChip({
    required String label,
    required PhosphorIconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        tapFeedback();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? accentToken : cardToken,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          children: [
            PhosphorIcon(icon, size: 16, color: isSelected ? Colors.black : Colors.white),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
