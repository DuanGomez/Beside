import 'package:image_picker/image_picker.dart';

import 'app_state.dart';

class ProfileService {
  /// Elige una foto de la galería, la sube y devuelve su URL pública.
  static Future<String?> pickAndUploadAvatar({ImageSource source = ImageSource.gallery}) async {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 600, maxHeight: 600, imageQuality: 85);
    if (file == null) return null;
    final uid = db.auth.currentUser!.id;
    final path = '$uid/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await db.storage.from('avatars').uploadBinary(path, await file.readAsBytes());
    return db.storage.from('avatars').getPublicUrl(path);
  }

  static Future<void> save({required String name, required String color, String? avatarUrl}) async {
    final uid = db.auth.currentUser!.id;
    await db.from('profiles').upsert({
      'id': uid,
      'name': name.trim(),
      'color': color,
      'avatar_url': ?avatarUrl,
    });
  }
}
