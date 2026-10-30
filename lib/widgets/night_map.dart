import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Mapa nocturno de Beside: teselas gratis y sin clave de Esri (gris oscuro),
/// teñidas con la paleta del diseño. Llegan ya dibujadas, así que cargan
/// rápido y el celular no tiene que pintar cada calle.
class NightMapLayer extends StatelessWidget {
  const NightMapLayer({super.key});

  // Pasa el gris de Esri a los tonos de Beside: fondo #151318, calles azul
  // grisáceo. Como la tesela es gris, basta con el canal rojo.
  static const _tint = ColorFilter.matrix(<double>[
    0.74, 0, 0, 0, -24,
    0.84, 0, 0, 0, -31,
    1.05, 0, 0, 0, -38,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) => ColorFiltered(
        colorFilter: _tint,
        child: TileLayer(
          urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}',
          userAgentPackageName: 'com.duangomez.beside',
          maxNativeZoom: 16, // más cerca, se amplía la tesela del nivel 16
          maxZoom: 20,
          keepBuffer: 4,
          panBuffer: 1,
          tileDisplay: const TileDisplay.fadeIn(duration: Duration(milliseconds: 120)),
        ),
      );
}
