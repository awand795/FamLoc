import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design system FamLoc — "Modern Family Tech" (ala Dribbble).
/// Sumber kebenaran: skill famloc-design.

class FamColors {
  static const primary = Color(0xFF00897B); // teal/hijau tosca
  static const primaryLight = Color(0xFF00BFA5);
  static const secondary = Color(0xFFFFB300); // amber hangat
  static const surface = Color(0xFFFAFAF8); // off-white
  static const danger = Color(0xFFE53935); // HANYA SOS/unfriend/block
  static const sharingActive = Color(0xFF43A047);
  static const textDark = Color(0xFF263238);
  static const muted = Color(0xFF78909C);

  // Gradient identitas brand
  static const primaryGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [primaryLight, primary],
  );
  static const accentGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF7C4DFF), primaryLight],
  );

  /// Soft shadow tinted warna brand (bukan hitam pekat).
  static List<BoxShadow> softShadow({double opacity = 0.18}) => [
        BoxShadow(
          color: primary.withValues(alpha: opacity),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];
}

class FamRadius {
  static const card = 24.0;
  static const sheet = 28.0;
  static const pill = 999.0;
}

ThemeData buildFamTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: FamColors.primary,
      surface: FamColors.surface,
    ),
    scaffoldBackgroundColor: FamColors.surface,
  );
  return base.copyWith(
    textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
      bodyColor: FamColors.textDark,
      displayColor: FamColors.textDark,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: FamColors.textDark,
      centerTitle: false,
      titleTextStyle: GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: FamColors.textDark,
      ),
    ),
  );
}

/// Tombol utama: pill full-rounded, gradient primary, teks putih semibold.
class GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  const GradientButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: onPressed == null ? 1 : 0.98,
      duration: const Duration(milliseconds: 90),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: FamColors.primaryGradient,
          borderRadius: BorderRadius.circular(FamRadius.pill),
          boxShadow: FamColors.softShadow(),
        ),
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(FamRadius.pill),
            ),
            textStyle: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          onPressed: loading ? null : onPressed,
          child: loading
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4),
                )
              : Text(label),
        ),
      ),
    );
  }
}

/// Avatar fallback: lingkaran gradient berisi inisial nama (putih ExtraBold).
class InitialAvatar extends StatelessWidget {
  final String name;
  final double radius;

  const InitialAvatar({super.key, required this.name, this.radius = 24});

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: FamColors.primaryGradient,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: GoogleFonts.plusJakartaSans(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: radius * 0.85,
        ),
      ),
    );
  }
}

/// Chip status pill kecil dengan background tint 10% warna status.
class StatusChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const StatusChip({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
  });

  static StatusChip moving() =>
      StatusChip(label: 'Bergerak', icon: Icons.directions_car_rounded, color: FamColors.primary);
  static StatusChip stationary() =>
      StatusChip(label: 'Diam', icon: Icons.home_rounded, color: FamColors.muted);
  static StatusChip offline() =>
      StatusChip(label: 'Offline', icon: Icons.pause_circle_rounded, color: FamColors.muted);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(FamRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

/// Indikator baterai kecil; <20% = amber (bukan merah).
class BatteryIndicator extends StatelessWidget {
  final int? level;

  const BatteryIndicator({super.key, this.level});

  @override
  Widget build(BuildContext context) {
    if (level == null) return const SizedBox.shrink();
    final color = level! < 20 ? FamColors.secondary : FamColors.primary;
    final icon = level! >= 90
        ? Icons.battery_full_rounded
        : level! >= 60
            ? Icons.battery_6_bar_rounded
            : level! >= 40
                ? Icons.battery_4_bar_rounded
                : level! >= 20
                    ? Icons.battery_2_bar_rounded
                    : Icons.battery_1_bar_rounded;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 2),
        Text('$level%',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}

/// Avatar dengan ring gradient saat live sharing aktif
class AvatarWithRing extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final bool isLive;
  final double radius;

  const AvatarWithRing({
    super.key,
    required this.name,
    this.avatarUrl,
    this.isLive = false,
    this.radius = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(isLive ? 3 : 0),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isLive ? FamColors.primaryGradient : null,
        boxShadow: isLive ? FamColors.softShadow(opacity: 0.25) : null,
      ),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: avatarUrl != null
            ? CircleAvatar(
                radius: radius,
                backgroundImage: NetworkImage(avatarUrl!),
              )
            : InitialAvatar(name: name, radius: radius),
      ),
    );
  }
}

/// Scanner viewfinder cutout overlay dengan sudut bergaya Dribbble
class ScannerViewfinder extends StatefulWidget {
  final double size;
  const ScannerViewfinder({super.key, this.size = 260});

  @override
  State<ScannerViewfinder> createState() => _ScannerViewfinderState();
}

class _ScannerViewfinderState extends State<ScannerViewfinder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          children: [
            // Border box dengan corner accents
            CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _ViewfinderPainter(
                color: FamColors.primaryLight,
                cornerLength: 32,
                strokeWidth: 4,
                borderRadius: 24,
              ),
            ),
            // Laser garis pemindai yang bergerak naik-turun
            AnimatedBuilder(
              animation: _anim,
              builder: (context, child) {
                return Positioned(
                  top: 20 + (_anim.value * (widget.size - 44)),
                  left: 16,
                  right: 16,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          FamColors.primaryLight.withValues(alpha: 0.9),
                          FamColors.primary,
                          FamColors.primaryLight.withValues(alpha: 0.9),
                          Colors.transparent,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: FamColors.primaryLight.withValues(alpha: 0.6),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  final Color color;
  final double cornerLength;
  final double strokeWidth;
  final double borderRadius;

  _ViewfinderPainter({
    required this.color,
    required this.cornerLength,
    required this.strokeWidth,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;
    final r = borderRadius;
    final len = cornerLength;

    // Top-Left
    final pathTL = Path()
      ..moveTo(0, r + len)
      ..lineTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..lineTo(r + len, 0);
    canvas.drawPath(pathTL, paint);

    // Top-Right
    final pathTR = Path()
      ..moveTo(w - r - len, 0)
      ..lineTo(w - r, 0)
      ..quadraticBezierTo(w, 0, w, r)
      ..lineTo(w, r + len);
    canvas.drawPath(pathTR, paint);

    // Bottom-Left
    final pathBL = Path()
      ..moveTo(0, h - r - len)
      ..lineTo(0, h - r)
      ..quadraticBezierTo(0, h, r, h)
      ..lineTo(r + len, h);
    canvas.drawPath(pathBL, paint);

    // Bottom-Right
    final pathBR = Path()
      ..moveTo(w - r - len, h)
      ..lineTo(w - r, h)
      ..quadraticBezierTo(w, h, w, h - r)
      ..lineTo(w, h - r - len);
    canvas.drawPath(pathBR, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
