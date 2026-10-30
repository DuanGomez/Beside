import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
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

  Future<void> _openNtfy() async {
    if (_topic == null) return;
    final ok = await launchUrl(Uri.parse('ntfy://${Config.ntfyServer}/$_topic'), mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && mounted) {
      await Clipboard.setData(ClipboardData(text: _topic!));
      if (mounted) toast(context, 'Instala ntfy primero. Copié tu tema para pegarlo en la app.');
    }
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
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PermissionsScreen(fromSettings: true)));
                    },
                  ),
                ]),
              ),

              const SectionLabel('Avisos de llegadas'),
              Panel(
                padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                child: Column(children: [
                  _SwitchRow(
                    title: 'Recibir avisos',
                    subtitle: 'Cuando alguien llegue o salga de un lugar marcado.',
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
                ]),
              ),

              const SectionLabel('Música'),
              Panel(
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
                    for (final m in _s.everyone)
                      Material(
                        type: MaterialType.transparency,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                          leading: Avatar(member: m, size: 42),
                          title: Text(m.id == _s.myId ? '${m.name} (tú)' : _s.displayName(m), style: const TextStyle(fontWeight: FontWeight.w900)),
                          subtitle: _s.nicknames[m.id] != null ? Text(m.name, style: const TextStyle(color: C.muted)) : null,
                          trailing: m.id == _s.myId
                              ? null
                              : IconButton(tooltip: 'Ponerle un apodo', icon: const Icon(Icons.edit_rounded, color: C.muted, size: 20), onPressed: () => _editNickname(m)),
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
