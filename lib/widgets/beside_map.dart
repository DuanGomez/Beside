import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

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

/// Dos personas que están juntas: un solo marcador con las dos fotos y un corazón.
class MapCouple {
  const MapCouple({required this.id, required this.a, required this.b, required this.position, this.selected = false});
  final String id;
  final Member? a;
  final Member? b;
  final LatLng position;
  final bool selected;
}

/// Un círculo en metros (precisión del GPS, radio de un lugar que se edita…).
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
  final double width;
}

ml.LatLng _ml(LatLng p) => ml.LatLng(p.latitude, p.longitude);

/// Control del mapa (mover, animar, encuadrar).
class BesideMapController {
  ml.MapLibreMapController? _c;
  double zoom = 15;
  DateTime _quietUntil = DateTime.fromMillisecondsSinceEpoch(0);

  void _mark(Duration d) => _quietUntil = DateTime.now().add(d);

  void move(LatLng p, [double? z]) {
    _mark(const Duration(milliseconds: 700));
    _c?.moveCamera(ml.CameraUpdate.newLatLngZoom(_ml(p), z ?? zoom));
  }

  void animateTo(LatLng p, [double? z]) {
    _mark(const Duration(milliseconds: 1300));
    _c?.animateCamera(ml.CameraUpdate.newLatLngZoom(_ml(p), z ?? zoom), duration: const Duration(milliseconds: 900));
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
    _mark(const Duration(milliseconds: 700));
    _c?.moveCamera(ml.CameraUpdate.newLatLngBounds(
      ml.LatLngBounds(southwest: ml.LatLng(s, w), northeast: ml.LatLng(n, e)),
      left: padding,
      top: padding,
      right: padding,
      bottom: padding,
    ));
  }
}

