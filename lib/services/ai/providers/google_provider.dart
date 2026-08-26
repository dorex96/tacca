import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/errors/ai_exception.dart';
import '../ai_provider.dart';
import '../ai_selection.dart';
import '../plan_parser.dart';
import '../prompts.dart';
import 'chat_plan_provider.dart';

/// Chiavi che lo schema di Gemini non conosce: `responseSchema` è un
/// sottoinsieme di OpenAPI 3.0, non JSON Schema, e l'API rifiuta con un 400
/// (`Unknown name`) qualunque campo fuori da quel sottoinsieme invece di
/// ignorarlo. Le stesse regole restano scritte nel prompt, e la validazione
/// semantica vera è quella del [PlanParser].
const _unsupportedSchemaKeys = {r'$schema', 'additionalProperties'};

/// Lo schema §5.3 tradotto nel dialetto di Gemini.
final Map<String, dynamic> _planSchema = _toGeminiSchema(planJsonSchema);

/// Traduce lo schema §5.3 in `responseSchema`.
///
/// Due differenze rispetto al JSON Schema usato dagli altri provider: i tipi
/// sono nomi maiuscoli dell'enum `Type` (`STRING`, `INTEGER`, …) e il
/// nullable non è un'unione `["string", "null"]` ma il campo `nullable`.
///
/// La ricorsione segue la *struttura* dello schema, non i nomi delle chiavi:
/// dentro `properties` le chiavi sono nomi di campo, e un campo della scheda
/// si chiama proprio `type` (il tipo di blocco). Trattarlo come la parola
/// chiave omonima lo cancellerebbe dallo schema, lasciando `required` a
/// puntare a una proprietà che non c'è.
Map<String, dynamic> _toGeminiSchema(Map<String, dynamic> node) {
  final out = <String, dynamic>{};
  for (final entry in node.entries) {
    if (_unsupportedSchemaKeys.contains(entry.key)) continue;
    switch (entry.key) {
      case 'type':
        for (final type in switch (entry.value) {
          final String single => [single],
          final List union => union.whereType<String>(),
          _ => const <String>[],
        }) {
          if (type == 'null') {
            out['nullable'] = true;
          } else {
            out['type'] = type.toUpperCase();
          }
        }
      case 'properties':
        final properties = entry.value;
        out['properties'] = <String, dynamic>{
          if (properties is Map<String, dynamic>)
            for (final property in properties.entries)
              if (property.value case final Map<String, dynamic> schema)
                property.key: _toGeminiSchema(schema),
        };
      case 'items':
        if (entry.value case final Map<String, dynamic> items) {
          out['items'] = _toGeminiSchema(items);
        }
      // Il resto del sottoinsieme OpenAPI passa così com'è: `description`,
      // `enum`, `required`, `minItems`.
      default:
        out[entry.key] = entry.value;
    }
  }
  return out;
}

/// Provider Google (Gemini API, §6.1).
///
/// Structured output via `generationConfig.responseSchema` (con
/// `responseMimeType: application/json`) per i modelli che lo dichiarano nel
/// catalogo; per gli altri (o se il modello lo rifiuta a runtime, rischio
/// S-02) la richiesta riparte senza schema e il JSON viene estratto dal testo
/// dal [PlanParser].
///
/// Tutta la pipeline §6.2 (due fasi, retry, fallback) sta in
/// [ChatPlanProvider]: qui resta solo il protocollo.
class GoogleProvider extends ChatPlanProvider {
  GoogleProvider({
    required super.selection,
    Dio? dio,
    super.parser = const PlanParser(),
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
               connectTimeout: const Duration(seconds: 15),
               // Le estrazioni vision su schede dense possono essere lente.
               receiveTimeout: const Duration(minutes: 3),
             ),
           );

  final Dio _dio;

  /// Motivi di terminazione con cui il modello (o un filtro a monte) declina
  /// la richiesta: la risposta arriva con 200 e senza testo, e senza questo
  /// elenco sembrerebbe un guasto.
  static const _refusalReasons = {
    'SAFETY',
    'RECITATION',
    'BLOCKLIST',
    'PROHIBITED_CONTENT',
    'SPII',
    'IMAGE_SAFETY',
  };

  @override
  AiProviderId get id => AiProviderId.google;

