import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme.dart';

class BackgroundGuideHelper {
  static const MethodChannel _channel = MethodChannel('eu.awanda.famloc/battery');

  static Future<String> getDeviceManufacturer() async {
    if (!Platform.isAndroid) return 'ios';
    try {
      final String? brand = await _channel.invokeMethod<String>('getDeviceManufacturer');
      return brand ?? 'android';
    } catch (_) {
      return 'android';
    }
  }

  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    try {
      final bool? isIgnoring = await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return isIgnoring ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (_) {}
  }

  static Future<bool> openVivoBatterySettings() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool? res = await _channel.invokeMethod<bool>('openVivoBatterySettings');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openAutostartSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool? res = await _channel.invokeMethod<bool>('openAutostartSettings');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openAppDetailsSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool? res = await _channel.invokeMethod<bool>('openAppDetailsSettings');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Cek apakah pengguna sudah pernah menutup dialog panduan
  static Future<bool> hasSeenGuide() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('famloc_seen_bg_guide') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setHasSeenGuide() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('famloc_seen_bg_guide', true);
    } catch (_) {}
  }

  /// Tampilkan BottomSheet Panduan Anti-Mati seperti Co Fit
  static Future<void> showBackgroundGuideSheet(BuildContext context) async {
    final manufacturer = await getDeviceManufacturer();
    final isVivo = manufacturer.contains('vivo') || manufacturer.contains('iqoo');

    if (!context.mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(FamRadius.sheet)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.88,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (sheetContext, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Header
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: FamColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.shield_rounded, color: FamColors.primary, size: 30),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Mode Latar Belakang 24 Jam',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: FamColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Agar FamLoc tetap hidup seperti Co Fit',
                            style: TextStyle(
                              fontSize: 13,
                              color: FamColors.muted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Device info badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isVivo ? const Color(0xFFE8F5E9) : const Color(0xFFF3E5F5),
                    borderRadius: BorderRadius.circular(FamRadius.pill),
                    border: Border.all(
                      color: isVivo ? const Color(0xFF81C784) : const Color(0xFFCE93D8),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isVivo ? Icons.phone_android_rounded : Icons.info_outline_rounded,
                        size: 16,
                        color: isVivo ? const Color(0xFF2E7D32) : const Color(0xFF7B1FA2),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          isVivo
                              ? 'Perangkat Terdeteksi: Vivo (${manufacturer.toUpperCase()})'
                              : 'Perangkat Terdeteksi: ${manufacturer.toUpperCase()}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isVivo ? const Color(0xFF2E7D32) : const Color(0xFF7B1FA2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                const Text(
                  'Mengapa Co Fit bisa terus jalan sedangkan aplikasi lain mati?\n'
                  'HP Vivo memiliki manajemen baterai yang sangat ketat dan mematikan aplikasi setelah 3–5 menit layar mati. Ikuti 4 langkah mudah berikut:',
                  style: TextStyle(fontSize: 12.5, color: FamColors.textDark, height: 1.45),
                ),
                const SizedBox(height: 18),

                // Step 1: Konsumsi Daya Latar Belakang Tinggi (Khusus Vivo)
                _GuideStepCard(
                  stepNumber: '1',
                  isHighlighted: true,
                  title: 'Izinkan Konsumsi Daya Tinggi',
                  subtitle: isVivo
                      ? 'Kunci utama di HP Vivo! Buka Manajemen Daya Latar Belakang -> FamLoc -> pilih "Izinkan konsumsi daya latar belakang tinggi".'
                      : 'Bebaskan FamLoc dari optimasi baterai agar Android tidak mematikan service di Doze Mode.',
                  buttonText: isVivo ? 'Buka Pengaturan Baterai Vivo ↗' : 'Optimasi Baterai ↗',
                  onTapButton: () async {
                    if (isVivo) {
                      await openVivoBatterySettings();
                    } else {
                      await requestIgnoreBatteryOptimizations();
                    }
                  },
                ),
                const SizedBox(height: 12),

                // Step 2: Mulai Otomatis (Autostart)
                _GuideStepCard(
                  stepNumber: '2',
                  title: 'Aktifkan Mulai Otomatis (Autostart)',
                  subtitle:
                      'Memberikan izin agar FamLoc dapat langsung aktif kembali saat HP baru dinyalakan atau setelah memori dibersihkan.',
                  buttonText: 'Buka Pengaturan Autostart ↗',
                  onTapButton: () async {
                    await openAutostartSettings();
                  },
                ),
                const SizedBox(height: 12),

                // Step 3: Izin Lokasi Sepanjang Waktu
                _GuideStepCard(
                  stepNumber: '3',
                  title: 'Izin Lokasi "Sepanjang Waktu"',
                  subtitle:
                      'Pastikan izin lokasi disetel ke "Izinkan sepanjang waktu" (Allow all the time), bukan hanya "Saat aplikasi digunakan".',
                  buttonText: 'Buka Izin di Info Aplikasi ↗',
                  onTapButton: () async {
                    final perm = await Geolocator.checkPermission();
                    if (perm != LocationPermission.always) {
                      await Geolocator.openAppSettings();
                    } else {
                      await openAppDetailsSettings();
                    }
                  },
                ),
                const SizedBox(height: 12),

                // Step 4: Gembok di Recent Apps
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(FamRadius.card),
                    border: Border.all(color: const Color(0xFFFFD54F), width: 1.2),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFB300).withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.lock_rounded, color: Color(0xFFF57F17), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              '4. Kunci Aplikasi di Recent Apps',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFF57F17),
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Buka daftar Recent Apps (tombol kotak atau geser ke atas), lalu tarik jendela FamLoc ke bawah atau ketuk ikon 🔒 Gembok.\n'
                              'Aplikasi yang digembok tidak akan ditutup oleh Vivo saat Anda menekan tombol "Hapus Semua"!',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF5D4037),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Action Button: Selesai
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: FamColors.primary,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(FamRadius.pill),
                    ),
                  ),
                  onPressed: () async {
                    await setHasSeenGuide();
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text(
                    'Saya Sudah Mengatur Semuanya ✅',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _GuideStepCard extends StatelessWidget {
  final String stepNumber;
  final String title;
  final String subtitle;
  final String buttonText;
  final VoidCallback onTapButton;
  final bool isHighlighted;

  const _GuideStepCard({
    required this.stepNumber,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.onTapButton,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isHighlighted ? const Color(0xFFF0FDF4) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(FamRadius.card),
        border: Border.all(
          color: isHighlighted ? const Color(0xFF86EFAC) : Colors.grey.shade200,
          width: isHighlighted ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: isHighlighted ? FamColors.primary : Colors.grey.shade700,
                child: Text(
                  stepNumber,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: isHighlighted ? const Color(0xFF166534) : FamColors.textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: FamColors.muted, height: 1.4),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: isHighlighted ? const Color(0xFF166534) : FamColors.primary,
              side: BorderSide(
                color: isHighlighted ? const Color(0xFF166534) : FamColors.primary,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(FamRadius.pill),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            onPressed: onTapButton,
            icon: const Icon(Icons.settings_outlined, size: 16),
            label: Text(
              buttonText,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
