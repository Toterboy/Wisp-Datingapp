import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color, Colors;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

/// Profilbild auswaehlen und interaktiv quadratisch zuschneiden.
///
/// Wird von der Einrichtung ("Dein Profil") und "Profil bearbeiten"
/// genutzt, damit beide identisch funktionieren. Gibt null zurueck, wenn
/// der Nutzer abgebrochen hat.
Future<Uint8List?> pickAndCropAvatar() async {
  final picker = ImagePicker();
  final picked = await picker.pickImage(
    source: ImageSource.gallery,
    maxWidth: 2048,
    maxHeight: 2048,
    imageQuality: 90,
  );
  if (picked == null) return null;

  // Quadratischer Zuschnitt (1:1) - Avatare werden kreisfoermig gezeigt.
  final cropped = await ImageCropper().cropImage(
    sourcePath: picked.path,
    aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
    compressFormat: ImageCompressFormat.jpg,
    compressQuality: 85,
    uiSettings: [
      AndroidUiSettings(
        toolbarTitle: 'Bild zuschneiden',
        toolbarColor: const Color(0xFFFF6B9D),
        toolbarWidgetColor: Colors.white,
        activeControlsWidgetColor: const Color(0xFFFF6B9D),
        lockAspectRatio: true,
        hideBottomControls: false,
      ),
      IOSUiSettings(
        title: 'Bild zuschneiden',
        aspectRatioLockEnabled: true,
        resetAspectRatioEnabled: false,
        aspectRatioPickerButtonHidden: true,
      ),
    ],
  );
  if (cropped == null) return null;

  final bytes = await cropped.readAsBytes();
  if (kDebugMode) {
    debugPrint('[AvatarImage] zugeschnitten: ${bytes.length} Bytes');
  }
  return bytes;
}
