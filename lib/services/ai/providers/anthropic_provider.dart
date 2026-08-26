import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/errors/ai_exception.dart';
import '../ai_provider.dart';
import '../ai_selection.dart';
import '../plan_parser.dart';
import '../prompts.dart';
import 'chat_plan_provider.dart';

/// Chiavi di JSON Schema che lo structured output di Anthropic non accetta
/// (vincoli numerici e di lunghezza): lasciarle nello schema fa rifiutare la
/// richiesta con un 400. Le stesse regole restano scritte nel prompt, e la
/// validazione semantica vera è quella del [PlanParser].
const _unsupportedSchemaKeys = {
  'minItems',
  'maxItems',
  'minLength',
  'maxLength',
  'minimum',
  'maximum',
  'multipleOf',
  'pattern',
};

/// Lo schema §5.3 ripulito dei vincoli non supportati.
final Map<String, dynamic> _planSchema =
    _stripUnsupported(planJsonSchema) as Map<String, dynamic>;

Object? _stripUnsupported(Object? node) {
  if (node is Map<String, dynamic>) {
    return <String, dynamic>{
      for (final entry in node.entries)
        if (!_unsupportedSchemaKeys.contains(entry.key))
          entry.key: _stripUnsupported(entry.value),
    };
  }
  if (node is List) return [for (final item in node) _stripUnsupported(item)];
  return node;
}

/// Provider Anthropic (Messages API, §6.1).
///
/// Structured output via `output_config.format` per i modelli che lo
/// dichiarano nel catalogo; per gli altri (o se il modello lo rifiuta a
/// runtime, rischio S-02) la richiesta riparte senza schema e il JSON viene
/// estratto dal testo dal [PlanParser].
///
/// Tutta la pipeline §6.2 (due fasi, retry, fallback) sta in
/// [ChatPlanProvider]: qui resta solo il protocollo.
class AnthropicProvider extends ChatPlanProvider {
  AnthropicProvider({
    required super.selection,
    Dio? dio,
    super.parser = const PlanParser(),
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: 'https://api.anthropic.com/v1',
               connectTimeout: const Duration(seconds: 15),
               // Le estrazioni vision su schede dense possono essere lente.
               receiveTimeout: const Duration(minutes: 3),
             ),
           );

  final Dio _dio;

  /// Versione dell'API richiesta su ogni chiamata: Anthropic la pretende
  /// esplicita e la usa per non cambiare il contratto sotto ai client.
  static const _apiVersion = '2023-06-01';

  @override
  AiProviderId get id => AiProviderId.anthropic;

