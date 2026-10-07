import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:flutter_video_editor/core/models/shader_clip_model.dart';
import 'package:flutter_video_editor/core/models/shader_effect_model.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';

class EffectParameterPanel extends StatefulWidget {
  const EffectParameterPanel({
    super.key,
    required this.effect,
    required this.clip,
    required this.onParameterChanged,
    required this.onAddKeyframe,
    required this.onRemoveKeyframe,
    this.playheadTime = Duration.zero,
  });

  final ShaderEffect effect;
  final ShaderEffectClip clip;
  final void Function(String paramId, dynamic newValue) onParameterChanged;
  final void Function(String paramId, dynamic value, AnimationEasing easing) onAddKeyframe;
  final void Function(String paramId, String keyframeId) onRemoveKeyframe;
  final Duration playheadTime;

  @override
  State<EffectParameterPanel> createState() => _EffectParameterPanelState();
}

class _EffectParameterPanelState extends State<EffectParameterPanel> {
  AnimationEasing _selectedEasing = AnimationEasing.linear;

  static const List<Color> _swatches = <Color>[
    Colors.white,
    Color(0xFF00E5FF),
    Color(0xFFFF0055),
    Color(0xFFFFB300),
    Color(0xFF00FF66),
    Color(0xFF9D00FF),
    Color(0xFFFF6B00),
    Colors.black,
  ];

