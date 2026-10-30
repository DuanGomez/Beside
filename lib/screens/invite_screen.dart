import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../config.dart';
import '../services/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'scan_screen.dart';

/// Invitar a alguien al círculo: QR, código corto y enlace para compartir.
class InviteScreen extends StatelessWidget {
  const InviteScreen({super.key, this.circle});
  final Circle? circle;

  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    final c = circle ?? (s.circles.isNotEmpty ? s.circles.first : null);
    return Scaffold(
      appBar: AppBar(title: const Text('Conectar')),
      body: c == null
          ? const Center(child: Text('Primero crea un círculo.'))
          : ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 32), children: [
              Text('Que escanee este código o abra tu enlace. Así se ven en el mapa en «${c.name}».',
                  style: const TextStyle(fontSize: 16, color: C.muted, fontWeight: FontWeight.w600, height: 1.45)),
              const SizedBox(height: 18),
              Panel(
                radius: 30,
                padding: const EdgeInsets.all(22),
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
                    child: QrImageView(
                      data: 'beside://join/${c.code}',
                      size: 200,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: C.bg),
                      dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: C.bg),
                      semanticsLabel: 'Código QR de invitación',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('o comparte el código', style: TextStyle(color: C.muted, fontWeight: FontWeight.w700)),
                  SelectableText(c.code, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 4)),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => SharePlus.instance.share(ShareParams(
                          subject: 'Únete a mi círculo en Beside',
                          text: 'Únete a mi círculo «${c.name}» en Beside para vernos en el mapa.\n\n'
                              '1. Instala la app:\n'
                              '• Android: ${Config.apkUrl}\n'
                              '• iPhone: abre ${Config.webUrl} en Safari, toca Compartir y luego «Agregar a inicio».\n\n'
                              '2. Crea tu cuenta y escribe el código ${c.code} (en Android también sirve abrir beside://join/${c.code}).',
                        )),
                        icon: const Icon(Icons.ios_share_rounded, size: 20),
                        label: const Text('Enviar enlace'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final code = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScanScreen()));
                          if (code == null || !context.mounted) return;
                          try {
                            await db.rpc('join_circle', params: {'invite_code': code});
                            await s.refreshCircles();
                            if (context.mounted) toast(context, 'Te uniste al círculo.');
                          } catch (e) {
                            if (context.mounted) toast(context, friendlyError(e));
                          }
                        },
                        icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                        label: const Text('Escanear'),
                      ),
                    ),
                  ]),
                ]),
              ),
              const SizedBox(height: 16),
              const Panel(
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.lock_rounded, color: C.muted, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Solo las personas de tu círculo ven tu ubicación. Puedes dejar de compartir cuando quieras desde Perfil.',
                      style: TextStyle(color: C.muted, fontWeight: FontWeight.w600, height: 1.4),
                    ),
                  ),
                ]),
              ),
            ]),
    );
  }
}
