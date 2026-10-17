import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:flutter_video_editor/features/editor/theme/editor_tokens.dart';
import 'package:flutter_video_editor/core/widgets/loading_wave.dart';

/// Shared monochrome building blocks for the caption sheets.
/// Palette: black / white / greys only. Corners are small (6px), never pills.
class CaptionMono {
  static const double radius = 6;
  static const Color ink = Colors.white;
  static const Color onInk = Colors.black;
  static const String font = 'Ubuntu Sans';
}

/// Sheet title row with an optional trailing action.
class MonoSheetHeader extends StatelessWidget {
  const MonoSheetHeader({super.key, required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: EditorTokens.border)),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: CaptionMono.ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              fontFamily: CaptionMono.font,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Filled (white) or outlined button with a small corner radius.
class MonoButton extends StatelessWidget {
  const MonoButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.filled = false,
    this.busy = false,
    this.expand = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool filled;
  final bool busy;
  final bool expand;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final fg = filled
        ? CaptionMono.onInk
        : (danger ? Colors.redAccent : CaptionMono.ink);
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          TextShimmerWave(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFamily: CaptionMono.font,
            ),
            baseColor: fg.withValues(alpha: 0.5),
            waveColor: fg,
          )
        else ...[
          if (icon != null) ...[
            PhosphorIcon(icon!, size: 16, color: fg),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFamily: CaptionMono.font,
            ),
          ),
        ],
      ],
    );

    return Opacity(
      opacity: onTap == null && !busy ? 0.4 : 1,
      child: Material(
        color: filled ? CaptionMono.ink : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CaptionMono.radius),
          side: filled
              ? BorderSide.none
              : const BorderSide(color: EditorTokens.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(CaptionMono.radius),
          onTap: busy ? null : onTap,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Square-ish segmented control (replaces rounded chips).
class MonoSegmented<T> extends StatelessWidget {
  const MonoSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final entries = options.entries.toList();
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: EditorTokens.elevated,
        borderRadius: BorderRadius.circular(CaptionMono.radius + 2),
        border: Border.all(color: EditorTokens.border),
      ),
      child: Row(
        children: [
          for (final e in entries)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(e.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: e.key == value ? CaptionMono.ink : Colors.transparent,
                    borderRadius: BorderRadius.circular(CaptionMono.radius),
                  ),
                  child: Text(
                    e.value,
                    style: TextStyle(
                      color: e.key == value
                          ? CaptionMono.onInk
                          : EditorTokens.muted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      fontFamily: CaptionMono.font,
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

/// Small uppercase-free section label.
class MonoLabel extends StatelessWidget {
  const MonoLabel(this.text, {super.key, this.bottom = 8});
  final String text;
  final double bottom;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Text(
          text,
          style: const TextStyle(
            color: EditorTokens.muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            fontFamily: CaptionMono.font,
          ),
        ),
      );
}

String formatCueTime(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final t = (d.inMilliseconds.remainder(1000) ~/ 100).toString();
  return '$m:$s.$t';
}