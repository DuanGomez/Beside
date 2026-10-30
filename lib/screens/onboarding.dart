import 'package:beside/util/platform.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../services/app_state.dart';
import '../services/profile_service.dart';
import '../services/tracking.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'scan_screen.dart';

/// Dos círculos que se acompañan: tú y tu gente.
class BesideLogo extends StatelessWidget {
  const BesideLogo({super.key, this.size = 64});
  final double size;

  @override
  Widget build(BuildContext context) {
    final d = size * 0.62;
    return SizedBox(
      width: size,
      height: size * 0.72,
      child: Stack(children: [
        Positioned(
          left: 0,
          top: 0,
          child: Container(
            width: d,
            height: d,
            decoration: BoxDecoration(shape: BoxShape.circle, color: C.accent, boxShadow: [BoxShadow(color: C.accent.withValues(alpha: 0.5), blurRadius: size * 0.3)]),
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: Container(
            width: d,
            height: d,
            decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFA99BF5).withValues(alpha: 0.92), border: Border.all(color: C.bg, width: size * 0.04)),
            child: Icon(Icons.favorite_rounded, color: C.bg, size: d * 0.42),
          ),
        ),
      ]),
    );
  }
}

class _OnboardingScaffold extends StatelessWidget {
  const _OnboardingScaffold({required this.children, this.bottom, this.onBack});
  final List<Widget> children;
  final Widget? bottom;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          if (onBack != null)
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back_rounded), tooltip: 'Volver'),
            ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(24, 24, 24, 24), children: children),
          ),
          if (bottom != null) Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 20), child: bottom),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Bienvenida y cuenta