  /// Verifica la key sull'elenco dei modelli: è la chiamata autenticata più
  /// economica dell'API (nessun token di generazione).
  @override
  Future<void> testConnection() async {
    final apiKey = (await requireSelection()).requireApiKey();
    try {
      await _dio.get<Object?>(
        '/models',
        queryParameters: {'limit': 1},
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
    return _messages(
      selection: selection,
      system: system,
      messages: [for (final turn in turns) _message(turn)],
      structured: structured,
    );
  }

  /// Un turno nel formato Anthropic: lista di blocchi di contenuto, con
  /// l'immagine (base64) prima del testo, come raccomanda la documentazione
  /// quando la domanda riguarda l'immagine stessa.
  Map<String, dynamic> _message(AiChatTurn turn) {
    final image = turn.image;
    return {
      'role': turn.role == AiChatRole.assistant ? 'assistant' : 'user',
      'content': [
        if (image != null)
          {
            'type': 'image',
            'source': {
              'type': 'base64',
              'media_type': image.mimeType,
              'data': base64Encode(image.bytes),
            },
          },
        {'type': 'text', 'text': turn.text},
      ],
    };
  }

  Options _authOptions(String apiKey) {
    return Options(
      headers: {'x-api-key': apiKey, 'anthropic-version': _apiVersion},
    );
  }

  /// Una chiamata `POST /messages`; ritorna testo e `stop_reason`.
  ///
  /// Se il modello rifiuta `output_config` (HTTP 400/404/422 che non sia un
  /// problema di key o di credito), la stessa richiesta riparte una volta in
  /// modalità prompt-based (S-02).
  Future<AiChatResult> _messages({
    required AiSelection selection,
    required String system,
    required List<Map<String, dynamic>> messages,
    required bool structured,
  }) async {
    final model = selection.model;
    final effort = model.effort;
    final body = <String, dynamic>{
      'model': model.id,
      // `max_tokens` è obbligatorio: è il tetto della singola risposta e,
      // insieme al pensiero del modello, decide se la scheda arriva intera.
      'max_tokens': model.maxOutputTokens,
      'system': system,
      'messages': messages,
      if (structured || effort != null)
        'output_config': {
          if (effort != null) 'effort': effort,
          if (structured)
            'format': {'type': 'json_schema', 'schema': _planSchema},
        },
    };

    final Response<Object?> response;
    try {
      response = await _dio.post<Object?>(
        '/messages',
        data: body,
        options: _authOptions(selection.requireApiKey()),
      );
    } on DioException catch (e) {
      final mapped = _mapDioException(e);
      final status = e.response?.statusCode;
      // Solo un rifiuto della *richiesta* giustifica il secondo tentativo:
      // key invalida o credito finito darebbero lo stesso errore due volte.
      if (structured &&
          (status == 400 || status == 404 || status == 422) &&
          mapped is! AiAuthException &&
          mapped is! AiQuotaException) {
        return _messages(
          selection: selection,
          system: system,
          messages: messages,
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

    final stopReason = data['stop_reason'];
    // I classificatori di sicurezza possono declinare la richiesta con un
    // 200: senza questo controllo la risposta vuota sembrerebbe un guasto.
    if (stopReason == 'refusal') {
      throw const AiResponseException(
        'Il modello ha rifiutato di elaborare il contenuto inviato. '
        'Riprova con una foto o un testo diverso, oppure cambia modello '
        'nelle impostazioni AI.',
      );
    }

    final content = data['content'];
    final textContent = content is List
        ? content
              .whereType<Map<String, dynamic>>()
              .where((block) => block['type'] == 'text')
              .map((block) => block['text'])
              .whereType<String>()
              .join('\n')
        : '';
    if (textContent.trim().isEmpty) {
      throw const AiResponseException(
        'Il modello ha restituito una risposta vuota.',
      );
    }

    logResponse(
      content: textContent,
      stopReason: stopReason is String ? stopReason : null,
      usage: data['usage'],
    );
    return AiChatResult(textContent, isTruncated: stopReason == 'max_tokens');
  }

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
      'Impossibile raggiungere Anthropic: controlla la connessione.',
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
    // Il credito esaurito arriva come 400 con un messaggio sul saldo, non
    // come stato dedicato: senza riconoscerlo finirebbe fra gli errori
    // generici e l'utente non saprebbe cosa fare.
    if (_isCreditExhausted(message)) {
      return const AiQuotaException(
        'Credito Anthropic esaurito: aggiungi credito su '
        'console.anthropic.com/settings/billing, oppure passa a un altro '
        'provider nelle impostazioni AI.',
      );
    }
    return switch (status) {
      401 || 403 => AiAuthException(
        'API key Anthropic non valida o senza permessi: controllala nelle '
        'impostazioni AI.',
      ),
      429 => const AiQuotaException(
        'Troppe richieste ad Anthropic in poco tempo (o limite di utilizzo '
        'raggiunto): aspetta qualche istante e riprova.',
      ),
      529 => const AiNetworkException(
        'I server Anthropic sono momentaneamente sovraccarichi: riprova '
        'fra poco.',
      ),
      _ => AiNetworkException(message),
    };
  }

  bool _isCreditExhausted(String message) {
    final detail = message.toLowerCase();
    return detail.contains('credit balance') ||
        detail.contains('insufficient credit') ||
        detail.contains('billing');
  }
}
