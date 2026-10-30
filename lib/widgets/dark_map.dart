import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/app_state.dart';
import '../theme.dart';
import 'common.dart';
import 'night_map.dart';

/// Mapa nocturno con la paleta de Beside (ver night_map.dart).
Widget darkTiles() => const NightMapLayer();

Widget mapAttribution() => const Positioned(
      left: 10,
      bottom: 4,
      child: IgnorePointer(
        child: Text('© OpenStreetMap · OpenFreeMap', style: TextStyle(fontSize: 9, color: Color(0x99B9A9B0))),
      ),
    );

/// Zonas de los lugares marcados.
CircleLayer placeCircles(List<Place> places, {String? highlightId}) => CircleLayer(circles: [
      for (final p in places)
        CircleMarker(
          point: LatLng(p.lat, p.lng),
          radius: p.radius.toDouble(),
          useRadiusInMeter: true,
          color: (placeIconColors[p.icon] ?? C.accent).withValues(alpha: p.id == highlightId ? 0.2 : 0.1),
          borderColor: (placeIconColors[p.icon] ?? C.accent).withValues(alpha: 0.7),
          borderStrokeWidth: 1.6,
        ),
    ]);

MarkerLayer placeMarkers(List<Place> places) => MarkerLayer(markers: [
      for (final p in places)
        Marker(
          point: LatLng(p.lat, p.lng),
          width: 30,
          height: 30,
          child: IgnorePointer(child: Opacity(opacity: 0.85, child: PlaceIcon(icon: p.icon, size: 30))),
        ),
    ]);

/// Marcador de una persona: su foto con un halo si es la seleccionada.
class PersonMarker extends StatelessWidget {
  const PersonMarker({super.key, required this.member, required this.selected, required this.stale});
  final Member? member;
  final bool selected;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final color = hexColor(member?.color);
    final size = selected ? 52.0 : 40.0;
    return Opacity(
      opacity: stale ? 0.55 : 1,
      child: Stack(alignment: Alignment.center, children: [
        if (selected)
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [color.withValues(alpha: 0.32), color.withValues(alpha: 0)]),
            ),
          ),
        Avatar(member: member, size: size),
      ]),
    );
  }
}
