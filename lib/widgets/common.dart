import 'dart:math';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_state.dart';
import '../theme.dart';
import '../util/format.dart';

/// Foto de perfil redonda con el color de la persona como aro.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.member, this.size = 48, this.ring = true, this.glow = false});

  final Member? member;
  final double size;
  final bool ring;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final color = hexColor(member?.color);
    final initial = Center(
      child: Text(member?.initial ?? '?', style: TextStyle(color: C.map, fontWeight: FontWeight.w900, fontSize: size * 0.4)),
    );
    final photo = member?.avatarUrl;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: ring ? Border.all(color: C.map, width: size > 44 ? 3 : 2) : null,
        boxShadow: [
          if (ring) BoxShadow(color: color, spreadRadius: 2),
          if (glow) BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 24, spreadRadius: 4),
        ],
      ),
      child: ClipOval(
        child: photo == null
            ? initial
            : Image.network(photo, fit: BoxFit.cover, width: size, height: size, errorBuilder: (_, _, _) => initial),
      ),
    );
  }
}

/// Tarjeta oscura redondeada.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = 24, this.color = C.surface, this.borderColor = C.border});

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius), border: Border.all(color: borderColor)),
        child: child,
      );
}

/// Anillo de batería con el porcentaje en el centro.
class BatteryRing extends StatelessWidget {
  const BatteryRing({super.key, required this.level, required this.charging, this.size = 66});

  final int? level;
  final bool charging;
  final double size;

  @override
  Widget build(BuildContext context) {
    final v = (level ?? 0).clamp(0, 100) / 100;
    final color = level == null ? C.muted : (level! <= 15 && !charging ? C.danger : (level! <= 30 && !charging ? C.amber : C.green));
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(v, color),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (charging) const Icon(Icons.bolt_rounded, size: 14, color: C.green),
              Text(level == null ? '–' : '$level%', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            ]),
            const Text('batería', style: TextStyle(fontSize: 9, color: C.muted, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color);
  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * 0.09;
    final r = rect.deflate(stroke / 2);
    canvas.drawArc(r, 0, 2 * pi, false, Paint()
      ..color = C.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke);
    canvas.drawArc(r, -pi / 2, 2 * pi * value, false, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color;
}

/// Lo que suena en el Spotify de la persona, con su barra de progreso.
class NowPlayingCard extends StatelessWidget {
  const NowPlayingCard({super.key, required this.live});
  final Live live;

  @override
  Widget build(BuildContext context) {
    final duration = live.trackDuration ?? 0;
    final elapsed = live.trackAt == null ? 0 : DateTime.now().difference(live.trackAt!).inMilliseconds;
    final progress = ((live.trackProgress ?? 0) + (live.trackPlaying ? elapsed : 0)).clamp(0, duration == 0 ? 1 : duration);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: live.trackUrl == null ? null : () => launchUrl(Uri.parse(live.trackUrl!), mode: LaunchMode.externalApplication),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: C.spotifyBg, borderRadius: BorderRadius.circular(20), border: Border.all(color: C.spotifyBorder)),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: live.trackImage == null
                  ? Container(width: 56, height: 56, color: C.amber, child: const Icon(Icons.music_note_rounded, color: C.map))
                  : Image.network(live.trackImage!, width: 56, height: 56, fit: BoxFit.cover),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(live.trackName ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Text(live.trackArtist ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: C.muted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 7),
                Row(children: [
                  Text(mmss(progress.toInt()), style: const TextStyle(fontSize: 11, color: C.muted)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: duration == 0 ? 0 : progress / duration,
                        minHeight: 4,
                        backgroundColor: const Color(0xFF2A3A30),
                        color: C.spotify,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(mmss(duration), style: const TextStyle(fontSize: 11, color: C.muted)),
                ]),
              ]),
            ),
            const SizedBox(width: 10),
            const SpotifyMark(size: 26),
          ]),
        ),
      ),
    );
  }
}

class SpotifyMark extends StatelessWidget {
  const SpotifyMark({super.key, this.size = 24});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _SpotifyPainter()));
}

class _SpotifyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawCircle(s.center(Offset.zero), s.width / 2, Paint()..color = C.spotify);
    final p = Paint()
      ..color = C.spotifyBg
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = s.width * 0.075;
    final w = s.width;
    for (final (y, inset, lift) in [(0.38, 0.24, 0.06), (0.52, 0.28, 0.05), (0.65, 0.32, 0.04)]) {
      final path = Path()
        ..moveTo(w * inset, w * y)
        ..quadraticBezierTo(w * 0.5, w * (y - lift - 0.04), w * (1 - inset + 0.04), w * (y + lift * 0.4));
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Iconos para los lugares.
const placeIcons = <String, IconData>{
  'home': Icons.home_rounded,
  'work': Icons.work_rounded,
  'gym': Icons.fitness_center_rounded,
  'school': Icons.school_rounded,
  'heart': Icons.favorite_rounded,
  'food': Icons.restaurant_rounded,
  'cafe': Icons.local_cafe_rounded,
  'shop': Icons.shopping_bag_rounded,
  'health': Icons.local_hospital_rounded,
  'church': Icons.church_rounded,
  'park': Icons.park_rounded,
  'pin': Icons.place_rounded,
};

const placeIconColors = <String, Color>{
  'home': Color(0xFFC9B8F7),
  'work': Color(0xFFF5B97A),
  'gym': C.accent,
  'school': Color(0xFF8CC8F2),
  'heart': C.accent,
  'food': Color(0xFFF5B97A),
  'cafe': Color(0xFFD9A57A),
  'shop': Color(0xFF8CC8F2),
  'health': Color(0xFFFF8A8A),
  'church': Color(0xFFC9B8F7),
  'park': C.green,
  'pin': C.accent,
};

class PlaceIcon extends StatelessWidget {
  const PlaceIcon({super.key, required this.icon, this.size = 42});
  final String icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = placeIconColors[icon] ?? C.accent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(size * 0.33)),
      child: Icon(placeIcons[icon] ?? Icons.place_rounded, color: color, size: size * 0.5),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
        child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: C.muted, letterSpacing: 0.3)),
      );
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Mensaje legible a partir de un error de Supabase u otro.
String friendlyError(Object e) {
  final s = e.toString();
  final m = RegExp(r'message: ([^,]+)').firstMatch(s);
  if (s.contains('Invalid login credentials')) return 'Correo o contraseña incorrectos.';
  if (s.contains('User already registered')) return 'Ya existe una cuenta con ese correo. Inicia sesión.';
  if (s.contains('Password should be')) return 'La contraseña debe tener al menos 6 caracteres.';
  if (s.contains('SocketException') || s.contains('Failed host lookup')) return 'Sin conexión a internet.';
  return m?.group(1) ?? 'Algo salió mal. Intenta de nuevo.';
}
