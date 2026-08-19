import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/errors/ai_exception.dart';
import '../../../data/repositories/settings_repository.dart';
import '../ai_provider.dart';
import '../model_catalog.dart';
import '../plan_merge.dart';
import '../plan_normalizer.dart';
import '../plan_parser.dart';
import '../prompts.dart';

/// Testo della risposta più i metadati che dicono *come* è finita: se il
/// modello ha esaurito il budget di output la scheda è incompleta anche
/// quando il JSON sembra a posto.
class _ChatResult {
  final String content;
  final String? finishReason;

  /// Motivo grezzo del provider a monte (Google usa `MAX_TOKENS`): OpenRouter
  /// non sempre lo normalizza in `finish_reason`.
  final String? nativeFinishReason;
  final Map<String, dynamic>? usage;

  const _ChatResult(
    this.content, {
    this.finishReason,
    this.nativeFinishReason,
    this.usage,
  });

  /// Vero se la generazione si è fermata per esaurimento token.
  bool get isTruncated =>
      finishReason == 'length' ||
      const {'MAX_TOKENS', 'length'}.contains(nativeFinishReason);
}

/// Parametri comuni alle chiamate di un import: risolti una volta sola dalle
/// impostazioni e dal catalogo, poi passati alle due fasi.
class _CallConfig {
  final String apiKey;
  final String modelId;
  final bool useJsonSchema;
  final int maxTokens;
  final bool disableReasoning;

  const _CallConfig({
    required this.apiKey,
    required this.modelId,
    required this.useJsonSchema,
    required this.maxTokens,
    required this.disableReasoning,
  });
}

/// Venti cifre uguali di fila non esistono in una scheda: è il loop del
/// sampler sotto grammatica vincolata.
final _degenerateDigits = RegExp(r'(\d)\1{19,}');

