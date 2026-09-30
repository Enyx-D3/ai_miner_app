import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'theme.dart';

/// Top branded bar with Global Context logo, title, and actions
class GlobalContextBrandHeader extends StatelessWidget {
  final VoidCallback? onSearch;
  final VoidCallback? onMore;
  final Widget? trailing;

  const GlobalContextBrandHeader({
    super.key,
    this.onSearch,
    this.onMore,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Brain2Theme.primaryBlue,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Brain2Theme.primaryBlue.withOpacity(0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Center(
              child: Text(
                'G',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  fontFamily: 'Roboto',
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'GLOBAL CONTEXT',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
              color: Brain2Theme.textPrimaryOf(context),
            ),
          ),
          const Spacer(),
          if (trailing != null)
            trailing!
          else ...[
            if (onSearch != null)
              IconButton(
                icon: const Icon(Icons.search, size: 22),
                color: Brain2Theme.textSecondaryOf(context),
                splashRadius: 20,
                onPressed: onSearch,
              ),
            if (onMore != null)
              IconButton(
                icon: const Icon(Icons.more_horiz, size: 24),
                color: Brain2Theme.textSecondaryOf(context),
                splashRadius: 20,
                onPressed: onMore,
              ),
          ],
        ],
      ),
    );
  }
}

/// Category tag e.g. "ANDROID · AN01", "GLOBAL / onboarding"
class GlobalContextBreadcrumb extends StatelessWidget {
  final String text;
  final bool isEntry;

  const GlobalContextBreadcrumb(this.text, {super.key, this.isEntry = false});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: Brain2Theme.primaryBlue,
      ),
    );
  }
}

/// Standard page heading with tag, title, and subtitle
class GlobalContextPageHeader extends StatelessWidget {
  final String tag;
  final String title;
  final String description;
  final List<String>? chips;

  const GlobalContextPageHeader({
    super.key,
    required this.tag,
    required this.title,
    required this.description,
    this.chips,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (chips != null && chips!.isNotEmpty)
            Row(
              children: chips!
                  .map(
                    (chip) => Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 8),
                      child: GlobalContextPillBadge(
                        label: chip,
                        color: Brain2Theme.primaryBlueLight,
                        textColor: Brain2Theme.primaryBlue,
                      ),
                    ),
                  )
                  .toList(),
            )
          else
            GlobalContextBreadcrumb(tag),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: Brain2Theme.textPrimaryOf(context),
              letterSpacing: -0.8,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              fontSize: 14,
              color: Brain2Theme.textSecondaryOf(context),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pill badge (e.g. Concept, Local-first, Private by default)
class GlobalContextPillBadge extends StatelessWidget {
  final String label;
  final Color? color;
  final Color? backgroundColor;
  final Color? textColor;