// ---------------------------------------------------------------------

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Spacer(flex: 2),
            const BesideLogo(size: 84),
            const SizedBox(height: 28),
            const Text('Beside', style: TextStyle(fontSize: 44, fontWeight: FontWeight.w900, letterSpacing: -1.2)),
            const SizedBox(height: 8),
            const Text(
              'Siempre cerca de los tuyos. Mira dónde están en tiempo real, entérate cuando lleguen a casa y qué canción los acompaña.',
              style: TextStyle(fontSize: 18, color: C.muted, fontWeight: FontWeight.w600, height: 1.4),
            ),
            const Spacer(flex: 3),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthScreen(signUp: true))),
                child: const Text('Crear mi cuenta'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthScreen(signUp: false))),
                child: const Text('Ya tengo cuenta'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.signUp});
  final bool signUp;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late bool _signUp = widget.signUp;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (_signUp && _name.text.trim().isEmpty) return setState(() => _error = 'Escribe tu nombre.');
    if (!email.contains('@')) return setState(() => _error = 'Escribe un correo válido.');
    if (password.length < 6) return setState(() => _error = 'La contraseña debe tener al menos 6 caracteres.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_signUp) {
        final res = await db.auth.signUp(email: email, password: password, data: {'name': _name.text.trim()});
        if (res.session == null) {
          setState(() => _error = 'Revisa tu correo para confirmar la cuenta y luego inicia sesión.');
          return;
        }
      } else {
        await db.auth.signInWithPassword(email: email, password: password);
      }
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _OnboardingScaffold(
      onBack: () => Navigator.of(context).pop(),
      bottom: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: C.bg))
              : Text(_signUp ? 'Crear cuenta' : 'Entrar'),
        ),
      ),
      children: [
        Text(_signUp ? 'Crea tu cuenta' : 'Hola de nuevo', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.8)),
        const SizedBox(height: 6),
        Text(_signUp ? 'Solo toma un minuto.' : 'Entra con tu correo y contraseña.', style: const TextStyle(fontSize: 16, color: C.muted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 28),
        if (_signUp) ...[
          TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Tu nombre')),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(labelText: 'Correo'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: _hide,
          autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'Contraseña',
            suffixIcon: IconButton(
              tooltip: _hide ? 'Mostrar contraseña' : 'Ocultar contraseña',
              icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: C.muted),
              onPressed: () => setState(() => _hide = !_hide),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(_error!, style: const TextStyle(color: C.danger, fontWeight: FontWeight.w700)),
        ],
        const SizedBox(height: 18),
        Center(
          child: TextButton(
            onPressed: () => setState(() {
              _signUp = !_signUp;
              _error = null;
            }),
            child: Text(_signUp ? 'Ya tengo cuenta' : 'Crear una cuenta nueva'),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// Perfil: foto, nombre y color
// ---------------------------------------------------------------------

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key, this.editing = false});

  /// true: se abre desde Perfil y vuelve atrás al guardar.
  final bool editing;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _name = TextEditingController();
  String _color = '#F2789A';
  String? _avatar;
  bool _busy = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = db.auth.currentUser?.id;
    if (uid == null) return;
    final p = await db.from('profiles').select().eq('id', uid).maybeSingle();
    final meta = db.auth.currentUser?.userMetadata?['name'] as String?;
    if (!mounted) return;
    setState(() {
      _name.text = (p?['name'] as String?)?.trim().isNotEmpty == true ? p!['name'] as String : (meta ?? '');
      _color = p?['color'] as String? ?? _color;
      _avatar = p?['avatar_url'] as String?;
    });
  }

  Future<void> _pickPhoto() async {
    setState(() => _uploading = true);
    try {
      final url = await ProfileService.pickAndUploadAvatar();
      if (url != null) setState(() => _avatar = url);
    } catch (e) {
      if (mounted) toast(context, 'No se pudo subir la foto. ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return toast(context, 'Escribe tu nombre.');
    setState(() => _busy = true);
    try {
      await ProfileService.save(name: _name.text, color: _color, avatarUrl: _avatar);
      if (!mounted) return;
      if (widget.editing) {
        Navigator.of(context).pop();
      } else {
        await Gate.of(context).refresh();
      }
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = Member(id: 'yo', name: _name.text.isEmpty ? '?' : _name.text, avatarUrl: _avatar, color: _color);
    return _OnboardingScaffold(
      onBack: widget.editing ? () => Navigator.of(context).pop() : null,
      bottom: SizedBox(
        width: double.infinity,
        child: FilledButton(onPressed: _busy ? null : _save, child: Text(widget.editing ? 'Guardar' : 'Continuar')),
      ),
      children: [
        Text(widget.editing ? 'Tu perfil' : 'Así te verán', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.8)),
        const SizedBox(height: 6),
        const Text('Tu foto y tu color aparecen en el mapa de tu círculo.', style: TextStyle(fontSize: 16, color: C.muted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 30),
        Center(
          child: GestureDetector(
            onTap: _uploading ? null : _pickPhoto,
            child: Stack(clipBehavior: Clip.none, children: [
              Avatar(member: preview, size: 120, glow: true),
              Positioned(
                right: -4,
                bottom: -4,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: C.surface2, shape: BoxShape.circle, border: Border.all(color: C.bg, width: 3)),
                  child: _uploading
                      ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.photo_camera_rounded, size: 20),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Center(child: TextButton(onPressed: _uploading ? null : _pickPhoto, child: Text(_avatar == null ? 'Poner foto' : 'Cambiar foto'))),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Tu nombre'),
        ),
        const SectionLabel('Tu color'),
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (final c in C.people)
            Semantics(
              button: true,
              selected: colorHex(c) == _color,
              label: 'Color ${colorHex(c)}',
              child: GestureDetector(
                onTap: () => setState(() => _color = colorHex(c)),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(color: colorHex(c) == _color ? C.text : Colors.transparent, width: 3),
                  ),
                  child: colorHex(c) == _color ? const Icon(Icons.check_rounded, color: C.bg) : null,
                ),
              ),
            ),
        ]),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// Círculo: crearlo o unirse con un código
// ---------------------------------------------------------------------

class CircleSetupScreen extends StatefulWidget {
  const CircleSetupScreen({super.key});

  @override
  State<CircleSetupScreen> createState() => _CircleSetupScreenState();
}

class _CircleSetupScreenState extends State<CircleSetupScreen> {
  final _code = TextEditingController(text: AppState.instance.pendingInviteCode ?? '');
  final _name = TextEditingController(text: 'Familia');
  late bool _joining = AppState.instance.pendingInviteCode != null;
  bool _busy = false;

  Future<void> _done() async {
    AppState.instance.pendingInviteCode = null;
    if (mounted) await Gate.of(context).refresh();
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      await db.rpc('create_circle', params: {'circle_name': _name.text});
      await _done();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join([String? code]) async {
    final value = inviteCodeFrom(code ?? _code.text);
    if (value == null) return toast(context, 'Ese código no se ve bien. Debe ser como BSD-4K7Q.');
    setState(() => _busy = true);
    try {
      await db.rpc('join_circle', params: {'invite_code': value});
      await _done();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (code != null) {
      _code.text = code;
      await _join(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _OnboardingScaffold(
      bottom: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: _busy ? null : (_joining ? _join : _create),
          child: Text(_joining ? 'Unirme' : 'Crear círculo'),
        ),
      ),
      children: [
        const Text('Tu círculo', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.8)),
        const SizedBox(height: 6),
        const Text('Las personas de tu círculo se ven entre sí en el mapa. Puedes crear uno o unirte al de alguien.',
            style: TextStyle(fontSize: 16, color: C.muted, fontWeight: FontWeight.w600, height: 1.4)),
        const SizedBox(height: 24),
        _Choice(
          selected: !_joining,
          icon: Icons.add_circle_rounded,
          title: 'Crear un círculo',
          subtitle: 'Luego invitas con un código o un QR.',
          onTap: () => setState(() => _joining = false),
        ),
        const SizedBox(height: 10),
        _Choice(
          selected: _joining,
          icon: Icons.qr_code_2_rounded,
          title: 'Tengo una invitación',
          subtitle: 'Escribe el código o escanea el QR.',
          onTap: () => setState(() => _joining = true),
        ),
        const SizedBox(height: 22),
        if (_joining) ...[
          TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 3),
            decoration: const InputDecoration(labelText: 'Código de invitación', hintText: 'BSD-4K7Q'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner_rounded), label: const Text('Escanear QR')),
        ] else
          TextField(controller: _name, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Nombre del círculo')),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.selected, required this.icon, required this.title, required this.subtitle, required this.onTap});
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: C.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: selected ? C.accent : C.border, width: selected ? 1.6 : 1),
          ),
          child: Row(children: [
            Icon(icon, color: selected ? C.accent : C.muted, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                Text(subtitle, style: const TextStyle(fontSize: 13, color: C.muted, fontWeight: FontWeight.w600)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Permisos: lo que el celular necesita para compartir sin fallas
// ---------------------------------------------------------------------

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key, this.fromSettings = false});
  final bool fromSettings;

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> with WidgetsBindingObserver {
  bool _service = false;
  bool _whenInUse = false;
  bool _always = false;
  bool _precise = true;
  bool _notifications = false;
  bool _battery = !isAndroid;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (kIsWeb) {
      // En el navegador solo existe "mientras la app está abierta"
      final p = await Geolocator.checkPermission();
      final granted = p == LocationPermission.whileInUse || p == LocationPermission.always;
      if (mounted) {
        setState(() {
          _service = true;
          _whenInUse = granted;
          _always = granted;
        });
      }
      return;
    }
    final service = await Geolocator.isLocationServiceEnabled();
    final whenInUse = await Permission.locationWhenInUse.isGranted;
    final always = await Permission.locationAlways.isGranted;
    var precise = true;
    if (whenInUse) {
      try {
        precise = await Geolocator.getLocationAccuracy() == LocationAccuracyStatus.precise;
      } catch (_) {}
    }
    final notifications = await Permission.notification.isGranted;
    final battery = isAndroid ? await FlutterForegroundTask.isIgnoringBatteryOptimizations : true;
    if (!mounted) return;
    setState(() {
      _service = service;
      _whenInUse = whenInUse;
      _always = always;
      _precise = precise;
      _notifications = notifications;
      _battery = battery;
    });
  }

  Future<void> _requestLocation() async {
    if (kIsWeb) {
      try {
        await Geolocator.requestPermission();
        await Geolocator.getCurrentPosition(); // Safari pregunta aquí
      } catch (_) {}
      await _check();
      return;
    }
    if (!_service) {
      await Geolocator.openLocationSettings();
      return;
    }
    if (!_whenInUse) {
      final s = await Permission.locationWhenInUse.request();
      if (s.isPermanentlyDenied) await openAppSettings();
      await _check();
      if (!_whenInUse) return;
    }
    if (!_always) {
      final s = await Permission.locationAlways.request();
      if (!s.isGranted) await openAppSettings();
    }
    await _check();
  }

  Future<void> _requestNotifications() async {
    final s = await Permission.notification.request();
    if (s.isPermanentlyDenied) await openAppSettings();
    await _check();
  }

  Future<void> _requestBattery() async {
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    await _check();
  }

  Future<void> _finish({required bool share}) async {
    setState(() => _busy = true);
    try {
      if (share) await Tracking.start();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarded_${db.auth.currentUser!.id}', true);
      if (!mounted) return;
      if (widget.fromSettings) {
        Navigator.of(context).pop();
      } else {
        await Gate.of(context).refresh();
      }
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _service && _always;
    return _OnboardingScaffold(
      onBack: widget.fromSettings ? () => Navigator.of(context).pop() : null,
      bottom: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy || !_whenInUse ? null : () => _finish(share: true),
            child: Text(ready ? 'Empezar a compartir' : 'Compartir solo con la app abierta'),
          ),
        ),
        if (!widget.fromSettings)
          TextButton(onPressed: _busy ? null : () => _finish(share: false), child: const Text('Por ahora solo quiero ver el mapa')),
      ]),
      children: [
        Text(widget.fromSettings ? 'Revisar permisos' : 'Para que nunca falle', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.8)),
        const SizedBox(height: 6),
        Text(
            kIsWeb
                ? 'Tu círculo te verá en el mapa mientras tengas Beside abierta.'
                : 'Beside necesita estos permisos para compartir tu ubicación aunque la app esté cerrada.',
            style: const TextStyle(fontSize: 16, color: C.muted, fontWeight: FontWeight.w600, height: 1.4)),
        const SizedBox(height: 22),
        _PermissionRow(
          done: _service && _whenInUse && _always,
          title: kIsWeb ? 'Ubicación' : (isIOS ? 'Ubicación «Siempre»' : 'Ubicación «Permitir todo el tiempo»'),
          subtitle: kIsWeb
              ? (_whenInUse ? 'Listo.' : 'Toca Permitir y acepta en el aviso de Safari.')
              : !_service
              ? 'El GPS está apagado. Actívalo.'
              : !_whenInUse
                  ? 'Primero permite la ubicación.'
                  : !_always
                      ? (isIOS
                          ? 'En Ajustes › Beside › Ubicación elige «Siempre».'
                          : 'En el permiso de ubicación elige «Permitir todo el tiempo».')
                      : 'Listo: funciona con la app cerrada.',
          action: 'Permitir',
          onTap: _requestLocation,
        ),
        if (_whenInUse && !_precise)
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 10),
            child: Text('Activa «Ubicación precisa» para que los lugares funcionen bien.', style: TextStyle(color: C.amber, fontWeight: FontWeight.w700)),
          ),
        if (isAndroid)
          _PermissionRow(
          done: _notifications,
          title: 'Notificaciones',
          subtitle: isAndroid ? 'Para el aviso fijo que mantiene vivo el servicio.' : 'Para avisarte cuando alguien llegue.',
          action: 'Permitir',
          onTap: _requestNotifications,
        ),
        if (isAndroid)
          _PermissionRow(
            done: _battery,
            title: 'Sin restricción de batería',
            subtitle: 'Evita que Android apague Beside para ahorrar batería.',
            action: 'Permitir',
            onTap: _requestBattery,
          ),
      ],
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({required this.done, required this.title, required this.subtitle, required this.action, required this.onTap});
  final bool done;
  final String title;
  final String subtitle;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        child: Row(children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? C.green : Colors.transparent,
              border: done ? null : Border.all(color: C.muted, width: 2),
            ),
            child: done ? const Icon(Icons.check_rounded, size: 18, color: C.bg) : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(fontSize: 13, color: C.muted, fontWeight: FontWeight.w600)),
            ]),
          ),
          if (!done) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: onTap, child: Text(action)),
          ],
        ]),
      ),
    );
  }
}
