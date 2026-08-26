import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/errors/ai_exception.dart';
import '../ai_provider.dart';
import '../ai_selection.dart';
import '../plan_parser.dart';
import '../prompts.dart';
import 'chat_plan_provider.dart';

/// Provider OpenRouter (endpoint OpenAI-compatible, §6.1).
///
/// Structured output via `response_format: json_schema` per i modelli che lo
/// dichiarano nel catalogo; per gli altri (o se il modello lo rifiuta a
/// runtime, rischio S-02) la richiesta riparte senza schema e il JSON viene
/// estratto dal testo dal [PlanParser].
///
/// Tutta la pipeline §6.2 (due fasi, retry, fallback) sta in
/// [ChatPlanProvider]: qui resta solo il protocollo.
class OpenRouterProvider extends ChatPlanProvider {
  OpenRouterProvider({
    required super.selection,
    Dio? dio,
    super.parser = const PlanParser(),
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: 'https://openrouter.ai/api/v1',
               connectTimeout: const Duration(seconds: 15),
               // Le estrazioni vision su schede dense possono essere lente.
               receiveTimeout: const Duration(minutes: 3),
             ),
           );

  final Dio _dio;

  @override
  AiProviderId get id => AiProviderId.openRouter;

  @override
  Future<void> testConnection() async {
    final apiKey = (await requireSelection()).requireApiKey();
    try {
      await _dio.get<Object?>('/key', options: _authOptions(apiKey));
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
    return _chatCompletion(
      selection: selection,
      messages: [
        {'role': 'system', 'content': system},
        for (final turn in turns) _message(turn),
      ],
      useJsonSchema: structured,
    );
  }

  /// Un turno nel formato OpenAI: testo semplice, o lista di parti quando
  /// c'è un'immagine (che viaggia come data URL).
  Map<String, dynamic> _message(AiChatTurn turn) {
    final role = turn.role == AiChatRole.assistant ? 'assistant' : 'user';
    final image = turn.image;
    if (image == null) return {'role': role, 'content': turn.text};
    return {
      'role': role,
      'content': [
        {'type': 'text', 'text': turn.text},
        {
          'type': 'image_url',
          'image_url': {
            'url': 'data:${image.mimeType};base64,${base64Encode(image.bytes)}',
          },
        },
      ],
    };
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
  Future<AiChatResult> _chatCompletion({
    required AiSelection selection,
    required List<Map<String, dynamic>> messages,
    required bool useJsonSchema,
  }) async {
    final model = selection.model;
    final body = <String, dynamic>{
      'model': model.id,
      'messages': messages,
      // Senza questo il default del provider può essere molto più basso di
      // quanto serve a una scheda intera: la risposta si tronca a metà.
      'max_tokens': model.maxOutputTokens,
      if (model.disableReasoning) 'reasoning': {'effort': 'none'},
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
        options: _authOptions(selection.requireApiKey()),
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (useJsonSchema && (status == 400 || status == 404 || status == 422)) {
        return _chatCompletion(
          selection: selection,
          messages: messages,
          useJsonSchema: false,
        );
      }
      throw _mapDioException(e, modelId: model.id);
    }

    return _extractContent(response.data, modelId: model.id);
  }

  AiChatResult _extractContent(Object? data, {String? modelId}) {
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
    // Motivo grezzo del provider a monte (Google usa `MAX_TOKENS`):
    // OpenRouter non sempre lo normalizza in `finish_reason`.
    final nativeFinishReason = choice?['native_finish_reason'];

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
    logResponse(
      content: textContent,
      stopReason: '$finishReason (native: $nativeFinishReason)',
      usage: data['usage'],
    );
    return AiChatResult(
      textContent,
      isTruncated:
          finishReason == 'length' ||
          const {'MAX_TOKENS', 'length'}.contains(nativeFinishReason),
    );
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
