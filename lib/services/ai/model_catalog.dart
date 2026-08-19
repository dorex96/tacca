import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Un modello OpenRouter offerto all'utente nelle Impostazioni AI.
class AiModelOption {
  /// Identificatore OpenRouter (es. `google/gemini-2.5-flash`).
  final String id;

  /// Nome mostrato in UI.
  final String label;

  /// Il modello accetta immagini (necessario per l'import da foto, RF-03).
  final bool supportsVision;

  /// Il modello supporta `response_format: json_schema`; altrimenti la
  /// richiesta usa il fallback prompt-based (§6.2, rischio S-02).
  final bool supportsJsonSchema;

  /// Tetto di `max_tokens` inviato al provider. Deve stare largo: una scheda
  /// di due giorni supera facilmente i 3.000 token di JSON e, sui modelli con
  /// reasoning, i token di pensiero consumano lo stesso budget. Se il budget
  /// finisce, la risposta arriva troncata e la scheda risulta amputata.
  final int maxOutputTokens;

  /// Chiede a OpenRouter `reasoning: {effort: "none"}` (§6.1): su modelli
  /// reasoning il "pensiero" può mangiarsi quasi tutto `maxOutputTokens`
  /// prima di arrivare al JSON, troncando la scheda anche con un budget
  /// generoso. Il compito qui è trascrizione/estrazione meccanica, non
  /// richiede catena di ragionamento: disattivarla libera il budget per
  /// l'output vero.
  final bool disableReasoning;

  const AiModelOption({
    required this.id,
    required this.label,
    this.supportsVision = false,
    this.supportsJsonSchema = false,
    this.maxOutputTokens = defaultMaxOutputTokens,
    this.disableReasoning = false,
  });

  /// Valore usato quando `models.json` non lo specifica: prudente, accettato
  /// da tutti i modelli vision di uso comune.
  static const defaultMaxOutputTokens = 8192;
}

/// Catalogo dei modelli selezionabili, letto da `assets/ai/models.json`.
///
/// La lista è configurazione, non codice: per cambiare i modelli offerti
/// basta modificare l'asset JSON, nessun intervento sul Dart.
class AiModelCatalog {
  final String defaultModelId;
  final List<AiModelOption> models;

  const AiModelCatalog({required this.defaultModelId, required this.models});

  static const assetPath = 'assets/ai/models.json';

  /// Carica il catalogo dagli asset. Chiamare in `main()` prima di `runApp`,
  /// come per lo Store ObjectBox: da lì in poi tutto è sincrono.
  static Future<AiModelCatalog> load() async {
    return AiModelCatalog.fromJsonString(
      await rootBundle.loadString(assetPath),
    );
  }

  /// Parsing separato dal caricamento asset per poterlo unit-testare.
  factory AiModelCatalog.fromJsonString(String source) {
    final root = jsonDecode(source);
    if (root is! Map<String, dynamic>) {
      throw const FormatException('models.json: atteso un oggetto JSON.');
    }
    final rawModels = root['models'];
    final models = <AiModelOption>[
      if (rawModels is List)
        for (final entry in rawModels.whereType<Map<String, dynamic>>())
          if (entry['id'] is String && (entry['id'] as String).isNotEmpty)
            AiModelOption(
              id: entry['id'] as String,
              label: entry['label'] is String
                  ? entry['label'] as String
                  : entry['id'] as String,
              supportsVision: entry['supportsVision'] == true,
              supportsJsonSchema: entry['supportsJsonSchema'] == true,
              maxOutputTokens: switch (entry['maxOutputTokens']) {
                final int value when value > 0 => value,
                _ => AiModelOption.defaultMaxOutputTokens,
              },
              disableReasoning: entry['disableReasoning'] == true,
            ),
    ];
    if (models.isEmpty) {
      throw const FormatException('models.json: nessun modello valido.');
    }
    final defaultId = root['defaultModelId'];
    return AiModelCatalog(
      defaultModelId:
          defaultId is String && models.any((m) => m.id == defaultId)
          ? defaultId
          : models.first.id,
      models: models,
    );
  }

  AiModelOption? byId(String id) {
    for (final model in models) {
      if (model.id == id) return model;
    }
    return null;
  }
}
