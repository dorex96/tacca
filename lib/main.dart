import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';
import 'app/di.dart';
import 'core/constants.dart';
import 'data/db/object_box.dart';
import 'services/ai/model_catalog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Le date localizzate (storico, "ultima volta") passano da `DateFormat`, che
  // richiede i simboli della locale caricati prima del primo uso.
  await initializeDateFormatting(
    AppConstants.supportedLocales.first.toString(),
  );

  // Lo Store ObjectBox viene aperto una sola volta, prima di runApp, e
  // iniettato nell'albero tramite la composition root (app/di.dart).
  final objectBox = await ObjectBox.open();

  // I modelli AI selezionabili sono configurazione, non codice: vivono in
  // assets/ai/models.json e vengono caricati una volta all'avvio.
  final aiModelCatalog = await AiModelCatalog.load();

  runApp(
    AppProviders(
      objectBox: objectBox,
      aiModelCatalog: aiModelCatalog,
      child: const App(),
    ),
  );
}