  /// Verifica la key sull'elenco dei modelli: è la chiamata autenticata più
  /// economica dell'API (nessun token di generazione).
  @override
  Future<void> testConnection() async {
    final apiKey = (await requireSelection()).requireApiKey();
    try {
      await _dio.get<Object?>(
        '/models',
        queryParameters: {'pageSize': 1},
        options: _authOptions(apiKey),
      );
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  @override
  Future<AiChatResult> sendChat({
    required AiSelection selection,
    required String system,
    required List<AiChatTurn> turns,
    required bool structured,
  }) {
    return _generateContent(
      selection: selection,
      system: system,
      contents: [for (final turn in turns) _content(turn)],
      structured: structured,
    );
  }

  /// Un turno nel formato Gemini: `parts` con l'immagine (base64 inline)
  /// prima del testo, come raccomanda la documentazione quando la domanda
  /// riguarda l'immagine stessa. Il ruolo dell'assistente qui si chiama
  /// `model`.
  Map<String, dynamic> _content(AiChatTurn turn) {
    final image = turn.image;
    return {
      'role': turn.role == AiChatRole.assistant ? 'model' : 'user',
      'parts': [
        if (image != null)
          {
            'inlineData': {
              'mimeType': image.mimeType,
              'data': base64Encode(image.bytes),
            },
          },
        {'text': turn.text},
      ],
    };
  }

  Options _authOptions(String apiKey) =>
      Options(headers: {'x-goog-api-key': apiKey});

  /// Una chiamata `POST /models/{model}:generateContent`; ritorna testo e
  /// `finishReason`.
  ///
  /// Se il modello rifiuta lo structured output (HTTP 400/404/422 che non sia
  /// un problema di key o di quota), la stessa richiesta riparte una volta in
  /// modalità prompt-based (S-02).
  Future<AiChatResult> _generateContent({
    required AiSelection selection,
    required String system,
    required List<Map<String, dynamic>> contents,
    required bool structured,
  }) async {
    final model = selection.model;
    // Su Gemini 3 il pensiero non si spegne, si dosa: `thinkingLevel` è
    // l'equivalente del `reasoning: {effort: none}` di OpenRouter. Trascrivere
    // e strutturare non richiede catena di ragionamento, e i token di
    // pensiero consumano lo stesso budget di `maxOutputTokens`.
    final effort = model.effort;
    final body = <String, dynamic>{
      'systemInstruction': {
        'parts': [
          {'text': system},
        ],
      },
      'contents': contents,
      'generationConfig': {
        'maxOutputTokens': model.maxOutputTokens,
        if (effort != null) 'thinkingConfig': {'thinkingLevel': effort},
        if (structured) ...{
          'responseMimeType': 'application/json',
          'responseSchema': _planSchema,
        },
      },
    };

    final Response<Object?> response;
    try {
      response = await _dio.post<Object?>(
        '/models/${model.id}:generateContent',
        data: body,
        options: _authOptions(selection.requireApiKey()),
      );
    } on DioException catch (e) {
      final mapped = _mapDioException(e);
      final status = e.response?.statusCode;
      // Google risponde 400 anche alla key invalida: solo un rifiuto della
      // *richiesta* giustifica il secondo tentativo, o key e quota darebbero
      // lo stesso errore due volte.
      if (structured &&
          (status == 400 || status == 404 || status == 422) &&
          mapped is! AiAuthException &&
          mapped is! AiQuotaException) {
        return _generateContent(
          selection: selection,
          system: system,
          contents: contents,
          structured: false,
        );
      }
      throw mapped;
    }

    return _extractContent(response.data);
  }

  AiChatResult _extractContent(Object? data) {
    if (data is! Map<String, dynamic>) {
      throw const AiResponseException(
        'Risposta del provider non riconosciuta.',
      );
    }

    // Il filtro sul prompt scarta la richiesta prima di generare: nessun
    // candidato, e il motivo sta qui.
    final promptFeedback = data['promptFeedback'];
    if (promptFeedback is Map<String, dynamic> &&
        promptFeedback['blockReason'] != null) {
      throw _refusal();
    }

    final candidates = data['candidates'];
    final candidate = candidates is List && candidates.isNotEmpty
        ? candidates.first
        : null;
    if (candidate is! Map<String, dynamic>) {
      throw const AiResponseException(
        'Il modello ha restituito una risposta vuota.',
      );
    }

    final finishReason = candidate['finishReason'];
    if (_refusalReasons.contains(finishReason)) throw _refusal();

    final content = candidate['content'];
    final parts = content is Map<String, dynamic> ? content['parts'] : null;
    final textContent = parts is List
        ? parts
              .whereType<Map<String, dynamic>>()
              // I riassunti del pensiero arrivano come parti marcate
              // `thought`: non sono la risposta e non vanno parsati.
              .where((part) => part['thought'] != true)
              .map((part) => part['text'])
              .whereType<String>()
              .join('\n')
        : '';
    if (textContent.trim().isEmpty) {
      // Con `maxOutputTokens` esaurito dal pensiero la risposta arriva vuota
      // e troncata: dirlo come troncamento, non come risposta vuota.
      if (finishReason == 'MAX_TOKENS') {
        return const AiChatResult('', isTruncated: true);
      }
      throw const AiResponseException(
        'Il modello ha restituito una risposta vuota.',
      );
    }

    logResponse(
      content: textContent,
      stopReason: finishReason is String ? finishReason : null,
      usage: data['usageMetadata'],
    );
    return AiChatResult(textContent, isTruncated: finishReason == 'MAX_TOKENS');
  }

  AiResponseException _refusal() => const AiResponseException(
    'Il modello ha rifiutato di elaborare il contenuto inviato. '
    'Riprova con una foto o un testo diverso, oppure cambia modello '
    'nelle impostazioni AI.',
  );

  AiException _mapDioException(DioException e) {
    final status = e.response?.statusCode;
    if (status != null) {
      final body = e.response?.data;
      final message = body is Map<String, dynamic>
          ? _errorMessageFromBody(body) ?? 'Errore HTTP $status dal provider.'
          : 'Errore HTTP $status dal provider.';
      return _exceptionForStatus(status, message);
    }
    // Un timeout in ricezione non è un problema di rete: il modello sta
    // ancora generando (tipicamente perché è finito in un loop). Dirlo, o
    // l'utente cerca il guasto dalla parte sbagliata.
    if (e.type == DioExceptionType.receiveTimeout) {
      return AiNetworkException(
        'Il modello non ha completato la risposta entro il tempo massimo. '
        'Riprova con meno foto per volta, o cambia modello nelle '
        'impostazioni AI.',
        cause: e,
      );
    }
    return AiNetworkException(
      'Impossibile raggiungere Google: controlla la connessione.',
      cause: e,
    );
  }

  String? _errorMessageFromBody(Map<String, dynamic> body) {
    final error = body['error'];
    if (error is Map<String, dynamic> && error['message'] is String) {
      return error['message'] as String;
    }
    return null;
  }

  AiException _exceptionForStatus(int status, String message) {
    // La key invalida non ha uno stato dedicato: arriva come 400 con
    // `API_KEY_INVALID` nel messaggio. Senza riconoscerla finirebbe fra gli
    // errori generici — e farebbe pure ritentare la richiesta senza schema.
    if (status == 400 && _isInvalidKey(message)) {
      return const AiAuthException(
        'API key Google non valida: controllala nelle impostazioni AI.',
      );
    }
    return switch (status) {
      401 || 403 => const AiAuthException(
        'API key Google non valida o senza permessi sulla Gemini API: '
        'controllala nelle impostazioni AI.',
      ),
      429 => const AiQuotaException(
        'Quota Google esaurita o troppe richieste in poco tempo: il piano '
        'gratuito della Gemini API ha un limite giornaliero. Aspetta e '
        'riprova, attiva la fatturazione su aistudio.google.com/apikey, '
        'oppure scegli un altro modello nelle impostazioni AI.',
      ),
      503 => const AiNetworkException(
        'I server Google sono momentaneamente sovraccarichi: riprova '
        'fra poco.',
      ),
      _ => AiNetworkException(message),
    };
  }

  bool _isInvalidKey(String message) {
    final detail = message.toLowerCase();
    return detail.contains('api_key_invalid') ||
        detail.contains('api key not valid') ||
        detail.contains('invalid api key');
  }
}
