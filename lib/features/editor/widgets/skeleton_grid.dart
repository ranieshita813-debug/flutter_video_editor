import 'package:flutter/material.dart';

class SkeletonGrid extends StatefulWidget {
  const SkeletonGrid({
    super.key,
    this.itemCount = 6,
    this.crossAxisCount = 3,
    this.childAspectRatio = 1.0,
  });

  final int itemCount;
  final int crossAxisCount;
  final double childAspectRatio;

  @override
  State<SkeletonGrid> createState() => _SkeletonGridState();
}

class _SkeletonGridState extends State<SkeletonGrid> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final opacity = 0.2 + (_ctrl.value * 0.3);
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: widget.crossAxisCount,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: widget.childAspectRatio,
          ),
          itemCount: widget.itemCount,
          itemBuilder: (context, index) {
            return Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: opacity),
                borderRadius: BorderRadius.circular(12),
              ),
            );
          },
        );
      },
    );
  }
}
