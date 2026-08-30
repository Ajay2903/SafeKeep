import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:safekeep/core/constants/app_motion.dart';
import 'package:safekeep/core/theme/app_colors.dart';

/// The app's shield mark, with an optional locked/unlocked transition.
///
/// Drawn rather than shipped as an asset: it is a handful of paths, it
/// stays crisp at any size, and it recolours with the theme instead of
/// needing a second file for dark mode.
///
/// The mark is decorative and is hidden from screen readers — the
/// surrounding screen carries the meaning in text.
class VaultMark extends StatefulWidget {
  const VaultMark({
    this.size = 96,
    this.isUnlocked = false,
    this.isBusy = false,
    super.key,
  });

  final double size;

  /// Draws the shackle open. Animates when this changes.
  final bool isUnlocked;

  /// Runs a slow, continuous ring sweep, for the seconds during which
  /// Argon2id is deriving a key and there is nothing else to show.
  final bool isBusy;

  @override
  State<VaultMark> createState() => _VaultMarkState();
}

class _VaultMarkState extends State<VaultMark> with TickerProviderStateMixin {
  late final AnimationController _unlock = AnimationController(
    vsync: this,
    duration: AppMotion.long,
    value: widget.isUnlocked ? 1 : 0,
  );

  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isBusy) _sweep.repeat();
  }

  @override
  void didUpdateWidget(VaultMark oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isUnlocked != oldWidget.isUnlocked) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _unlock.value = widget.isUnlocked ? 1 : 0;
      } else if (widget.isUnlocked) {
        _unlock.forward();
      } else {
        _unlock.reverse();
      }
    }

    if (widget.isBusy != oldWidget.isBusy) {
      if (widget.isBusy) {
        _sweep.repeat();
      } else {
        _sweep
          ..stop()
          ..value = 0;
      }
    }
  }

  @override
  void dispose() {
    _unlock.dispose();
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ExcludeSemantics(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: Listenable.merge([_unlock, _sweep]),
          builder: (context, _) {
            return CustomPaint(
              painter: _VaultMarkPainter(
                unlockProgress: Curves.easeOutCubic.transform(_unlock.value),
                sweepProgress: _sweep.value,
                showSweep: widget.isBusy,
                shieldColor: scheme.onSurface,
                accentColor: AppColors.accent,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _VaultMarkPainter extends CustomPainter {
  _VaultMarkPainter({
    required this.unlockProgress,
    required this.sweepProgress,
    required this.showSweep,
    required this.shieldColor,
    required this.accentColor,
  });

  final double unlockProgress;
  final double sweepProgress;
  final bool showSweep;
  final Color shieldColor;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = w * 0.055;

    // --- shield outline -------------------------------------------------
    final shield = Path()
      ..moveTo(w * 0.5, h * 0.06)
      ..lineTo(w * 0.87, h * 0.22)
      ..lineTo(w * 0.87, h * 0.52)
      // Sides curve inward to a point, so the form reads as a shield
      // rather than a generic pentagon.
      ..cubicTo(w * 0.87, h * 0.76, w * 0.7, h * 0.9, w * 0.5, h * 0.96)
      ..cubicTo(w * 0.3, h * 0.9, w * 0.13, h * 0.76, w * 0.13, h * 0.52)
      ..lineTo(w * 0.13, h * 0.22)
      ..close();

    canvas
      ..drawPath(
        shield,
        Paint()
          ..color = accentColor.withValues(alpha: 0.07)
          ..style = PaintingStyle.fill,
      )
      ..drawPath(
        shield,
        Paint()
          ..color = shieldColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeJoin = StrokeJoin.round,
      )
      // --- padlock body -------------------------------------------------
      ..drawRRect(
        RRect.fromLTRBR(
          w * 0.34,
          h * 0.47,
          w * 0.66,
          h * 0.71,
          Radius.circular(w * 0.05),
        ),
        Paint()..color = accentColor,
      );

    // --- shackle --------------------------------------------------------
    // Lifts and rotates slightly as it opens: a straight lift reads as a
    // glitch, a small pivot reads as a mechanism.
    final lift = h * 0.06 * unlockProgress;
    final tilt = 0.35 * unlockProgress;

    canvas
      ..save()
      ..translate(w * 0.5, h * 0.47 - lift)
      ..rotate(tilt)
      ..translate(-w * 0.5, -(h * 0.47));

    final shackle = Path()
      ..moveTo(w * 0.40, h * 0.47)
      ..lineTo(w * 0.40, h * 0.39)
      ..arcToPoint(
        Offset(w * 0.60, h * 0.39),
        radius: Radius.circular(w * 0.10),
      )
      ..lineTo(w * 0.60, h * 0.47);

    canvas
      ..drawPath(
        shackle,
        Paint()
          ..color = accentColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 0.9
          ..strokeCap = StrokeCap.round,
      )
      ..restore();

    // --- busy sweep -----------------------------------------------------
    if (showSweep) {
      final rect = Rect.fromCircle(
        center: Offset(w * 0.5, h * 0.5),
        radius: w * 0.46,
      );
      canvas.drawArc(
        rect,
        sweepProgress * 2 * math.pi,
        math.pi * 0.5,
        false,
        Paint()
          ..color = accentColor.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 0.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_VaultMarkPainter old) =>
      old.unlockProgress != unlockProgress ||
      old.sweepProgress != sweepProgress ||
      old.showSweep != showSweep ||
      old.shieldColor != shieldColor;
}
