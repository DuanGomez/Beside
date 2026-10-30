import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as g;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' show LatLng;

import '../services/app_state.dart';
import '../theme.dart';
import 'common.dart';

/// Una persona en el mapa.
class MapPerson {
  const MapPerson({required this.id, required this.member, required this.position, this.selected = false, this.stale = false});
  final String id;
  final Member? member;
  final LatLng position;
  final bool selected;
  final bool stale;
}

/// Un círculo (precisión del GPS, radio de un lugar que se edita…).
class MapCircle {
  const MapCircle({required this.id, required this.center, required this.radius, required this.color, this.fill = 0.12, this.stroke = 1.6});
  final String id;
  final LatLng center;
  final double radius;
  final Color color;
  final double fill;
  final double stroke;
}

/// Un recorrido.
class MapLine {
  const MapLine({required this.id, required this.points, required this.color, this.width = 4});
  final String id;
  final List<LatLng> points;
  final Color color;
  final int width;
}

/// Control del mapa (mover, animar, encuadrar).
class BesideMapController {
  g.GoogleMapController? _c;
  double zoom = 15;
  DateTime _quietUntil = DateTime.fromMillisecondsSinceEpoch(0);

  void _mark(Duration d) => _quietUntil = DateTime.now().add(d);

  void move(LatLng p, [double? z]) {
    _mark(const Duration(milliseconds: 600));
    _c?.moveCamera(g.CameraUpdate.newLatLngZoom(_g(p), z ?? zoom));
  }

  void animateTo(LatLng p, [double? z]) {
    _mark(const Duration(milliseconds: 1500));
    _c?.animateCamera(g.CameraUpdate.newLatLngZoom(_g(p), z ?? zoom));
  }

  void fit(List<LatLng> points, {double padding = 40}) {
    if (points.isEmpty) return;
    if (points.length == 1) return move(points.first, 16);
    var s = points.first.latitude, n = s, w = points.first.longitude, e = w;
    for (final p in points) {
      s = math.min(s, p.latitude);
      n = math.max(n, p.latitude);
      w = math.min(w, p.longitude);
      e = math.max(e, p.longitude);
    }
    _mark(const Duration(milliseconds: 600));
    _c?.moveCamera(g.CameraUpdate.newLatLngBounds(
      g.LatLngBounds(southwest: g.LatLng(s, w), northeast: g.LatLng(n, e)),
      padding,
    ));
  }
}

g.LatLng _g(LatLng p) => g.LatLng(p.latitude, p.longitude);

/// Mapa de Google en negro, con los sitios de interés (centros comerciales,
/// parques, tiendas…) y las fotos de cada persona como marcador.
class BesideMap extends StatefulWidget {
  const BesideMap({
    super.key,
    required this.initialCenter,
    this.initialZoom = 15,
    this.controller,
    this.people = const [],
    this.places = const [],
    this.highlightPlaceId,
    this.circles = const [],
    this.lines = const [],
    this.startDot,
    this.padding = EdgeInsets.zero,
    this.onCameraMove,
    this.onUserGesture,
    this.onPersonTap,
    this.onReady,
  });

  final LatLng initialCenter;
  final double initialZoom;
  final BesideMapController? controller;
  final List<MapPerson> people;
  final List<Place> places;
  final String? highlightPlaceId;
  final List<MapCircle> circles;
  final List<MapLine> lines;
  final LatLng? startDot;
  final EdgeInsets padding;
  final void Function(LatLng center, double zoom)? onCameraMove;
  final VoidCallback? onUserGesture;
  final ValueChanged<String>? onPersonTap;
  final VoidCallback? onReady;

  @override
  State<BesideMap> createState() => _BesideMapState();
}

class _BesideMapState extends State<BesideMap> {
  late final BesideMapController _ctrl = widget.controller ?? BesideMapController();