  @override
  Widget build(BuildContext context) {
    final clipRelativeTime = widget.playheadTime - widget.clip.start;
    final interpolatedValues = widget.clip.getInterpolatedParameters(clipRelativeTime);

    return Container(
      color: EditorTokens.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: EditorTokens.border)),
            ),
            child: Row(
              children: [
                const HugeIcon(
                  icon: HugeIcons.strokeRoundedFilter,
                  color: EditorTokens.text,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.effect.name} Controls',
                    style: const TextStyle(
                      color: EditorTokens.text,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ),
                _buildEasingDropdown(),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: widget.effect.parameters.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final param = widget.effect.parameters[index];
                final currentValue = interpolatedValues[param.id] ?? param.value;
                final keyframeAnim = widget.clip.keyframeAnimations.firstWhere(
                  (a) => a.parameterId == param.id,
                  orElse: () => KeyframeAnimation(id: '', parameterId: param.id),
                );
                final hasKeyframeAtTime = keyframeAnim.keyframes.any(
                  (k) => (k.time.inMilliseconds - clipRelativeTime.inMilliseconds).abs() < 50,
                );

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: EditorTokens.elevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: EditorTokens.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              param.label,
                              style: const TextStyle(
                                color: EditorTokens.text,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Poppins',
                              ),
                            ),
                          ),
                          Text(
                            _formatDisplayValue(param.type, currentValue),
                            style: const TextStyle(
                              color: EditorTokens.accent,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Poppins',
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: hasKeyframeAtTime ? 'Remove Keyframe' : 'Add Keyframe',
                            icon: HugeIcon(
                              icon: hasKeyframeAtTime
                                  ? HugeIcons.strokeRoundedBookmark02
                                  : HugeIcons.strokeRoundedAdd01,
                              color: hasKeyframeAtTime ? EditorTokens.accent : EditorTokens.muted,
                              size: 18,
                            ),
                            onPressed: () {
                              if (hasKeyframeAtTime) {
                                final kf = keyframeAnim.keyframes.firstWhere(
                                  (k) => (k.time.inMilliseconds - clipRelativeTime.inMilliseconds).abs() < 50,
                                );
                                widget.onRemoveKeyframe(param.id, kf.id);
                              } else {
                                widget.onAddKeyframe(param.id, currentValue, _selectedEasing);
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildParameterControl(param, currentValue),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEasingDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: EditorTokens.elevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: EditorTokens.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<AnimationEasing>(
          value: _selectedEasing,
          dropdownColor: EditorTokens.elevated,
          isDense: true,
          style: const TextStyle(
            color: EditorTokens.text,
            fontSize: 11,
            fontFamily: 'Poppins',
          ),
          items: AnimationEasing.values.map((easing) {
            return DropdownMenuItem<AnimationEasing>(
              value: easing,
              child: Text(easing.name),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() => _selectedEasing = val);
            }
          },
        ),
      ),
    );
  }

  Widget _buildParameterControl(ShaderParameter param, dynamic currentValue) {
    switch (param.type) {
      case ParameterType.float:
      case ParameterType.integer:
        final double val = currentValue is num ? currentValue.toDouble() : param.doubleValue;
        return SliderTheme(
          data: const SliderThemeData(
            trackHeight: 3,
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: EditorTokens.text,
            inactiveTrackColor: EditorTokens.border,
            thumbColor: EditorTokens.text,
          ),
          child: Slider(
            value: val.clamp(param.min, param.max),
            min: param.min,
            max: param.max,
            onChanged: (newVal) {
              widget.onParameterChanged(
                param.id,
                param.type == ParameterType.integer ? newVal.round() : newVal,
              );
            },
          ),
        );
      case ParameterType.color:
        Color curColor = currentValue is Color
            ? currentValue
            : (currentValue is int ? Color(currentValue) : param.colorValue);

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _swatches.map((color) {
            final isSelected = curColor.toARGB32() == color.toARGB32();
            return GestureDetector(
              onTap: () => widget.onParameterChanged(param.id, color),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? EditorTokens.text : EditorTokens.border,
                    width: isSelected ? 2.5 : 1.0,
                  ),
                ),
              ),
            );
          }).toList(),
        );
      case ParameterType.boolean:
        final bool val = currentValue is bool ? currentValue : param.boolValue;
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(
            val ? 'Enabled' : 'Disabled',
            style: const TextStyle(color: EditorTokens.muted, fontSize: 12, fontFamily: 'Poppins'),
          ),
          value: val,
          activeTrackColor: EditorTokens.text,
          onChanged: (newVal) => widget.onParameterChanged(param.id, newVal),
        );
      case ParameterType.choice:
        final String val = currentValue is String ? currentValue : (param.options.isNotEmpty ? param.options.first : '');
        return DropdownButton<String>(
          value: param.options.contains(val) ? val : (param.options.isNotEmpty ? param.options.first : null),
          dropdownColor: EditorTokens.elevated,
          isExpanded: true,
          style: const TextStyle(color: EditorTokens.text, fontSize: 12, fontFamily: 'Poppins'),
          items: param.options.map((opt) {
            return DropdownMenuItem<String>(
              value: opt,
              child: Text(opt),
            );
          }).toList(),
          onChanged: (newVal) {
            if (newVal != null) {
              widget.onParameterChanged(param.id, newVal);
            }
          },
        );
      case ParameterType.position:
        final Offset pos = currentValue is Offset ? currentValue : param.positionValue;
        return Column(
          children: [
            Row(
              children: [
                const Text('X: ', style: TextStyle(color: EditorTokens.muted, fontSize: 11)),
                Expanded(
                  child: Slider(
                    value: pos.dx.clamp(-1.0, 1.0),
                    min: -1.0,
                    max: 1.0,
                    onChanged: (x) => widget.onParameterChanged(param.id, Offset(x, pos.dy)),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const Text('Y: ', style: TextStyle(color: EditorTokens.muted, fontSize: 11)),
                Expanded(
                  child: Slider(
                    value: pos.dy.clamp(-1.0, 1.0),
                    min: -1.0,
                    max: 1.0,
                    onChanged: (y) => widget.onParameterChanged(param.id, Offset(pos.dx, y)),
                  ),
                ),
              ],
            ),
          ],
        );
    }
  }

  String _formatDisplayValue(ParameterType type, dynamic value) {
    if (value == null) return '';
    if (type == ParameterType.float && value is num) {
      return value.toDouble().toStringAsFixed(2);
    }
    if (type == ParameterType.integer && value is num) {
      return value.toInt().toString();
    }
    if (type == ParameterType.boolean) {
      return value == true ? 'ON' : 'OFF';
    }
    return value.toString();
  }
}
