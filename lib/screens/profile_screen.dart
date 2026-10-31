import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../main.dart';
import '../util/format.dart';
import '../util/platform.dart';
import '../services/app_state.dart';
import '../services/spotify_api.dart';
import '../services/tracking.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'invite_screen.dart';
import 'onboarding.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _s = AppState.instance;
  bool _sharing = false;
  bool _spotify = false;
  bool _notify = true;
  String? _topic;
  List<(bool, String)> _diag = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_s.demo) {
      setState(() {
        _sharing = true;
        _spotify = true;
        _topic = 'beside-demo';
      });
      return;
    }
    final sharing = await Tracking.isSharing();
    final spotify = await SpotifyApi.isConnected();
    Map<String, dynamic>? settings;
    try {
      settings = await db.from('private_settings').select().eq('user_id', _s.myId!).maybeSingle();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _sharing = sharing;
      _spotify = spotify;
      _notify = settings?['notify_enabled'] as bool? ?? true;
      _topic = settings?['ntfy_topic'] as String?;
    });
    await _diagnose();
  }

  /// Revisa todo lo que necesita el compartir ubicación y lo muestra en Perfil,
  /// para que con una captura se sepa qué falla.
  Future<void> _diagnose() async {
    if (_s.demo || kIsWeb) return;
    final out = <(bool, String)>[];
    try {
      final service = await Geolocator.isLocationServiceEnabled().catchError((_) => false);
      out.add((service, service ? 'GPS encendido' : 'El GPS (ubicación) del celular está apagado'));
      final perm = await Geolocator.checkPermission().catchError((_) => LocationPermission.denied);
      out.add(switch (perm) {
        LocationPermission.always => (true, 'Permiso de ubicación: todo el tiempo'),
        LocationPermission.whileInUse => (false, 'Permiso de ubicación: solo con la app abierta (debe ser «todo el tiempo»)'),
        _ => (false, 'Sin permiso de ubicación'),
      });
      if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
        final precise = await Geolocator.getLocationAccuracy().catchError((_) => LocationAccuracyStatus.precise);
        out.add(precise == LocationAccuracyStatus.precise ? (true, 'Ubicación precisa activada') : (false, 'Ubicación precisa apagada'));
      }
      if (isAndroid) {
        final battery = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
        out.add(battery ? (true, 'Batería sin restricción') : (false, 'Batería con restricción (Android puede cerrar Beside)'));
        if (_sharing) {
          final running = await FlutterForegroundTask.isRunningService;
          out.add(running ? (true, 'Servicio de ubicación encendido') : (false, 'El servicio de ubicación está apagado'));
        }
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      out.add(prefs.getString('device_key') != null ? (true, 'Celular registrado') : (false, 'Este celular no está registrado todavía'));
      final okAt = DateTime.tryParse(prefs.getString('track_ok_at') ?? '');
      final error = prefs.getString('track_error');
      if (okAt != null) {
        final fresh = DateTime.now().difference(okAt) < const Duration(minutes: 5);
        out.add((fresh, 'Último envío de ubicación: ${ago(okAt)}'));
      } else if (_sharing) {
        out.add((false, 'Todavía no ha enviado ninguna ubicación'));
      }
      if (prefs.getBool('track_coarse') == true) out.add((false, 'Solo llegan ubicaciones aproximadas (revisa «Ubicación precisa»)'));
      if (error != null) out.add((false, 'Último error: $error'));
    } catch (e) {
      out.add((false, 'No se pudo revisar: $e'));
    }
    if (mounted) setState(() => _diag = out);
  }

  Future<void> _testNotify() async {
    if (_demoBlock()) return;
    try {
      await db.rpc('send_test_notification');
      if (mounted) toast(context, 'Aviso enviado. Debe llegarte a ntfy en unos segundos.');
    } catch (e) {
      final msg = e.toString().contains('send_test_notification')
          ? 'Falta correr el SQL nuevo (circulos_y_prueba.sql) en Supabase.'
          : friendlyError(e);
      if (mounted) toast(context, msg);
    }
  }

  bool _isOwner(Circle c) => c.createdBy != null && c.createdBy == _s.myId;

  Future<void> _afterCircleChange() async {
    await _s.reload();
    if (!mounted) return;
    if (_s.circles.isEmpty) await Gate.of(context).refresh();
  }

  Future<void> _removeMember(Circle c, Member m) async {
    if (_demoBlock()) return;
    final ok = await _confirm('¿Sacar a ${_s.displayName(m)}?',
        'Ya no verá tu ubicación ni la del círculo «${c.name}», y ustedes tampoco la suya. Puede volver solo si la invitas otra vez.', 'Sacar');
    if (!ok) return;
    try {
      await db.rpc('remove_member', params: {'circle': c.id, 'member': m.id});
      await _afterCircleChange();
      if (mounted) toast(context, '${_s.displayName(m)} salió del círculo.');
    } catch (e) {
      if (mounted) toast(context, e.toString().contains('remove_member') ? 'Falta correr el SQL nuevo en Supabase.' : friendlyError(e));
    }
  }

  Future<void> _deleteCircle(Circle c) async {
    if (_demoBlock()) return;
    final ok = await _confirm('¿Eliminar «${c.name}»?',
        'Se borra el círculo con sus lugares para todos. Nadie del círculo se volverá a ver en el mapa (a menos que estén en otro círculo juntos).', 'Eliminar');
    if (!ok) return;
    try {
      await db.rpc('delete_circle', params: {'circle': c.id});
      await _afterCircleChange();
      if (mounted) toast(context, 'Círculo eliminado.');
    } catch (e) {
      if (mounted) toast(context, e.toString().contains('delete_circle') ? 'Falta correr el SQL nuevo en Supabase.' : friendlyError(e));
    }
  }

  Future<void> _leaveCircle(Circle c) async {
    if (_demoBlock()) return;
    final ok = await _confirm('¿Salir de «${c.name}»?', 'Dejarás de ver a las personas de este círculo y ellas a ti.', 'Salir');
    if (!ok) return;
    try {
      await db.rpc('leave_circle', params: {'circle': c.id});
      await _afterCircleChange();
      if (mounted) toast(context, 'Saliste del círculo.');
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  bool _demoBlock() {
    if (!_s.demo) return false;
    toast(context, 'Esto funciona en la app instalada (es la vista previa).');
    return true;
  }

  Future<void> _toggleSharing(bool on) async {
    if (_demoBlock()) return;
    if (on) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PermissionsScreen(fromSettings: true)));
    } else {
      final ok = await _confirm('¿Dejar de compartir?', 'Tu círculo verá tu última ubicación conocida hasta que vuelvas a activarlo.', 'Dejar de compartir');
      if (ok) await Tracking.stop();
    }
    await _load();
  }

  Future<void> _toggleSpotify() async {
    if (_demoBlock()) return;
    if (!Config.hasSpotify) return toast(context, 'Spotify aún no está configurado en esta versión.');
    try {
      if (_spotify) {
        await SpotifyApi.disconnect();
      } else {
        await SpotifyApi.connect();
        if (mounted) toast(context, 'Spotify conectado. Tu círculo verá lo que escuchas.');
      }
    } catch (e) {
      if (mounted) toast(context, 'No se pudo conectar Spotify.');
    }
    await _load();
  }

  Future<void> _setNotify(bool on) async {
    if (_demoBlock()) return;
    setState(() => _notify = on);
    await db.from('private_settings').update({'notify_enabled': on}).eq('user_id', _s.myId!);
  }

  /// Muestra el canal de avisos con los pasos para suscribirse en ntfy
  /// (en iPhone, ntfy no siempre se abre solo desde otra app).
  Future<void> _openNtfy() async {
    final topic = _topic;
    if (topic == null) {
      toast(context, 'Todavía no cargo tu canal de avisos. Revisa el internet y vuelve a abrir Perfil.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: topic));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: C.surface,
        title: const Text('Activar avisos', style: TextStyle(fontWeight: FontWeight.w900)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Ya copié tu canal. En la app ntfy:', style: TextStyle(color: C.muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          const Text('1. Toca el botón + (Suscribirse a un tema).\n2. Pega tu canal en «Topic».\n3. Toca «Subscribe» y permite las notificaciones.',
              style: TextStyle(height: 1.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.border)),
            child: SelectableText(topic, style: const TextStyle(fontWeight: FontWeight.w800, color: C.accent)),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: topic)).then((_) {
              if (context.mounted) toast(context, 'Canal copiado');
            }),
            child: const Text('Copiar'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              // Android abre ntfy directo en el tema; en iPhone al menos abre la app
              final direct = await launchUrl(Uri.parse('ntfy://${Config.ntfyServer}/$topic'), mode: LaunchMode.externalApplication)
                  .catchError((_) => false);
              if (!direct) await launchUrl(Uri.parse('ntfy://'), mode: LaunchMode.externalApplication).catchError((_) => false);
            },
            child: const Text('Abrir ntfy'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: C.surface,
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
          ],
        ),
      ) ??
      false;

  Future<void> _editNickname(Member m) async {
    final controller = TextEditingController(text: _s.nicknames[m.id] ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: C.surface,
        title: Text('Apodo para ${m.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Ej. Mi amor'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Quitar apodo')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Guardar')),
        ],
      ),
    );
    if (value != null) await _s.setNickname(m.id, value);
  }

  Future<void> _joinAnother() async {
    if (_demoBlock()) return;
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: C.surface,
        title: const Text('Unirme a otro círculo'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'BSD-4K7Q'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Unirme')),
        ],
      ),
    );
    if (code == null || code.trim().isEmpty) return;
    try {
      await db.rpc('join_circle', params: {'invite_code': code});
      await _s.refreshCircles();
      if (mounted) toast(context, 'Te uniste al círculo.');
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _signOut() async {
    if (_demoBlock()) return;
    final ok = await _confirm('¿Cerrar sesión?', 'Dejarás de compartir tu ubicación en este celular.', 'Cerrar sesión');
    if (!ok) return;
    await Tracking.forget();
    await _s.stop();
    await db.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _s,
      builder: (context, _) {
        final me = _s.me;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: ListView(padding: const EdgeInsets.fromLTRB(18, 14, 18, 120), children: [
              Row(children: [
                Avatar(member: me, size: 64, glow: true),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(me?.name ?? 'Tú', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
                    Text(_s.demo ? 'Vista previa' : (db.auth.currentUser?.email ?? ''),
                        style: const TextStyle(color: C.muted, fontWeight: FontWeight.w600)),
                  ]),
                ),
                TextButton(
                  onPressed: () async {
                    if (_demoBlock()) return;
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileSetupScreen(editing: true)));
                  },
                  child: const Text('Editar'),
                ),
              ]),

              const SectionLabel('Tu ubicación'),
              Panel(
                padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                child: Column(children: [
                  _SwitchRow(
                    title: 'Compartir mi ubicación',
                    subtitle: _sharing ? 'Tu círculo te ve en tiempo real, incluso con la app cerrada.' : 'Tu círculo no ve dónde estás.',
                    value: _sharing,
                    onChanged: _toggleSharing,
                  ),
                  const Divider(height: 1),
                  _LinkRow(
                    icon: Icons.verified_user_rounded,
                    title: 'Revisar permisos',
                    subtitle: 'Ubicación siempre, notificaciones y batería',
                    onTap: () {
                      if (_demoBlock()) return;
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PermissionsScreen(fromSettings: true))).then((_) => _load());
                    },
                  ),
                  if (_diag.isNotEmpty) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 12, 8, 8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const Expanded(child: Text('Estado de este celular', style: TextStyle(fontWeight: FontWeight.w900))),
                          TextButton(onPressed: _diagnose, child: const Text('Actualizar')),
                        ]),
                        for (final (ok, text) in _diag)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Icon(ok ? Icons.check_circle_rounded : Icons.error_rounded, size: 18, color: ok ? C.green : C.amber),
                              const SizedBox(width: 8),
                              Expanded(child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                            ]),
                          ),
                      ]),
                    ),
                  ],
                ]),
              ),

              const SectionLabel('Avisos de llegadas'),
              Panel(
                padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                child: Column(children: [
                  _SwitchRow(
                    title: 'Recibir avisos',
                    subtitle: 'Llegadas y salidas de lugares, batería baja, cuando ponen a cargar el celular o se les apaga.',
                    value: _notify,
                    onChanged: _setNotify,
                  ),
                  const Divider(height: 1),
                  _LinkRow(
                    icon: Icons.notifications_active_rounded,
                    title: 'Activar avisos en este celular',
                    subtitle: 'Usa la app gratis «ntfy». Instálala y toca aquí para conectarla.',
                    onTap: _openNtfy,
                  ),
                  const Divider(height: 1),
                  _LinkRow(
                    icon: Icons.campaign_rounded,
                    title: 'Enviarme un aviso de prueba',
                    subtitle: 'Para revisar que los avisos sí te llegan a ntfy.',
                    onTap: _testNotify,
                  ),
                ]),
              ),

              if (!kIsWeb) const SectionLabel('Música'),
              if (!kIsWeb) Panel(
                child: Row(children: [
                  const SpotifyMark(size: 34),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_spotify ? 'Spotify conectado' : 'Conectar Spotify', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                      Text(_spotify ? 'Tu círculo ve la canción que suena.' : 'Muestra a tu círculo qué estás escuchando.',
                          style: const TextStyle(fontSize: 13, color: C.muted, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  TextButton(onPressed: _toggleSpotify, child: Text(_spotify ? 'Quitar' : 'Conectar')),
                ]),
              ),

              for (final c in _s.circles) ...[
                SectionLabel('Círculo «${c.name}»'),
                Panel(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  child: Column(children: [
                    for (final m in _s.everyone.where((m) => c.memberIds.isEmpty || c.memberIds.contains(m.id)))
                      Material(
                        type: MaterialType.transparency,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                          leading: Avatar(member: m, size: 42),
                          title: Text(m.id == _s.myId ? '${m.name} (tú)' : _s.displayName(m), style: const TextStyle(fontWeight: FontWeight.w900)),
                          subtitle: _s.nicknames[m.id] != null ? Text(m.name, style: const TextStyle(color: C.muted)) : null,
                          trailing: m.id == _s.myId
                              ? (_isOwner(c) ? const Text('Creador', style: TextStyle(color: C.muted, fontWeight: FontWeight.w700, fontSize: 12)) : null)
                              : Row(mainAxisSize: MainAxisSize.min, children: [
                                  IconButton(tooltip: 'Ponerle un apodo', icon: const Icon(Icons.edit_rounded, color: C.muted, size: 20), onPressed: () => _editNickname(m)),
                                  if (_isOwner(c))
                                    IconButton(
                                      tooltip: 'Sacar del círculo',
                                      icon: const Icon(Icons.person_remove_rounded, color: C.danger, size: 20),
                                      onPressed: () => _removeMember(c, m),
                                    ),
                                ]),
                        ),
                      ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => InviteScreen(circle: c))),
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: Text('Invitar · ${c.code}'),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _isOwner(c) ? _deleteCircle(c) : _leaveCircle(c),
                      style: TextButton.styleFrom(foregroundColor: C.danger),
                      icon: Icon(_isOwner(c) ? Icons.delete_outline_rounded : Icons.logout_rounded, size: 20),
                      label: Text(_isOwner(c) ? 'Eliminar círculo' : 'Salir del círculo'),
                    ),
                  ]),
                ),
              ],
              const SizedBox(height: 10),
              OutlinedButton.icon(onPressed: _joinAnother, icon: const Icon(Icons.group_add_rounded), label: const Text('Unirme a otro círculo')),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _signOut,
                style: TextButton.styleFrom(foregroundColor: C.danger),
                child: const Text('Cerrar sesión'),
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.title, required this.subtitle, required this.value, required this.onChanged});
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(fontSize: 13, color: C.muted, fontWeight: FontWeight.w600)),
            ]),
          ),
          Switch(value: value, onChanged: onChanged),
        ]),
      );
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            Icon(icon, color: C.accent),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                Text(subtitle, style: const TextStyle(fontSize: 13, color: C.muted, fontWeight: FontWeight.w600)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: C.muted),
            const SizedBox(width: 6),
          ]),
        ),
      );
}
