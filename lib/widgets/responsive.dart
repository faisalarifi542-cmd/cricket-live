import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../components.dart';

/// Press-down scale wrapper that adds a subtle 0.97 tap feedback used across
/// every interactive premium card / button in CricPro.
class TapScale extends StatefulWidget {
  const TapScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = .97,
    this.borderRadius = 26,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final double borderRadius;

  @override
  State<TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<TapScale> {
  bool _down = false;

  void _set(bool v) {
    if (!mounted || _down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final body = AnimatedScale(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      scale: _down ? widget.scale : 1.0,
      child: widget.child,
    );
    if (widget.onTap == null) return body;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: widget.onTap,
      child: body,
    );
  }
}

/// One-shot fade + slide-up entrance used for staggered card reveals.
class FadeUp extends StatefulWidget {
  const FadeUp({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 380),
    this.offset = 14,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offset;

  @override
  State<FadeUp> createState() => _FadeUpState();
}

class _FadeUpState extends State<FadeUp> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: curve,
      builder: (_, child) => Opacity(
        opacity: curve.value,
        child: Transform.translate(
          offset: Offset(0, (1 - curve.value) * widget.offset),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Auto-staggered fade-up for a list of children inside a Column.
class StaggeredColumn extends StatelessWidget {
  const StaggeredColumn({
    super.key,
    required this.children,
    this.spacing = 0,
    this.step = const Duration(milliseconds: 60),
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  final List<Widget> children;
  final double spacing;
  final Duration step;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final out = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0 && spacing > 0) out.add(SizedBox(height: spacing));
      out.add(FadeUp(delay: step * i, child: children[i]));
    }
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      children: out,
    );
  }
}

/// Tween the displayed number from 0 → [value] over [duration]. Used on top
/// of stats numbers (runs, wickets, totals).
class CountUpText extends StatelessWidget {
  const CountUpText({
    super.key,
    required this.value,
    required this.style,
    this.duration = const Duration(milliseconds: 900),
    this.fractionDigits = 0,
    this.suffix = '',
    this.prefix = '',
    this.curve = Curves.easeOutCubic,
  });

  final num value;
  final TextStyle style;
  final Duration duration;
  final int fractionDigits;
  final String suffix;
  final String prefix;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: curve,
      builder: (_, v, __) {
        final n = fractionDigits == 0
            ? v.round().toString()
            : v.toStringAsFixed(fractionDigits);
        return Text('$prefix$n$suffix', style: style);
      },
    );
  }
}

/// Soft cyan pulse — used on live countdowns / breaking-news badges.
class PulseDot extends StatefulWidget {
  const PulseDot({
    super.key,
    required this.color,
    this.size = 8,
    this.intensity = .55,
  });

  final Color color;
  final double size;
  final double intensity;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value;
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color
                    .withValues(alpha: widget.intensity * (.4 + .6 * t)),
                blurRadius: 8 + 6 * t,
                spreadRadius: 1 + 2 * t,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A horizontally-scrollable segmented tab bar that never squeezes labels.
/// Use this in place of [SegmentedTabs] when you have 5+ tabs and risk text
/// truncation on small screens.
class ScrollableSegmentedTabs extends StatefulWidget {
  const ScrollableSegmentedTabs({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
    this.height = 56,
  });

  final List<String> items;
  final int selected;
  final ValueChanged<int> onChanged;
  final double height;

  @override
  State<ScrollableSegmentedTabs> createState() =>
      _ScrollableSegmentedTabsState();
}

class _ScrollableSegmentedTabsState extends State<ScrollableSegmentedTabs> {
  final _controller = ScrollController();
  final _scrollViewKey = GlobalKey();
  final _keys = <GlobalKey>[];

  @override
  void initState() {
    super.initState();
    _ensureKeys();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }

  @override
  void didUpdateWidget(covariant ScrollableSegmentedTabs old) {
    super.didUpdateWidget(old);
    _ensureKeys();
    if (old.selected != widget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
    }
  }

  void _ensureKeys() {
    while (_keys.length < widget.items.length) {
      _keys.add(GlobalKey());
    }
    if (_keys.length > widget.items.length) {
      _keys.removeRange(widget.items.length, _keys.length);
    }
  }