  const GlobalContextPillBadge({
    super.key,
    required this.label,
    this.color,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final isGreen = label.toLowerCase().contains('local') ||
        label.toLowerCase().contains('private') ||
        label.toLowerCase().contains('always') ||
        label.toLowerCase().contains('on');
    final bg = backgroundColor ??
        color ??
        (isGreen ? Brain2Theme.greenLight : Brain2Theme.primaryBlueLight);
    final fg = textColor ??
        (isGreen ? Brain2Theme.greenDark : Brain2Theme.primaryBlue);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Hero card matching "PICK UP WHERE YOU LEFT OFF" in reference screens
class GlobalContextHeroCard extends StatelessWidget {
  final String overline;
  final String title;
  final String subtitle;
  final String buttonText;
  final VoidCallback? onButtonPressed;

  const GlobalContextHeroCard({
    super.key,
    this.overline = 'PICK UP WHERE YOU LEFT OFF',
    required this.title,
    required this.subtitle,
    this.buttonText = 'Continue project ↗',
    this.onButtonPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Brain2Theme.heroCardBgOf(context),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Brain2Theme.heroBorderOf(context), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            overline.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: Brain2Theme.primaryBlueOf(context),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Brain2Theme.textPrimaryOf(context),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: Brain2Theme.textSecondaryOf(context),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: onButtonPressed,
            style: FilledButton.styleFrom(
              backgroundColor: Brain2Theme.primaryBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              elevation: 0,
            ),
            child: Text(
              buttonText,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Section container with outer border, title and pill badge
class GlobalContextSectionCard extends StatelessWidget {
  final String title;
  final String? badgeLabel;
  final List<Widget> children;

  const GlobalContextSectionCard({
    super.key,
    required this.title,
    this.badgeLabel,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Brain2Theme.cardBgOf(context),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Brain2Theme.borderOf(context), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: Brain2Theme.textPrimaryOf(context),
                ),
              ),
              if (badgeLabel != null)
                GlobalContextPillBadge(label: badgeLabel!),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

/// Action Tile matching the reference inner cards
class GlobalContextActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback? onTap;

  const GlobalContextActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Brain2Theme.cardBgOf(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Brain2Theme.borderOf(context), width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Brain2Theme.pillBadgeBgOf(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: Brain2Theme.primaryBlueOf(context),
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Brain2Theme.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Brain2Theme.textSecondaryOf(context),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  actionLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Brain2Theme.primaryBlueOf(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The signature bottom Tick banner seen on all screens: "✓ Tick · 1 pending   Review →"
class GlobalContextTickBanner extends StatelessWidget {
  final int count;
  final VoidCallback? onReview;

  const GlobalContextTickBanner({
    super.key,
    this.count = 1,
    this.onReview,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onReview,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: Brain2Theme.cardBgOf(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Brain2Theme.isDark(context)
                ? const Color(0xFF1E3A8A)
                : const Color(0xFFCCE4F7),
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.check,
              size: 16,
              color: Brain2Theme.primaryBlueOf(context),
            ),
            const SizedBox(width: 10),
            Text(
              count > 0 ? 'Tick · $count pending' : 'Ticks · All caught up',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Brain2Theme.textPrimaryOf(context),
              ),
            ),
            const Spacer(),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  count > 0 ? 'Review →' : 'View all →',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Brain2Theme.primaryBlueOf(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Backward-compatible widget aliases & helpers
// ---------------------------------------------------------------------------

class PageTitle extends StatelessWidget {
  final String title;
  final String description;

  const PageTitle(this.title, this.description, {super.key});

  @override
  Widget build(BuildContext context) => GlobalContextPageHeader(
        tag: 'GLOBAL CONTEXT',
        title: title,
        description: description,
      );
}

class MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const MetricCard(this.label, this.value, this.icon, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Brain2Theme.borderLight),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Brain2Theme.primaryBlueLight,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Brain2Theme.primaryBlue, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Brain2Theme.textMuted,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Brain2Theme.textDark,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

String bestTitle(Map<String, Object?> record) =>
    '${record['title'] ?? record['name'] ?? record['label'] ?? record['text'] ?? record['id'] ?? 'Item'}';

String subline(Map<String, Object?> record) => [
      '${record['status'] ?? ''}',
      '${record['provider'] ?? ''}',
      '${record['updatedAt'] ?? record['createdAt'] ?? ''}',
    ].where((value) => value.isNotEmpty).join(' · ');

class RecordTile extends StatelessWidget {
  final Map<String, Object?> record;
  final VoidCallback? onTap;

  const RecordTile(this.record, {super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GlobalContextActionTile(
      icon: Icons.auto_awesome,
      title: bestTitle(record),
      subtitle: subline(record).isEmpty ? 'Verified record' : subline(record),
      actionLabel: 'Open >',
      onTap: onTap,
    );
  }
}

/// Clean minimalist home icon matching AN01_home.png (pure outline without inner door)
class CleanHomeIcon extends StatelessWidget {
  final Color color;
  final double size;
  final double strokeWidth;

  const CleanHomeIcon({
    super.key,
    required this.color,
    this.size = 22,
    this.strokeWidth = 1.9,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CleanHomePainter(color: color, strokeWidth: strokeWidth),
      ),
    );
  }
}

class _CleanHomePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  const _CleanHomePainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final path = Path();
    final padX = w * 0.14;
    final padTop = h * 0.08;
    final padBottom = h * 0.10;
    final eavesY = h * 0.44;
    final leftX = padX;
    final rightX = w - padX;
    final bottomY = h - padBottom;
    final cornerRadius = w * 0.10;
    final peakRadius = w * 0.06;

    // Start near peak right
    path.moveTo(w / 2 + peakRadius, padTop + peakRadius * 0.8);
    // Slope down to right eaves
    path.lineTo(rightX, eavesY);
    // Down to right bottom corner
    path.lineTo(rightX, bottomY - cornerRadius);
    // Round bottom right
    path.arcToPoint(
      Offset(rightX - cornerRadius, bottomY),
      radius: Radius.circular(cornerRadius),
    );
    // Bottom edge
    path.lineTo(leftX + cornerRadius, bottomY);
    // Round bottom left
    path.arcToPoint(
      Offset(leftX, bottomY - cornerRadius),
      radius: Radius.circular(cornerRadius),
    );
    // Up to left eaves
    path.lineTo(leftX, eavesY);
    // Slope up to near peak left
    path.lineTo(w / 2 - peakRadius, padTop + peakRadius * 0.8);
    // Round the roof peak smoothly
    path.arcToPoint(
      Offset(w / 2 + peakRadius, padTop + peakRadius * 0.8),
      radius: Radius.circular(peakRadius),
    );

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _CleanHomePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}

/// Clean minimalist search icon matching AN01_home.png
class CleanSearchIcon extends StatelessWidget {
  final Color color;
  final double size;
  final double strokeWidth;

  const CleanSearchIcon({
    super.key,
    required this.color,
    this.size = 22,
    this.strokeWidth = 1.9,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CleanSearchPainter(color: color, strokeWidth: strokeWidth),
      ),
    );
  }
}

class _CleanSearchPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  const _CleanSearchPainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final center = Offset(w * 0.40, h * 0.40);
    final radius = w * 0.27;

    // Lens circle
    canvas.drawCircle(center, radius, paint);

    // Diagonal handle
    final start = Offset(
      center.dx + radius * 0.72,
      center.dy + radius * 0.72,
    );
    final end = Offset(w * 0.88, h * 0.88);
    canvas.drawLine(start, end, paint);
  }

  @override
  bool shouldRepaint(covariant _CleanSearchPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}

/// Clean minimalist projects icon (document with lines) matching AN01_home.png
class CleanProjectsIcon extends StatelessWidget {
  final Color color;
  final double size;
  final double strokeWidth;

  const CleanProjectsIcon({
    super.key,
    required this.color,
    this.size = 22,
    this.strokeWidth = 1.9,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CleanProjectsPainter(color: color, strokeWidth: strokeWidth),
      ),
    );
  }
}

class _CleanProjectsPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  const _CleanProjectsPainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Document card outline
    final padX = w * 0.16;
    final padY = h * 0.10;
    final cardRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(padX, padY, w - padX, h - padY),
      Radius.circular(w * 0.10),
    );
    canvas.drawRRect(cardRect, stroke);

    // 4 horizontal lines
    final lineLeft = padX + w * 0.13;
    final lineRight = w - padX - w * 0.13;
    final startY = padY + h * 0.22;
    final stepY = (h - padY * 2 - h * 0.44) / 3;

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 4; i++) {
      final y = startY + i * stepY;
      canvas.drawLine(Offset(lineLeft, y), Offset(lineRight, y), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CleanProjectsPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}

/// Clean minimalist knowledge icon (square frame with inner tile) matching AN01_home.png
class CleanKnowledgeIcon extends StatelessWidget {
  final Color color;
  final double size;
  final double strokeWidth;

  const CleanKnowledgeIcon({
    super.key,
    required this.color,
    this.size = 22,
    this.strokeWidth = 1.9,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CleanKnowledgePainter(color: color, strokeWidth: strokeWidth),
      ),
    );
  }
}

class _CleanKnowledgePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  const _CleanKnowledgePainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Outer rounded square
    final pad = w * 0.12;
    final outerRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(pad, pad, w - pad, h - pad),
      Radius.circular(w * 0.12),
    );

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawRRect(outerRect, stroke);

    // Inner filled rounded square
    final innerPad = w * 0.28;
    final innerRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(innerPad, innerPad, w - innerPad, h - innerPad),
      Radius.circular(w * 0.06),
    );

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawRRect(innerRect, fill);
  }

  @override
  bool shouldRepaint(covariant _CleanKnowledgePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}

/// Clean minimalist settings gear icon matching AN01_home.png
class CleanMoreIcon extends StatelessWidget {
  final Color color;
  final double size;
  final double strokeWidth;

  const CleanMoreIcon({
    super.key,
    required this.color,
    this.size = 22,
    this.strokeWidth = 1.8,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CleanMorePainter(color: color, strokeWidth: strokeWidth),
      ),
    );
  }
}

class _CleanMorePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  const _CleanMorePainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final rOuter = w * 0.42;
    final rInner = w * 0.32;
    final rHole = w * 0.15;
    const teeth = 8;

    final path = Path();
    for (int i = 0; i < teeth; i++) {
      final a0 = (i * 2 * math.pi) / teeth;
      final aToothStart = a0 - 0.18;
      final aToothEnd = a0 + 0.18;
      final aValleyEnd = a0 + (2 * math.pi / teeth) - 0.18;

      final p0 = Offset(center.dx + rInner * math.cos(aToothStart), center.dy + rInner * math.sin(aToothStart));
      final p1 = Offset(center.dx + rOuter * math.cos(aToothStart), center.dy + rOuter * math.sin(aToothStart));
      final p2 = Offset(center.dx + rOuter * math.cos(aToothEnd), center.dy + rOuter * math.sin(aToothEnd));
      final p3 = Offset(center.dx + rInner * math.cos(aToothEnd), center.dy + rInner * math.sin(aToothEnd));
      final p4 = Offset(center.dx + rInner * math.cos(aValleyEnd), center.dy + rInner * math.sin(aValleyEnd));

      if (i == 0) {
        path.moveTo(p0.dx, p0.dy);
      } else {
        path.lineTo(p0.dx, p0.dy);
      }
      path.lineTo(p1.dx, p1.dy);
      path.lineTo(p2.dx, p2.dy);
      path.lineTo(p3.dx, p3.dy);
      path.lineTo(p4.dx, p4.dy);
    }
    path.close();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, paint);
    canvas.drawCircle(center, rHole, paint);
  }

  @override
  bool shouldRepaint(covariant _CleanMorePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}


