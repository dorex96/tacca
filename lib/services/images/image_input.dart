import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// Sorgente immagini per l'import AI (RF-03): fotocamera o galleria.
///
/// Interfaccia sottile su `image_picker` così il cubit dell'import resta
/// testabile senza plugin di piattaforma.
abstract interface class ImageInput {
  /// Scatta una foto; `null` se l'utente annulla.
  Future<Uint8List?> takePhoto();

  /// Selezione (anche multipla: fronte/retro, più pagine) dalla galleria.
  Future<List<Uint8List>> pickFromGallery();
}

class PickerImageInput implements ImageInput {
  PickerImageInput({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<Uint8List?> takePhoto() async {
    final file = await _picker.pickImage(source: ImageSource.camera);
    return file?.readAsBytes();
  }

  @override
  Future<List<Uint8List>> pickFromGallery() async {
    final files = await _picker.pickMultiImage();
    return [for (final file in files) await file.readAsBytes()];
  }
}