/// Mapa nocturno de Beside: MapLibre con datos de OpenStreetMap (OpenFreeMap,
/// gratis y sin clave), con centros comerciales, parques, tiendas… y las fotos
/// de cada persona como marcador. Se dibuja en vectores: nítido en cualquier zoom.
class BesideMap extends StatefulWidget {
  const BesideMap({
    super.key,
    required this.initialCenter,
    this.initialZoom = 15,
    this.controller,
    this.people = const [],
    this.couples = const [],
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
  final List<MapCouple> couples;
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
  static Future<String>? _style;

  late final BesideMapController _ctrl = widget.controller ?? BesideMapController();
  ml.MapLibreMapController? _c;
  bool _styleReady = false;
  bool _syncing = false;
  bool _again = false;
  bool _gestureSent = false;
  bool _overlapSet = false;
  EdgeInsets? _insets;

  // Onda que late alrededor de las parejas
  Timer? _pulseTimer;
  double _pulse = 0;

  final Set<String> _images = {};
  final Map<String, ml.Symbol> _symbols = {};
  final Map<String, String> _symbolSig = {};
  final Map<String, ml.Fill> _fills = {};
  final Map<String, ml.Line> _lines = {};
  final Map<String, String> _shapeSig = {};

  @override
  void initState() {
    super.initState();
    _ctrl.zoom = widget.initialZoom;
    _style ??= rootBundle.loadString('assets/map_style.json');
    _updatePulse();
  }

  @override
  void didUpdateWidget(BesideMap old) {
    super.didUpdateWidget(old);
    _updatePulse();
    _sync();
  }

  @override
  void dispose() {
    _pulseTimer?.cancel();
    _c?.onSymbolTapped.remove(_onSymbolTap);
    super.dispose();
  }

  void _updatePulse() {
    if (widget.couples.isEmpty) {
      _pulseTimer?.cancel();
      _pulseTimer = null;
      return;
    }
    _pulseTimer ??= Timer.periodic(const Duration(milliseconds: 90), (_) {
      _pulse = (_pulse + 0.045) % 1;
      _sync();
    });
  }

  void _onSymbolTap(ml.Symbol s) {
    final id = s.data?['person'] as String?;
    if (id != null) widget.onPersonTap?.call(id);
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: C.map,
      child: FutureBuilder<String>(
        future: _style,
        builder: (context, snap) {
          if (!snap.hasData) return const SizedBox.expand();
          return ml.MapLibreMap(
            styleString: snap.data!,
            initialCameraPosition: ml.CameraPosition(target: _ml(widget.initialCenter), zoom: widget.initialZoom),
            trackCameraPosition: true,
            compassEnabled: false,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            myLocationEnabled: false,
            logoEnabled: false,
            attributionButtonPosition: ml.AttributionButtonPosition.bottomLeft,
            attributionButtonMargins: math.Point(8, widget.padding.bottom + 4),
            foregroundLoadColor: C.map,
            onMapCreated: (c) {
              _c = c;
              _ctrl._c = c;
              c.onSymbolTapped.add(_onSymbolTap);
            },
            onStyleLoadedCallback: () {
              _styleReady = true;
              _overlapSet = false;
              _images.clear();
              _symbols.clear();
              _symbolSig.clear();
              _fills.clear();
              _lines.clear();
              _shapeSig.clear();
              _sync();
              widget.onReady?.call();
            },
            onCameraMove: (pos) {
              _ctrl.zoom = pos.zoom;
              if (!_gestureSent && DateTime.now().isAfter(_ctrl._quietUntil)) {
                _gestureSent = true;
                widget.onUserGesture?.call();
              }
              widget.onCameraMove?.call(LatLng(pos.target.latitude, pos.target.longitude), pos.zoom);
            },
            onCameraIdle: () => _gestureSent = false,
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------------
  // Sincroniza marcadores, círculos y líneas con lo que pide el widget.
  // ------------------------------------------------------------------

  Future<void> _sync() async {
    final c = _c;
    if (c == null || !_styleReady || !mounted) return;
    if (_syncing) {
      _again = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _again = false;
        await _syncOnce(c);
      } while (_again && mounted);
    } catch (_) {
      // El mapa se cerró a mitad de camino; no pasa nada
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncOnce(ml.MapLibreMapController c) async {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // En la web la imagen se pinta a 1:1; en Android e iPhone ya usa la densidad
    final iconSize = kIsWeb ? 1 / dpr : 1.0;

    if (_insets != widget.padding) {
      _insets = widget.padding;
      await c.updateContentInsets(widget.padding);
    }

    // --- Formas: círculos de lugares y extra, recorridos ---
    final fills = <String, ml.FillOptions>{};
    final lines = <String, ml.LineOptions>{};
    final sig = <String, String>{};

    void circle(String id, LatLng center, double radius, Color color, double fill, double stroke) {
      final ring = _ring(center, radius);
      fills[id] = ml.FillOptions(geometry: [ring], fillColor: _hex(color), fillOpacity: fill);
      lines['$id-borde'] = ml.LineOptions(geometry: ring, lineColor: _hex(color), lineWidth: stroke, lineOpacity: color.a, lineJoin: 'round');
      final s = '${center.latitude.toStringAsFixed(6)},${center.longitude.toStringAsFixed(6)},$radius,${color.toARGB32()},$fill,$stroke';
      sig[id] = s;
      sig['$id-borde'] = s;
    }

    for (final p in widget.places) {
      final color = placeIconColors[p.icon] ?? C.accent;
      circle('lugar-${p.id}', LatLng(p.lat, p.lng), p.radius.toDouble(), color.withValues(alpha: 0.7), p.id == widget.highlightPlaceId ? 0.2 : 0.1, 1.6);
    }
    for (final x in widget.circles) {
      circle('c-${x.id}', x.center, x.radius, x.color, x.fill, x.stroke);
    }
    for (final k in widget.couples) {
      // Dos ondas desfasadas que crecen y se desvanecen
      for (final (i, phase) in [(0, 0.0), (1, 0.5)]) {
        final t = (_pulse + phase) % 1;
        final step = (t * 20).round() / 20; // menos actualizaciones, igual de suave
        circle('pareja-${k.id}-$i', k.position, 18 + step * 70, C.accent.withValues(alpha: 0.75 * (1 - step)), 0.18 * (1 - step), 2);
      }
    }
    for (final l in widget.lines) {
      if (l.points.length < 2) continue;
      lines['l-${l.id}'] = ml.LineOptions(
        geometry: [for (final p in l.points) _ml(p)],
        lineColor: _hex(l.color),
        lineOpacity: l.color.a,
        lineWidth: l.width,
        lineJoin: 'round',
      );
      sig['l-${l.id}'] = '${l.points.length},${l.points.first},${l.points.last},${l.color.toARGB32()},${l.width}';
    }

    for (final id in _fills.keys.toList()) {
      if (!fills.containsKey(id)) await c.removeFill(_fills.remove(id)!);
    }
    for (final id in _lines.keys.toList()) {
      if (!lines.containsKey(id)) await c.removeLine(_lines.remove(id)!);
    }
    for (final e in fills.entries) {
      final old = _fills[e.key];
      if (old == null) {
        _fills[e.key] = await c.addFill(e.value);
      } else if (_shapeSig[e.key] != sig[e.key]) {
        await c.updateFill(old, e.value);
      }
      _shapeSig[e.key] = sig[e.key]!;
    }
    for (final e in lines.entries) {
      final old = _lines[e.key];
      if (old == null) {
        _lines[e.key] = await c.addLine(e.value);
      } else if (_shapeSig[e.key] != sig[e.key]) {
        await c.updateLine(old, e.value);
      }
      _shapeSig[e.key] = sig[e.key]!;
    }

    // --- Marcadores ---
    final symbols = <String, (ml.SymbolOptions, Map<String, dynamic>?)>{};
    for (final p in widget.places) {
      final img = await _image(c, 'lugar|${p.icon}|$dpr', () => _drawPlace(p.icon, dpr));
      symbols['lugar-${p.id}'] = (
        ml.SymbolOptions(geometry: ml.LatLng(p.lat, p.lng), iconImage: img, iconSize: iconSize, iconAnchor: 'center', iconOpacity: 0.9, zIndex: 1),
        null,
      );
    }
    if (widget.startDot != null) {
      final img = await _image(c, 'inicio|$dpr', () => _drawDot(dpr));
      symbols['inicio'] = (ml.SymbolOptions(geometry: _ml(widget.startDot!), iconImage: img, iconSize: iconSize, iconAnchor: 'center', zIndex: 2), null);
    }
    for (final person in widget.people) {
      final m = person.member;
      final key = 'persona|${m?.id}|${m?.avatarUrl}|${m?.color}|${m?.initial}|${person.selected}|$dpr';
      final img = await _image(c, key, () => _drawPerson(m, person.selected, dpr));
      symbols['persona-${person.id}'] = (
        ml.SymbolOptions(
          geometry: _ml(person.position),
          iconImage: img,
          iconSize: iconSize,
          iconAnchor: 'center',
          iconOpacity: person.stale ? 0.55 : 1,
          zIndex: person.selected ? 10 : 5,
        ),
        {'person': person.id},
      );
    }

    for (final k in widget.couples) {
      final key = 'pareja|${k.a?.id}|${k.a?.avatarUrl}|${k.b?.id}|${k.b?.avatarUrl}|$dpr';
      final img = await _image(c, key, () => _drawCouple(k.a, k.b, dpr));
      symbols['pareja-${k.id}'] = (
        ml.SymbolOptions(geometry: _ml(k.position), iconImage: img, iconSize: iconSize, iconAnchor: 'center', zIndex: 12),
        {'person': k.id},
      );
    }

    for (final id in _symbols.keys.toList()) {
      if (!symbols.containsKey(id)) {
        await c.removeSymbol(_symbols.remove(id)!);
        _symbolSig.remove(id);
      }
    }
    for (final e in symbols.entries) {
      final (opts, data) = e.value;
      final s = '${opts.geometry?.latitude},${opts.geometry?.longitude},${opts.iconImage},${opts.iconOpacity},${opts.zIndex}';
      final old = _symbols[e.key];
      if (old == null) {
        _symbols[e.key] = await c.addSymbol(opts, data);
      } else if (_symbolSig[e.key] != s) {
        await c.updateSymbol(old, opts);
      }
      _symbolSig[e.key] = s;
    }
    if (!_overlapSet && _symbols.isNotEmpty) {
      // Las fotos nunca se esconden detrás de otros íconos ni nombres
      _overlapSet = true;
      await c.setSymbolIconAllowOverlap(true);
      await c.setSymbolIconIgnorePlacement(true);
    }
  }

  Future<String> _image(ml.MapLibreMapController c, String key, Future<Uint8List> Function() draw) async {
    if (_images.add(key)) {
      final bytes = await _Icons.cached(key, draw);
      await c.addImage(key, bytes);
    }
    return key;
  }

  static String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  /// Círculo de [radius] metros como polígono.
  static List<ml.LatLng> _ring(LatLng center, double radius) {
    const steps = 64;
    final lat = center.latitude * math.pi / 180;
    final dLat = radius / 111320.0;
    final dLng = radius / (111320.0 * math.cos(lat));
    return [
      for (var i = 0; i <= steps; i++)
        ml.LatLng(center.latitude + dLat * math.sin(2 * math.pi * i / steps), center.longitude + dLng * math.cos(2 * math.pi * i / steps)),
    ];
  }

  // ------------------------------------------------------------------
  // Dibujo de los marcadores
  // ------------------------------------------------------------------

  static Future<Uint8List> _png(ui.PictureRecorder rec, double size, double dpr) async {
    final img = await rec.endRecording().toImage((size * dpr).ceil(), (size * dpr).ceil());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  static Future<Uint8List> _drawPerson(Member? m, bool selected, double dpr) async {
    final avatar = selected ? 52.0 : 40.0;
    final box = selected ? 120.0 : 50.0;
    final color = hexColor(m?.color);
    final photo = m?.avatarUrl == null ? null : await _Icons.photo(m!.avatarUrl!);

    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec)..scale(dpr);
    final c = Offset(box / 2, box / 2);
    if (selected) {
      canvas.drawCircle(c, box / 2, Paint()..shader = ui.Gradient.radial(c, box / 2, [color.withValues(alpha: 0.34), color.withValues(alpha: 0)]));
    }
    canvas.drawCircle(
      c + const Offset(0, 1.5),
      avatar / 2 + 3,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(c, avatar / 2 + 2, Paint()..color = color);
    canvas.drawCircle(c, avatar / 2, Paint()..color = C.map);
    final inner = avatar / 2 - 3;
    canvas.drawCircle(c, inner, Paint()..color = color);
    if (photo != null) {
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: inner)));
      final side = math.min(photo.width, photo.height).toDouble();
      final src = Rect.fromLTWH((photo.width - side) / 2, (photo.height - side) / 2, side, side);
      canvas.drawImageRect(photo, src, Rect.fromCircle(center: c, radius: inner), Paint()..filterQuality = FilterQuality.high);
      canvas.restore();
    } else {
      final tp = TextPainter(
        text: TextSpan(text: m?.initial ?? '?', style: TextStyle(color: C.map, fontWeight: FontWeight.w900, fontSize: avatar * 0.4)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
    return _png(rec, box, dpr);
  }

  /// Las dos fotos juntitas con un corazón en medio.
  static Future<Uint8List> _drawCouple(Member? a, Member? b, double dpr) async {
    const w = 120.0, h = 96.0, avatar = 46.0;
    final pa = a?.avatarUrl == null ? null : await _Icons.photo(a!.avatarUrl!);
    final pb = b?.avatarUrl == null ? null : await _Icons.photo(b!.avatarUrl!);
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec)..scale(dpr);
    const mid = Offset(w / 2, h / 2 - 4);
    canvas.drawCircle(mid, 56, Paint()..shader = ui.Gradient.radial(mid, 56, [C.accent.withValues(alpha: 0.4), C.accent.withValues(alpha: 0)]));
    void face(Member? m, ui.Image? photo, Offset c) {
      final color = hexColor(m?.color);
      canvas.drawCircle(c + const Offset(0, 1.5), avatar / 2 + 3, Paint()..color = Colors.black.withValues(alpha: 0.4)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      canvas.drawCircle(c, avatar / 2 + 2, Paint()..color = color);
      canvas.drawCircle(c, avatar / 2, Paint()..color = C.map);
      final inner = avatar / 2 - 3;
      canvas.drawCircle(c, inner, Paint()..color = color);
      if (photo != null) {
        canvas.save();
        canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: inner)));
        final side = math.min(photo.width, photo.height).toDouble();
        canvas.drawImageRect(photo, Rect.fromLTWH((photo.width - side) / 2, (photo.height - side) / 2, side, side),
            Rect.fromCircle(center: c, radius: inner), Paint()..filterQuality = FilterQuality.high);
        canvas.restore();
      } else {
        final tp = TextPainter(
          text: TextSpan(text: m?.initial ?? '?', style: TextStyle(color: C.map, fontWeight: FontWeight.w900, fontSize: avatar * 0.4)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      }
    }

    face(a, pa, mid - const Offset(17, 0));
    face(b, pb, mid + const Offset(17, 0));
    // Corazón en medio, abajo
    const hc = Offset(w / 2, h / 2 + 22);
    canvas.drawCircle(hc, 13, Paint()..color = C.map);
    canvas.drawCircle(hc, 11, Paint()..color = C.accent);
    final heart = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.favorite_rounded.codePoint),
        style: TextStyle(fontFamily: Icons.favorite_rounded.fontFamily, fontSize: 14, color: Colors.white),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    heart.paint(canvas, hc - Offset(heart.width / 2, heart.height / 2 - 0.5));

    final img = await rec.endRecording().toImage((w * dpr).ceil(), (h * dpr).ceil());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  static Future<Uint8List> _drawPlace(String icon, double dpr) async {
    const size = 30.0;
    final color = placeIconColors[icon] ?? C.accent;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec)..scale(dpr);
    final r = RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, size, size), const Radius.circular(size * 0.33));
    canvas.drawRRect(r, Paint()..color = C.map.withValues(alpha: 0.9));
    canvas.drawRRect(r, Paint()..color = color.withValues(alpha: 0.22));
    final data = placeIcons[icon] ?? Icons.place_rounded;
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(data.codePoint),
        style: TextStyle(fontFamily: data.fontFamily, package: data.fontPackage, fontSize: size * 0.56, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((size - tp.width) / 2, (size - tp.height) / 2));
    return _png(rec, size, dpr);
  }

  static Future<Uint8List> _drawDot(double dpr) async {
    const size = 16.0;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec)..scale(dpr);
    const c = Offset(size / 2, size / 2);
    canvas.drawCircle(c, 7, Paint()..color = C.text);
    canvas.drawCircle(c, 4.5, Paint()..color = C.map);
    return _png(rec, size, dpr);
  }
}

/// Imágenes ya dibujadas y fotos descargadas (se comparten entre mapas).
class _Icons {
  static final Map<String, Future<Uint8List>> _pngs = {};
  static final Map<String, Future<ui.Image?>> _photos = {};

  static Future<Uint8List> cached(String key, Future<Uint8List> Function() draw) => _pngs.putIfAbsent(key, draw);

  static Future<ui.Image?> photo(String url) => _photos.putIfAbsent(url, () async {
        try {
          final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
          if (res.statusCode != 200) return null;
          final codec = await ui.instantiateImageCodec(res.bodyBytes, targetWidth: 200);
          return (await codec.getNextFrame()).image;
        } catch (_) {
          return null;
        }
      });
}
