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
        Text('$level%',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}
