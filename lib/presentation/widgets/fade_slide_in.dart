import 'package:flutter/material.dart';
import 'package:safekeep/core/constants/app_motion.dart';

/// Fades and lifts its child into place once, on first build.
///
/// Used to stagger a screen's content: a small [delay] on each successive
/// element makes a screen assemble rather than appear, which is what
/// makes an interface feel considered instead of merely fast.
///
/// # Accessibility
///
/// Honours the platform's reduce-motion setting. When animations are
/// disabled the child is shown immediately at full opacity and final
/// position — never hidden, never delayed. Motion here is decoration, and
/// decoration must not gate content.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    required this.child,
    this.delay = Duration.zero,
    this.duration = AppMotion.medium,
    this.offset = 12,
    super.key,
  });

  final Widget child;

  /// How long to wait before starting. Stagger siblings with this.
  final Duration delay;

  final Duration duration;

  /// Vertical distance travelled, in logical pixels. Small on purpose;
  /// a long slide reads as sluggish.
  final double offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  late final Animation<double> _animation = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.enter,
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      return;
    }
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(
          opacity: _animation.value,
          child: Transform.translate(
            offset: Offset(0, widget.offset * (1 - _animation.value)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
