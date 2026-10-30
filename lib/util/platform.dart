import 'package:flutter/foundation.dart';

/// Plataforma sin dart:io, para que la app también corra en el navegador (vista previa).
bool get isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
bool get isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
String get platformName => kIsWeb ? 'web' : (isAndroid ? 'android' : (isIOS ? 'ios' : 'other'));
