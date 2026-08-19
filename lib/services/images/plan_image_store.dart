import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

/// Salvataggio e compressione delle immagini delle schede (§6.4, RF-03).
///
/// Gli originali vivono a piena risoluzione in
/// `getApplicationDocumentsDirectory()/plan_images/`; le entity salvano solo
/// il path relativo. La versione compressa (lato lungo ~1600 px, JPEG q80)
/// esiste solo in memoria, per ridurre i token vision prima dell'upload.
class PlanImageStore {
  static const _directoryName = 'plan_images';

  /// Salva l'originale su disco e ritorna il path relativo da mettere in
  /// `WorkoutPlan.imagePaths`.
  Future<String> saveOriginal(Uint8List bytes) async {
    final directory = await _imagesDirectory();
    final fileName =
        '${DateTime.now().microsecondsSinceEpoch}_${bytes.length}.jpg';
    await File('${directory.path}/$fileName').writeAsBytes(bytes, flush: true);
    return '$_directoryName/$fileName';
  }

  /// File assoluto di un path relativo salvato in `imagePaths`.
  Future<File> fileForRelativePath(String relativePath) async {
    final documents = await getApplicationDocumentsDirectory();
    return File('${documents.path}/$relativePath');
  }

  /// Comprime per l'upload AI: lato lungo max ~1600 px, JPEG qualità 80.
  Future<Uint8List> compressForUpload(Uint8List bytes) async {
    return FlutterImageCompress.compressWithList(
      bytes,
      minWidth: 1600,
      minHeight: 1600,
      quality: 80,
      format: CompressFormat.jpeg,
    );
  }

  Future<Directory> _imagesDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/$_directoryName');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }
}
