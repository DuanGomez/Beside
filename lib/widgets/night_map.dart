import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

/// Mapa nocturno de Beside: teselas vectoriales gratis de OpenFreeMap
/// (datos de OpenStreetMap, sin clave) pintadas con la paleta del diseño.
class NightMapLayer extends StatefulWidget {
  const NightMapLayer({super.key});

  @override
  State<NightMapLayer> createState() => _NightMapLayerState();
}

class _NightMapLayerState extends State<NightMapLayer> {
  static Future<TileProviders>? _providers;
  static final vtr.Theme _theme = vtr.ThemeReader().read(_style);

  @override
  void initState() {
    super.initState();
    _providers ??= _loadProviders();
  }

  /// La URL de las teselas cambia con cada actualización semanal de OpenFreeMap.
  static Future<TileProviders> _loadProviders() async {
    try {
      final res = await http.get(Uri.parse('https://tiles.openfreemap.org/planet')).timeout(const Duration(seconds: 15));
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final url = (json['tiles'] as List).first as String;
      final maxZoom = (json['maxzoom'] as num?)?.toInt() ?? 14;
      return TileProviders({'openmaptiles': NetworkVectorTileProvider(urlTemplate: url, maximumZoom: maxZoom)});
    } catch (_) {
      _providers = null; // reintentar la próxima vez
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TileProviders>(
      future: _providers,
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        return VectorTileLayer(theme: _theme, tileProviders: snap.data!, maximumZoom: 20);
      },
    );
  }
}

const _land = '#141218';
const _park = '#14261B';
const _water = '#0E2033';
const _building = '#1B181F';
const _minor = '#1F2229';
const _mid = '#262A33';
const _major = '#2E3240';
const _label = '#7E7480';

Map<String, dynamic> _line(String id, List<String> classes, String color, List<num> widths, {int minzoom = 0}) => {
      'id': id,
      'type': 'line',
      'source': 'openmaptiles',
      'source-layer': 'transportation',
      'minzoom': minzoom,
      'filter': ['all', ['==', '\$type', 'LineString'], ['in', 'class', ...classes]],
      'layout': {'line-cap': 'round', 'line-join': 'round'},
      'paint': {
        'line-color': color,
        'line-width': [
          'interpolate', ['exponential', 1.5], ['zoom'],
          10, widths[0], 14, widths[1], 18, widths[2],
        ],
      },
    };

final Map<String, dynamic> _style = {
  'version': 8,
  'id': 'beside-night',
  'sources': {
    'openmaptiles': {'type': 'vector', 'url': 'https://tiles.openfreemap.org/planet'},
  },
  'layers': [
    {'id': 'fondo', 'type': 'background', 'paint': {'background-color': _land}},
    {
      'id': 'verde',
      'type': 'fill',
      'source': 'openmaptiles',
      'source-layer': 'landcover',
      'filter': ['in', 'class', 'wood', 'grass', 'farmland'],
      'paint': {'fill-color': _park, 'fill-opacity': 0.7},
    },
    {
      'id': 'parques',
      'type': 'fill',
      'source': 'openmaptiles',
      'source-layer': 'landuse',
      'filter': ['in', 'class', 'park', 'cemetery', 'pitch', 'stadium', 'playground', 'garden'],
      'paint': {'fill-color': _park},
    },
    {'id': 'parque', 'type': 'fill', 'source': 'openmaptiles', 'source-layer': 'park', 'paint': {'fill-color': _park}},
    {'id': 'agua', 'type': 'fill', 'source': 'openmaptiles', 'source-layer': 'water', 'paint': {'fill-color': _water}},
    {
      'id': 'rios',
      'type': 'line',
      'source': 'openmaptiles',
      'source-layer': 'waterway',
      'paint': {'line-color': _water, 'line-width': ['interpolate', ['linear'], ['zoom'], 10, 1, 16, 4]},
    },
    {
      'id': 'edificios',
      'type': 'fill',
      'source': 'openmaptiles',
      'source-layer': 'building',
      'minzoom': 15,
      'paint': {'fill-color': _building},
    },
    _line('senderos', ['path', 'track'], _minor, [0.3, 0.8, 2], minzoom: 15),
    _line('calles', ['minor', 'service'], _minor, [0.4, 2.5, 10], minzoom: 12),
    _line('vias', ['tertiary', 'secondary'], _mid, [0.8, 4, 14]),
    _line('avenidas', ['primary', 'trunk', 'motorway'], _major, [1.2, 5, 18]),
    {
      'id': 'nombres-calles',
      'type': 'symbol',
      'source': 'openmaptiles',
      'source-layer': 'transportation_name',
      'minzoom': 15,
      'layout': {
        'symbol-placement': 'line',
        'text-field': '{name}',
        'text-size': 11,
      },
      'paint': {'text-color': _label, 'text-halo-color': _land, 'text-halo-width': 1.2},
    },
    {
      'id': 'barrios',
      'type': 'symbol',
      'source': 'openmaptiles',
      'source-layer': 'place',
      'filter': ['in', 'class', 'suburb', 'neighbourhood', 'quarter'],
      'minzoom': 12,
      'layout': {'text-field': '{name}', 'text-size': 12, 'text-transform': 'uppercase', 'text-letter-spacing': 0.1},
      'paint': {'text-color': '#5F5761', 'text-halo-color': _land, 'text-halo-width': 1},
    },
    {
      'id': 'ciudades',
      'type': 'symbol',
      'source': 'openmaptiles',
      'source-layer': 'place',
      'filter': ['in', 'class', 'city', 'town'],
      'layout': {'text-field': '{name}', 'text-size': 14},
      'paint': {'text-color': _label, 'text-halo-color': _land, 'text-halo-width': 1.2},
    },
  ],
};