  @override
  void initState() {
    super.initState();
    _ctrl.zoom = widget.initialZoom;
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final markers = <g.Marker>{};

    for (final p in widget.places) {
      final icon = _Icons.place(p.icon, dpr, () => mounted ? setState(() {}) : null);
      if (icon == null) continue;
      markers.add(g.Marker(
        markerId: g.MarkerId('place-${p.id}'),
        position: g.LatLng(p.lat, p.lng),
        icon: icon,
        anchor: const Offset(0.5, 0.5),
        alpha: 0.9,
        consumeTapEvents: true,
        zIndexInt: 1,
      ));
    }
    if (widget.startDot != null) {
      final icon = _Icons.dot(dpr, () => mounted ? setState(() {}) : null);
      if (icon != null) {
        markers.add(g.Marker(markerId: const g.MarkerId('start'), position: _g(widget.startDot!), icon: icon, anchor: const Offset(0.5, 0.5), zIndexInt: 2));
      }
    }
    for (final person in widget.people) {
      final icon = _Icons.person(person, dpr, () => mounted ? setState(() {}) : null);
      if (icon == null) continue;
      markers.add(g.Marker(
        markerId: g.MarkerId('person-${person.id}'),
        position: _g(person.position),
        icon: icon,
        anchor: const Offset(0.5, 0.5),
        alpha: person.stale ? 0.55 : 1,
        zIndexInt: person.selected ? 10 : 5,
        consumeTapEvents: true,
        onTap: () => widget.onPersonTap?.call(person.id),
      ));
    }

    final circles = <g.Circle>{
      for (final p in widget.places)
        g.Circle(
          circleId: g.CircleId('place-${p.id}'),
          center: g.LatLng(p.lat, p.lng),
          radius: p.radius.toDouble(),
          fillColor: (placeIconColors[p.icon] ?? C.accent).withValues(alpha: p.id == widget.highlightPlaceId ? 0.2 : 0.1),
          strokeColor: (placeIconColors[p.icon] ?? C.accent).withValues(alpha: 0.7),
          strokeWidth: 2,
        ),
      for (final c in widget.circles)
        g.Circle(
          circleId: g.CircleId(c.id),
          center: _g(c.center),
          radius: c.radius,
          fillColor: c.color.withValues(alpha: c.fill),
          strokeColor: c.color,
          strokeWidth: c.stroke.round(),
          zIndex: 3,
        ),
    };

    final lines = <g.Polyline>{
      for (final l in widget.lines)
        g.Polyline(
          polylineId: g.PolylineId(l.id),
          points: [for (final p in l.points) _g(p)],
          color: l.color,
          width: l.width,
          startCap: g.Cap.roundCap,
          endCap: g.Cap.roundCap,
          jointType: g.JointType.round,
        ),
    };

    return ColoredBox(
      color: C.map,
      child: g.GoogleMap(
        initialCameraPosition: g.CameraPosition(target: _g(widget.initialCenter), zoom: widget.initialZoom),
        style: mapStyle,
        markers: markers,
        circles: circles,
        polylines: lines,
        padding: widget.padding,
        myLocationEnabled: false,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
        mapToolbarEnabled: false,
        compassEnabled: false,
        rotateGesturesEnabled: false,
        tiltGesturesEnabled: false,
        indoorViewEnabled: false,
        onMapCreated: (c) {
          _ctrl._c = c;
          widget.onReady?.call();
        },
        onCameraMoveStarted: () {
          if (DateTime.now().isAfter(_ctrl._quietUntil)) widget.onUserGesture?.call();
        },
        onCameraMove: (pos) {
          _ctrl.zoom = pos.zoom;
          widget.onCameraMove?.call(LatLng(pos.target.latitude, pos.target.longitude), pos.zoom);
        },
      ),
    );
  }
}

/// Dibuja (una sola vez) las imágenes de los marcadores.
class _Icons {
  static final Map<String, g.BitmapDescriptor> _ready = {};
  static final Set<String> _working = {};
  static final Map<String, Future<ui.Image?>> _photos = {};

  static g.BitmapDescriptor? _get(String key, Future<ui.Image> Function() draw, double dpr, VoidCallback onDone) {
    final hit = _ready[key];
    if (hit != null) return hit;
    if (_working.add(key)) {
      draw().then((img) async {
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        if (png == null) return;
        _ready[key] = g.BitmapDescriptor.bytes(png.buffer.asUint8List(), imagePixelRatio: dpr);
        onDone();
      }).whenComplete(() => _working.remove(key));
    }
    return null;
  }

  static g.BitmapDescriptor? person(MapPerson p, double dpr, VoidCallback onDone) {
    final m = p.member;
    final key = 'p|${m?.id}|${m?.avatarUrl}|${m?.color}|${m?.initial}|${p.selected}|$dpr';
    return _get(key, () => _drawPerson(m, p.selected, dpr), dpr, onDone);
  }

  static g.BitmapDescriptor? place(String icon, double dpr, VoidCallback onDone) =>
      _get('pl|$icon|$dpr', () => _drawPlace(icon, dpr), dpr, onDone);

  static g.BitmapDescriptor? dot(double dpr, VoidCallback onDone) => _get('dot|$dpr', () => _drawDot(dpr), dpr, onDone);

  static Future<ui.Image?> _photo(String url) => _photos.putIfAbsent(url, () async {
        try {
          final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
          if (res.statusCode != 200) return null;
          final codec = await ui.instantiateImageCodec(res.bodyBytes, targetWidth: 200);
          return (await codec.getNextFrame()).image;
        } catch (_) {
          return null;
        }
      });

