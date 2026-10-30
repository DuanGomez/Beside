import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../main.dart';
import '../theme.dart';

/// Escanea el QR de invitación y devuelve el código (BSD-XXXX).
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, title: const Text('Escanear invitación')),
      body: Stack(children: [
        MobileScanner(
          onDetect: (capture) {
            if (_done) return;
            for (final b in capture.barcodes) {
              final code = b.rawValue == null ? null : inviteCodeFrom(b.rawValue!);
              if (code != null) {
                _done = true;
                Navigator.of(context).pop(code);
                return;
              }
            }
          },
        ),
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(border: Border.all(color: C.accent, width: 3), borderRadius: BorderRadius.circular(28)),
          ),
        ),
        const Positioned(
          left: 24,
          right: 24,
          bottom: 48,
          child: Text(
            'Apunta al código QR que aparece en el celular de la otra persona.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      ]),
    );
  }
}
