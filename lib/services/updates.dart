import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../theme.dart';
import '../util/platform.dart';

/// Revisa si hay una versión nueva en GitHub Releases y la ofrece (solo Android;
/// la versión web del iPhone se actualiza sola).
class Updates {
  static bool _checked = false;

  static Future<void> checkAndOffer(BuildContext context) async {
    if (_checked || !isAndroid || Config.appVersion.isEmpty) return;
    _checked = true;
    try {
      final res = await http.get(Uri.parse(Config.latestReleaseApi)).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return;
      final latest = (jsonDecode(res.body) as Map<String, dynamic>)['tag_name'] as String? ?? '';
      if (!isNewer(latest, Config.appVersion) || !context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: C.surface,
          title: const Text('Hay una versión nueva', style: TextStyle(fontWeight: FontWeight.w900)),
          content: Text(
            'Beside ${latest.replaceFirst('v', '')} ya está lista. Toca «Actualizar», abre el archivo cuando termine de descargar '
            'y elige «Actualizar». No pierdes nada: tu cuenta y tu círculo siguen igual.',
            style: const TextStyle(color: C.muted, fontWeight: FontWeight.w600, height: 1.4),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Más tarde')),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                launchUrl(Uri.parse(Config.apkUrl), mode: LaunchMode.externalApplication);
              },
              child: const Text('Actualizar'),
            ),
          ],
        ),
      );
    } catch (_) {
      // Sin internet o GitHub no responde: se revisa la próxima vez
    }
  }

  /// "v1.2.0" es más nueva que "v1.1.9".
  static bool isNewer(String latest, String current) {
    List<int> parts(String v) => v.replaceFirst(RegExp('^v'), '').split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final a = parts(latest), b = parts(current);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }
}