  static Future<ui.Image> _drawPerson(Member? m, bool selected, double dpr) async {
    final avatar = selected ? 52.0 : 40.0;
    final box = selected ? 120.0 : 48.0;
    final color = hexColor(m?.color);
    final photo = m?.avatarUrl == null ? null : await _photo(m!.avatarUrl!);

    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec)..scale(dpr);
    final c = Offset(box / 2, box / 2);
    if (selected) {
      canvas.drawCircle(
        c,
        box / 2,
        Paint()..shader = ui.Gradient.radial(c, box / 2, [color.withValues(alpha: 0.34), color.withValues(alpha: 0)]),
      );
    }
    canvas.drawCircle(c + const Offset(0, 1.5), avatar / 2 + 3, Paint()..color = Colors.black.withValues(alpha: 0.35)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    canvas.drawCircle(c, avatar / 2 + 2, Paint()..color = color);
    canvas.drawCircle(c, avatar / 2, Paint()..color = C.map);
    final inner = avatar / 2 - 3;
    canvas.drawCircle(c, inner, Paint()..color = color);
    if (photo != null) {
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: inner)));
      final src = photo.width < photo.height
          ? Rect.fromLTWH(0, (photo.height - photo.width) / 2, photo.width.toDouble(), photo.width.toDouble())
          : Rect.fromLTWH((photo.width - photo.height) / 2, 0, photo.height.toDouble(), photo.height.toDouble());
      canvas.drawImageRect(photo, src, Rect.fromCircle(center: c, radius: inner), Paint()..filterQuality = FilterQuality.high);
      canvas.restore();
    } else {
      final tp = TextPainter(
        text: TextSpan(text: m?.initial ?? '?', style: TextStyle(color: C.map, fontWeight: FontWeight.w900, fontSize: avatar * 0.4, fontFamily: 'Nunito')),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
    return rec.endRecording().toImage((box * dpr).ceil(), (box * dpr).ceil());
  }

  static Future<ui.Image> _drawPlace(String icon, double dpr) async {
    const size = 30.0;
    final color = placeIconColors[icon] ?? C.accent;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec)..scale(dpr);
    final r = RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, size, size), const Radius.circular(size * 0.33));
    canvas.drawRRect(r, Paint()..color = C.map.withValues(alpha: 0.85));
    canvas.drawRRect(r, Paint()..color = color.withValues(alpha: 0.2));
    final data = placeIcons[icon] ?? Icons.place_rounded;
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(data.codePoint),
        style: TextStyle(fontFamily: data.fontFamily, package: data.fontPackage, fontSize: size * 0.56, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((size - tp.width) / 2, (size - tp.height) / 2));
    return rec.endRecording().toImage((size * dpr).ceil(), (size * dpr).ceil());
  }

  static Future<ui.Image> _drawDot(double dpr) async {
    const size = 16.0;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec)..scale(dpr);
    const c = Offset(size / 2, size / 2);
    canvas.drawCircle(c, 7, Paint()..color = C.text);
    canvas.drawCircle(c, 4.5, Paint()..color = C.map);
    return rec.endRecording().toImage((size * dpr).ceil(), (size * dpr).ceil());
  }
}

/// Estilo negro de Beside: sitios de interés visibles (con sus íconos de
/// colores, como en Life360), calles legibles y parques en verde oscuro.
const mapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#17151c"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#968c9c"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#17151c"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#2c2733"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#d9cbe0"}]},
  {"featureType":"administrative.neighborhood","elementType":"labels.text.fill","stylers":[{"color":"#7d7385"}]},
  {"featureType":"landscape.man_made","elementType":"geometry","stylers":[{"color":"#1c1a22"}]},
  {"featureType":"landscape.natural","elementType":"geometry","stylers":[{"color":"#191820"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#201d27"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#c3b5c9"}]},
  {"featureType":"poi","elementType":"labels.text.stroke","stylers":[{"color":"#141218"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#15291e"}]},
  {"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#72c495"}]},
  {"featureType":"poi.sports_complex","elementType":"geometry","stylers":[{"color":"#173026"}]},
  {"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#2b2d37"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#1b1a21"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#a49cad"}]},
  {"featureType":"road","elementType":"labels.text.stroke","stylers":[{"color":"#17151c"}]},
  {"featureType":"road.arterial","elementType":"geometry.fill","stylers":[{"color":"#353845"}]},
  {"featureType":"road.highway","elementType":"geometry.fill","stylers":[{"color":"#4a4558"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#2a2631"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#e3d4e6"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#26222d"}]},
  {"featureType":"transit.station","elementType":"labels.text.fill","stylers":[{"color":"#c9b8f7"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0f2236"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#56779a"}]}
]
''';
