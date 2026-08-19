import 'dart:io';

import 'package:app_palestra/objectbox.g.dart';

// `flutter test` gira sull'host, dove la libreria nativa objectbox NON è
// inclusa da objectbox_flutter_libs (che la fornisce solo alle build dell'app).
// Se la lib manca il test si auto-salta invece di fallire; per abilitarlo:
//   * su device/simulatore la lib è già presente, oppure
//   * da CLI: bash <(curl -s https://raw.githubusercontent.com/objectbox/objectbox-dart/main/install.sh)
//     (copia libobjectbox.dylib in ./lib, dove il loader di ObjectBox la cerca).

/// Prova ad aprire uno Store usa-e-getta: se la libreria nativa non è
/// caricabile restituisce il motivo di skip, altrimenti `null`.
String? objectBoxNativeLibSkipReason() {
  Directory? dir;
  try {
    dir = Directory.systemTemp.createTempSync('obx-probe-');
    Store(getObjectBoxModel(), directory: dir.path).close();
    return null;
  } catch (_) {
    return 'Libreria nativa objectbox non disponibile sull\'host di test '
        '(vedi commento in testa al file).';
  } finally {
    try {
      dir?.deleteSync(recursive: true);
    } catch (_) {
      // best effort
    }
  }
}