/// Provider OpenRouter (endpoint OpenAI-compatible, §6.1).
///
/// Structured output via `response_format: json_schema` per i modelli che lo
/// dichiarano nel catalogo; per gli altri (o se il modello lo rifiuta a
/// runtime, rischio S-02) la richiesta riparte senza schema e il JSON viene
/// estratto dal testo dal [PlanParser].
///
/// La key viene letta dal [SettingsRepository] a ogni chiamata e finisce solo
/// nell'header `Authorization`: mai nei log, mai nelle eccezioni (RNF-03).
class OpenRouterProvider implements AiProvider {
  OpenRouterProvider({
    required SettingsRepository settings,
    required AiModelCatalog catalog,
    Dio? dio,
    PlanParser parser = const PlanParser(),
  }) : _settings = settings,
       _catalog = catalog,
       _parser = parser,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: 'https://openrouter.ai/api/v1',
               connectTimeout: const Duration(seconds: 15),
               // Le estrazioni vision su schede dense possono essere lente.
               receiveTimeout: const Duration(minutes: 3),
             ),
           );

  final SettingsRepository _settings;
  final AiModelCatalog _catalog;
  final PlanParser _parser;
  final Dio _dio;

  @override
  Future<PlanExtraction> extractPlan({
    List<AiImage> images = const [],
    String? text,
    String? userHint,
  }) async {
    final apiKey = await _requireApiKey();
    final modelId =
        await _settings.getOpenRouterModelId() ?? _catalog.defaultModelId;
    final model = _catalog.byId(modelId);
    final call = _CallConfig(
      apiKey: apiKey,
      modelId: modelId,
      useJsonSchema: model?.supportsJsonSchema ?? false,
      maxTokens: model?.maxOutputTokens ?? AiModelOption.defaultMaxOutputTokens,
      disableReasoning: model?.disableReasoning ?? false,
    );

    if (images.isEmpty) {
      return _structure(call, sourceText: text ?? '', userHint: userHint);
    }

    // Una richiesta per pagina, e due fasi per pagina: prima leggere, poi
    // strutturare. Una sola chiamata su più foto costringe il modello a
    // produrre in un colpo il JSON dell'intera scheda, ed è lì che le schede
    // lunghe si accorciano. Le parti si fondono dopo.
    final pageCount = images.length > 1 ? images.length : null;
    final parts = <PlanExtraction>[];
    for (var i = 0; i < images.length; i++) {
      final transcript = await _transcribe(
        call,
        image: images[i],
        pageIndex: pageCount == null ? null : i + 1,
        pageCount: pageCount,
      );
      // Il testo incollato appartiene alla scheda intera: va unito a una
      // pagina sola, altrimenti ogni pagina ne ripeterebbe i giorni.
      final source = (i == 0 && text != null && text.trim().isNotEmpty)
          ? '$transcript\n\n${text.trim()}'
          : transcript;
      parts.add(
        await _structure(
          call,
          sourceText: source,
          userHint: userHint,
          pageIndex: pageCount == null ? null : i + 1,
          pageCount: pageCount,
        ),
      );
    }

    if (parts.length == 1) return parts.single;
    // La fusione riaccosta blocchi che venivano da pagine diverse (un giorno
    // che prosegue sulla pagina dopo): la forma va rinormalizzata dopo,
    // altrimenti il taglio della pagina resta visibile come blocco a parte.
    return PlanExtraction(
      plan: normalizePlanDto(
        mergePlanDtos([for (final part in parts) part.plan]),
      ),
      usedFallback: parts.any((part) => part.usedFallback),
      rawResponse: [for (final part in parts) part.rawResponse].join('\n\n'),
    );
  }

  /// Fase 1: l'immagine diventa testo, senza structured output.
  ///
  /// Senza la grammatica del `json_schema` addosso il modello si limita a
  /// copiare, che è il compito in cui è affidabile.
  Future<String> _transcribe(
    _CallConfig call, {
    required AiImage image,
    int? pageIndex,
    int? pageCount,
  }) async {
    final result = await _chatCompletion(
      call: call,
      useJsonSchema: false,
      messages: [
        {'role': 'system', 'content': transcriptionSystemPrompt},
        {
          'role': 'user',
          'content': [
            {
              'type': 'text',
              'text': transcriptionUserText(
                pageIndex: pageIndex,
                pageCount: pageCount,
              ),
            },
            {
              'type': 'image_url',
              'image_url': {
                'url':
                    'data:${image.mimeType};base64,${base64Encode(image.bytes)}',
              },
            },
          ],
        },
      ],
    );
    _guardTruncation(result, incomplete: 'La trascrizione della foto');
    return result.content;
  }

  /// Fase 2: dal testo al JSON, pipeline §6.2 con retry e fallback.
  ///
  /// Se la strutturazione fallisce due volte il blocco `freeText` conserva la
  /// trascrizione, non la risposta malformata: è il contenuto che serve
  /// davvero all'utente in editor (RNF-05).
  Future<PlanExtraction> _structure(
    _CallConfig call, {
    required String sourceText,
    String? userHint,
    int? pageIndex,
    int? pageCount,
  }) async {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': extractionSystemPrompt},
      {
        'role': 'user',
        'content': extractionUserText(
          text: sourceText,
          userHint: userHint,
          pageIndex: pageIndex,
          pageCount: pageCount,
        ),
      },
    ];

    // Pipeline §6.2: prima chiamata → parse; errore di parsing → 1 retry con
    // messaggio correttivo; secondo fallimento → fallback freeText (RNF-05).
    final first = await _chatCompletion(
      call: call,
      messages: messages,
      useJsonSchema: call.useJsonSchema,
    );
    _guardResponse(first);
    try {
      return PlanExtraction(
        plan: _parser.parse(first.content),
        usedFallback: false,
        rawResponse: first.content,
      );
    } on PlanParseException catch (firstError) {
      messages
        ..add({'role': 'assistant', 'content': first.content})
        ..add({'role': 'user', 'content': retryUserText(firstError.message)});
      final retry = await _chatCompletion(
        call: call,
        messages: messages,
        useJsonSchema: call.useJsonSchema,
      );
      _guardResponse(retry);
      try {
        return PlanExtraction(
          plan: _parser.parse(retry.content),
          usedFallback: false,
          rawResponse: retry.content,
        );
      } on PlanParseException {
        return PlanExtraction(
          plan: _parser.fallback(sourceText),
          usedFallback: true,
          rawResponse: retry.content,
        );
      }
    }
  }

  void _guardResponse(_ChatResult result) {
    _guardTruncation(result, incomplete: 'La scheda');
    _guardDegenerate(result);
  }

  /// Una risposta troncata non va né riparsata né ritentata: il JSON
  /// incompleto fallisce il parse e il retry correttivo spinge il modello a
  /// rispondere con una scheda *più corta ma valida*, perdendo silenziosamente
  /// giorni ed esercizi. Meglio fermarsi e dirlo.
  void _guardTruncation(_ChatResult result, {required String incomplete}) {
    if (!result.isTruncated) return;
    throw AiResponseException(
      '$incomplete è stata troncata: supera il budget di output del modello. '
      'Riprova con una foto alla volta, o alza "maxOutputTokens" per il '
      'modello selezionato.',
    );
  }

  /// Sotto structured output capita che il modello si incastri ripetendo una
  /// cifra dentro un intero ("sets": 44444…): il JSON resta sintatticamente
  /// plausibile ma il numero non entra in un `int`, il parse fallisce e il
  /// retry ripiega su una scheda più corta. Riconosciuto qui, prima del retry.
  void _guardDegenerate(_ChatResult result) {
    if (!_degenerateDigits.hasMatch(result.content)) return;
    throw const AiResponseException(
      'Il modello ha prodotto una risposta anomala e la scheda risulterebbe '
      'incompleta. Riprova: se capita di nuovo, cambia modello nelle '
      'impostazioni AI.',
    );
  }

  @override
  Future<void> testConnection() async {
    final apiKey = await _requireApiKey();
    try {
      await _dio.get<Object?>('/key', options: _authOptions(apiKey));
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  Future<String> _requireApiKey() async {
    final apiKey = await _settings.getOpenRouterApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw const AiConfigurationException(
        'Nessuna API key OpenRouter configurata.',
      );
    }
    return apiKey;
  }

  Options _authOptions(String apiKey) {
    return Options(
      headers: {
        'Authorization': 'Bearer $apiKey',
        // Identificazione facoltativa dell'app raccomandata da OpenRouter.
        'X-Title': 'Tacca',
      },
    );
  }

  /// Una chiamata `POST /chat/completions`; ritorna testo e `finish_reason`.
  ///
  /// Se il modello rifiuta `response_format` (HTTP 400/404/422), la stessa
  /// richiesta riparte una volta in modalità prompt-based (S-02).
  Future<_ChatResult> _chatCompletion({
    required _CallConfig call,
    required List<Map<String, dynamic>> messages,
    required bool useJsonSchema,
  }) async {
    final body = <String, dynamic>{
      'model': call.modelId,
      'messages': messages,
      // Senza questo il default del provider può essere molto più basso di
      // quanto serve a una scheda intera: la risposta si tronca a metà.
      'max_tokens': call.maxTokens,
      if (call.disableReasoning) 'reasoning': {'effort': 'none'},
      if (useJsonSchema)
        'response_format': {
          'type': 'json_schema',
          'json_schema': {
            'name': 'workout_plan',
            'strict': true,
            'schema': planJsonSchema,
          },
        },
    };

    final Response<Object?> response;
    try {
      response = await _dio.post<Object?>(
        '/chat/completions',
        data: body,
        options: _authOptions(call.apiKey),
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (useJsonSchema && (status == 400 || status == 404 || status == 422)) {
        return _chatCompletion(
          call: call,
          messages: messages,
          useJsonSchema: false,
        );
      }
      throw _mapDioException(e, modelId: call.modelId);
    }

    return _extractContent(response.data, modelId: call.modelId);
  }

  _ChatResult _extractContent(Object? data, {String? modelId}) {
    if (data is! Map<String, dynamic>) {
      throw const AiResponseException(
        'Risposta del provider non riconosciuta.',
      );
    }

    // OpenRouter può rispondere 200 con un errore nel body (es. moderazione).
    final error = data['error'];
    if (error is Map<String, dynamic>) {
      final code = error['code'];
      final message = error['message'] is String
          ? error['message'] as String
          : 'Errore del provider.';
      throw _exceptionForStatus(
        code is int ? code : null,
        message,
        modelId: modelId,
      );
    }

    final choices = data['choices'];
    final choice = choices is List && choices.isNotEmpty
        ? choices.first as Map<String, dynamic>
        : null;
    final message = choice?['message'];
    final content = message is Map<String, dynamic> ? message['content'] : null;
    final finishReason = choice?['finish_reason'];

    // Il contenuto è di norma una stringa; alcuni modelli restituiscono una
    // lista di parti in stile OpenAI.
    final textContent = switch (content) {
      String value => value,
      List parts =>
        parts
            .whereType<Map<String, dynamic>>()
            .map((part) => part['text'])
            .whereType<String>()
            .join('\n'),
      _ => '',
    };
    if (textContent.trim().isEmpty) {
      throw const AiResponseException(
        'Il modello ha restituito una risposta vuota.',
      );
    }
    final result = _ChatResult(
      textContent,
      finishReason: finishReason is String ? finishReason : null,
      nativeFinishReason: choice?['native_finish_reason'] is String
          ? choice!['native_finish_reason'] as String
          : null,
      usage: data['usage'] is Map<String, dynamic>
          ? data['usage'] as Map<String, dynamic>
          : null,
    );
    _logResponse(result);
    return result;
  }

  /// Diagnostica di sviluppo: senza il motivo di terminazione e il conteggio
  /// token una scheda che arriva amputata è indistinguibile da una che il
  /// modello ha semplicemente letto male. Mai la API key, solo la risposta.
  void _logResponse(_ChatResult result) {
    if (!kDebugMode) return;
    debugPrint(
      '[AI] finish_reason=${result.finishReason} '
      'native=${result.nativeFinishReason} usage=${result.usage} '
      'chars=${result.content.length}',
    );
    debugPrint('[AI] risposta grezza:\n${result.content}');
  }

  AiException _mapDioException(DioException e, {String? modelId}) {
    final status = e.response?.statusCode;
    if (status != null) {
      final body = e.response?.data;
      final message = body is Map<String, dynamic>
          ? _errorMessageFromBody(body) ?? 'Errore HTTP $status dal provider.'
          : 'Errore HTTP $status dal provider.';
      return _exceptionForStatus(status, message, modelId: modelId);
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
      'Impossibile raggiungere OpenRouter: controlla la connessione.',
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

  AiException _exceptionForStatus(
    int? status,
    String message, {
    String? modelId,
  }) {
    return switch (status) {
      401 || 403 => AiAuthException(message),
      402 || 429 => AiQuotaException(
        _quotaMessage(status: status!, message: message, modelId: modelId),
      ),
      _ => AiNetworkException(message),
    };
  }

  /// Dice *quale* limite è stato raggiunto, invece di rigirare all'utente il
  /// messaggio inglese del provider.
  ///
  /// I tre casi hanno rimedi diversi e vanno distinti: le richieste gratuite
  /// finite si aspettano (o si sblocca il modello a pagamento), il credito
  /// esaurito si ricarica, il rate limit passa da solo.
  String _quotaMessage({
    required int status,
    required String message,
    String? modelId,
  }) {
    final detail = message.toLowerCase();
    // OpenRouter risponde 429 con "free-models-per-day" (o simili) quando è
    // il piano gratuito a essere finito; il suffisso ":free" del modello dice
    // la stessa cosa quando il testo del provider è generico.
    final isFreeTier =
        detail.contains('free-models') ||
        detail.contains('free model') ||
        detail.contains('free tier') ||
        detail.contains('free-tier') ||
        (modelId != null && modelId.endsWith(':free'));

    if (status == 429 && isFreeTier) {
      return 'Hai esaurito le richieste gratuite di OpenRouter per il modello '
          'selezionato: l\'utilizzo gratis è finito. Riprova più tardi (il '
          'limite gratuito si azzera ogni giorno), aggiungi credito su '
          'openrouter.ai/credits, oppure scegli un altro modello nelle '
          'impostazioni AI.';
    }
    if (status == 429) {
      return 'Troppe richieste a OpenRouter in poco tempo: aspetta qualche '
          'istante e riprova.';
    }
    // 402: OpenRouter non accetta la richiesta perché il saldo non basta —
    // sia a credito zero, sia quando è questa richiesta a costare troppo.
    if (isFreeTier) {
      return 'L\'utilizzo gratis di OpenRouter è finito e il credito è '
          'esaurito. Aggiungi credito su openrouter.ai/credits, oppure '
          'scegli un altro modello nelle impostazioni AI.';
    }
    return 'Credito OpenRouter esaurito: non basta per questa richiesta. '
        'Aggiungi credito su openrouter.ai/credits, oppure passa a un modello '
        'gratuito (":free") nelle impostazioni AI.';
  }
}