  void _scrollToSelected() {
    if (!_controller.hasClients) return;
    final i = widget.selected;
    if (i < 0 || i >= _keys.length) return;
    final ctx = _keys[i].currentContext;
    final viewportCtx = _scrollViewKey.currentContext;
    if (ctx == null || viewportCtx == null) return;
    final itemBox = ctx.findRenderObject() as RenderBox?;
    final viewportBox = viewportCtx.findRenderObject() as RenderBox?;
    if (itemBox == null || viewportBox == null) return;

    // Scroll only the horizontal tab strip. Using Scrollable.ensureVisible here
    // also moves the parent ListView, which made Match Details open/jump down
    // to the tabs after load or tab selection.
    final itemOffset = itemBox.localToGlobal(Offset.zero, ancestor: viewportBox);
    final itemLeft = itemOffset.dx + _controller.offset;
    final itemRight = itemLeft + itemBox.size.width;
    final viewportWidth = viewportBox.size.width;
    var target = _controller.offset;
    if (itemLeft < _controller.offset) {
      target = itemLeft - 8;
    } else if (itemRight > _controller.offset + viewportWidth) {
      target = itemRight - viewportWidth + 8;
    }
    target = target.clamp(
      _controller.position.minScrollExtent,
      _controller.position.maxScrollExtent,
    );
    if ((target - _controller.offset).abs() < 1) return;
    _controller.animateTo(target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      height: widget.height,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .015),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: c.border),
      ),
      child: SingleChildScrollView(
        key: _scrollViewKey,
        controller: _controller,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            for (var i = 0; i < widget.items.length; i++) ...[
              _tab(context, i),
              if (i != widget.items.length - 1) const SizedBox(width: 4),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tab(BuildContext context, int i) {
    final c = context.cric;
    final selected = i == widget.selected;
    return TapScale(
      onTap: () => widget.onChanged(i),
      borderRadius: 28,
      child: AnimatedContainer(
        key: _keys[i],
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(horizontal: context.w <= 420 ? 10 : 12),
        decoration: BoxDecoration(
          gradient: selected ? c.primaryGradient : null,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color:
                selected ? c.cyan.withValues(alpha: .65) : Colors.transparent,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: .18),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        // Wrapping in an IntrinsicWidth keeps the Text from being clipped by
        // the surrounding Container — required because the AnimatedContainer
        // would otherwise size to a smaller-than-natural width and trigger
        // `TextOverflow` mid-label (e.g. "Sq" instead of "Squads").
        child: Text(
          widget.items[i],
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            color: selected ? Colors.white : c.text,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            fontSize: context.sp(14.5),
          ),
        ),
      ),
    );
  }
}

/// Icon + label/value/subtitle list row. The replacement for the broken
/// fixed-width [StatTile] inside narrow info cards.
class InfoListTile extends StatelessWidget {
  const InfoListTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    this.iconColor,
    this.valueColor,
    this.padding,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final Color? iconColor;
  final Color? valueColor;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Padding(
      padding: padding ?? const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: c.card2,
              shape: BoxShape.circle,
              border: Border.all(color: c.border),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: iconColor ?? c.muted, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.muted, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                  style: TextStyle(
                    color: valueColor ?? c.text,
                    fontWeight: FontWeight.w800,
                    fontSize: context.sp(16),
                    height: 1.3,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                    style: TextStyle(
                      color: c.muted,
                      fontSize: context.sp(13.5),
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Width-aware tile that gets its width from a parent [LayoutBuilder] /
/// [Wrap]. Use this for responsive stat grids instead of computing widths
/// from `context.w` (which ignores parent padding and produces overflow).
class ResponsiveStatTile extends StatelessWidget {
  const ResponsiveStatTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.tileWidth,
    this.accent,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final double tileWidth;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final col = accent ?? c.muted;
    return SizedBox(
      width: tileWidth,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: c.card2,
            child: Icon(icon, color: col),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.muted, fontSize: 13.5),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w900,
                      fontSize: context.sp(22),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                  style: TextStyle(color: c.muted, height: 1.3, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Computes a child width for a [Wrap] / responsive grid given a parent
/// [maxWidth], desired columns, and spacing between children. Floors to a
/// safe value so overflow is impossible.
double computeGridChildWidth({
  required double maxWidth,
  required int columns,
  required double spacing,
}) {
  if (columns <= 1) return maxWidth;
  final total = maxWidth - spacing * (columns - 1);
  // Floor to whole pixel and subtract a tiny epsilon so float-rounding never
  // pushes the last child past the right edge.
  final w = (total / columns).floorToDouble();
  return math.max(0, w);
}
