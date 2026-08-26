import 'dart:convert';
import 'dart:typed_data';

import 'package:tacca/core/errors/ai_exception.dart';
import 'package:tacca/data/entities/block.dart';
import 'package:tacca/services/ai/ai_provider.dart';
import 'package:tacca/services/ai/ai_selection.dart';
import 'package:tacca/services/ai/model_catalog.dart';
import 'package:tacca/services/ai/providers/google_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fakes.dart';

class _MockAdapter extends Mock implements HttpClientAdapter {}

const _catalog = AiModelCatalog(
  defaultProviderId: AiProviderId.google,
  providers: [
    AiProviderOption(
      id: AiProviderId.google,
      label: 'Google Gemini',
      defaultModelId: 'schema-model',
      models: [
        AiModelOption(
          id: 'schema-model',
          label: 'Con schema',
          supportsVision: true,
          supportsJsonSchema: true,
          maxOutputTokens: 12345,
        ),
        AiModelOption(id: 'plain-model', label: 'Senza schema'),
        AiModelOption(
          id: 'effort-model',
          label: 'Con effort configurato',
          effort: 'low',
        ),
      ],
    ),
  ],
);

const _validPlanJson =
    '{"name":"Scheda","days":[{"label":"A","blocks":[{"type":"standard",'
    '"exercises":[{"name":"Panca","sets":4,"reps":"8"}]}]}]}';

/// Corpo di risposta di `generateContent` con [text] come testo del modello.
String _candidateBody(String text, {String finishReason = 'STOP'}) =>
    jsonEncode({
      'candidates': [
        {
          'content': {
            'role': 'model',
            'parts': [
              {'text': text},
            ],
          },
          'finishReason': finishReason,
        },
      ],
      'usageMetadata': {'promptTokenCount': 10, 'candidatesTokenCount': 20},
    });

/// Scende nello schema tradotto seguendo [keys]: la catena di cast a mano
/// su `properties`/`items` annidati sarebbe illeggibile.
Map<String, dynamic> child(Map<String, dynamic> node, List<String> keys) {
  var current = node;
  for (final key in keys) {
    current = current[key] as Map<String, dynamic>;
  }
  return current;
}

void main() {
  late _MockAdapter adapter;
  late FakeSettingsRepository settings;
  late GoogleProvider provider;

  /// Richieste catturate dall'adapter, nell'ordine di invio.
  late List<RequestOptions> requests;

  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/'));
  });

  setUp(() {
    adapter = _MockAdapter();
    settings = FakeSettingsRepository(
      apiKey: 'AIza-test',
      defaultProviderId: 'google',
    );
    requests = [];
    final dio = Dio(
      BaseOptions(baseUrl: 'https://generativelanguage.googleapis.com/v1beta'),
    )..httpClientAdapter = adapter;
    provider = GoogleProvider(
      selection: AiSelectionResolver(settings: settings, catalog: _catalog),
      dio: dio,
    );
  });

  /// Accoda le risposte HTTP che l'adapter servirà in sequenza.
  void enqueueResponses(List<ResponseBody> responses) {
    var index = 0;
    when(() => adapter.fetch(any(), any(), any())).thenAnswer((invocation) {
      requests.add(invocation.positionalArguments.first as RequestOptions);
      return Future.value(responses[index++]);
    });
  }

  ResponseBody ok(String text, {String finishReason = 'STOP'}) =>
      ResponseBody.fromString(
        _candidateBody(text, finishReason: finishReason),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );

  ResponseBody status(int code, {String body = '{}'}) =>
      ResponseBody.fromString(
        body,
        code,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );

  ResponseBody errorBody(int code, String message) => status(
    code,
    body: jsonEncode({
      'error': {'code': code, 'message': message, 'status': 'INVALID_ARGUMENT'},
    }),
  );

  /// `generationConfig` della richiesta [index].
  Map<String, dynamic> generationConfig(int index) =>
      (requests[index].data as Map<String, dynamic>)['generationConfig']
          as Map<String, dynamic>;

  group('extractPlan', () {
    test('risposta valida al primo colpo, con responseSchema', () async {
      enqueueResponses([ok(_validPlanJson)]);

      final extraction = await provider.extractPlan(text: 'Panca 4x8');

      expect(extraction.usedFallback, isFalse);
      expect(extraction.plan.name, 'Scheda');
      expect(requests, hasLength(1));

      final request = requests.single;
      expect(request.path, '/models/schema-model:generateContent');
      expect(request.headers['x-goog-api-key'], 'AIza-test');

      final body = request.data as Map<String, dynamic>;
      final systemParts =
          (body['systemInstruction'] as Map<String, dynamic>)['parts'] as List;
      expect(
        (systemParts.single as Map<String, dynamic>)['text'],
        isA<String>(),
      );

      final config = generationConfig(0);
      expect(config['maxOutputTokens'], 12345);
      expect(config['responseMimeType'], 'application/json');
      final schema = config['responseSchema'] as Map<String, dynamic>;
      // Gemini non è JSON Schema: tipi maiuscoli dell'enum `Type`, niente
      // `additionalProperties` (che farebbe rifiutare la richiesta) e il
      // nullable come campo, non come unione di tipi.
      expect(schema['type'], 'OBJECT');
      final encoded = jsonEncode(schema);
      expect(encoded, isNot(contains('additionalProperties')));
      expect(encoded, isNot(contains('"type":["string","null"]')));
      expect(encoded, contains('"nullable":true'));
      final name =
          (schema['properties'] as Map<String, dynamic>)['name']
              as Map<String, dynamic>;
      expect(name['type'], 'STRING');
      final description =
          (schema['properties'] as Map<String, dynamic>)['description']
              as Map<String, dynamic>;
      expect(description, {'type': 'STRING', 'nullable': true});
      // I vincoli che Gemini conosce restano: sono utili al modello.
      expect(
        ((schema['properties'] as Map<String, dynamic>)['days']
            as Map<String, dynamic>)['minItems'],
        1,
      );

      // Dentro `properties` le chiavi sono nomi di campo, non parole chiave:
      // il tipo di blocco si chiama `type` e deve sopravvivere alla
      // traduzione con il suo enum, o `required` punterebbe al vuoto.
      final days = child(schema, ['properties', 'days']);
      final blocks = child(days, ['items', 'properties', 'blocks']);
      final blockSchema = child(blocks, ['items']);
      expect(blockSchema['required'], contains('type'));
      final blockType =
          (blockSchema['properties'] as Map<String, dynamic>)['type']
              as Map<String, dynamic>;
      expect(blockType['type'], 'STRING');
      expect(blockType['enum'], contains('superset'));
    });

    test(
      'max_tokens ricade sul default quando il catalogo non lo indica',
      () async {
        settings.modelId = 'plain-model';
        enqueueResponses([ok('```json\n$_validPlanJson\n```')]);

        await provider.extractPlan(text: 'Panca 4x8');

        expect(
          generationConfig(0)['maxOutputTokens'],
          AiModelOption.defaultMaxOutputTokens,
        );
      },
    );

    test(
      'il modello senza supporto schema usa la richiesta prompt-based',
      () async {
        settings.modelId = 'plain-model';
        enqueueResponses([ok('```json\n$_validPlanJson\n```')]);

        final extraction = await provider.extractPlan(text: 'Panca 4x8');

        expect(extraction.plan.name, 'Scheda');
        final config = generationConfig(0);
        expect(config.containsKey('responseSchema'), isFalse);
        expect(config.containsKey('responseMimeType'), isFalse);
      },
    );

    test('effort nel catalogo diventa thinkingLevel', () async {
      settings.modelId = 'effort-model';
      enqueueResponses([ok(_validPlanJson)]);

      await provider.extractPlan(text: 'Panca 4x8');

      expect(generationConfig(0)['thinkingConfig'], {'thinkingLevel': 'low'});
    });

    test('senza effort nel catalogo, niente thinkingConfig', () async {
      enqueueResponses([ok(_validPlanJson)]);

      await provider.extractPlan(text: 'Panca 4x8');

      expect(generationConfig(0).containsKey('thinkingConfig'), isFalse);
    });

    test(
      'foto → trascrizione senza schema, poi strutturazione del testo',
      () async {
        enqueueResponses([ok('Panca 4x8'), ok(_validPlanJson)]);

        final extraction = await provider.extractPlan(
          images: [
            AiImage(Uint8List.fromList([1, 2, 3])),
          ],
        );

        expect(extraction.plan.name, 'Scheda');
        expect(requests, hasLength(2));

        // Fase 1: l'immagine viaggia come parte inline base64, senza schema.
        final transcription = requests[0].data as Map<String, dynamic>;
        final content =
            (transcription['contents'] as List).single as Map<String, dynamic>;
        expect(content['role'], 'user');
        final parts = content['parts'] as List<dynamic>;
        expect((parts.first as Map<String, dynamic>)['inlineData'], {
          'mimeType': 'image/jpeg',
          'data': base64Encode([1, 2, 3]),
        });
        expect((parts[1] as Map<String, dynamic>)['text'], isA<String>());
        expect(generationConfig(0).containsKey('responseSchema'), isFalse);

        // Fase 2: solo testo, con lo schema, e nessuna immagine allegata.
        expect(generationConfig(1).containsKey('responseSchema'), isTrue);
        final structuringParts =
            ((requests[1].data as Map<String, dynamic>)['contents'] as List)
                    .single
                as Map<String, dynamic>;
        final textParts = structuringParts['parts'] as List<dynamic>;
        expect(textParts, hasLength(1));
        expect(
          (textParts.single as Map<String, dynamic>)['text'],
          contains('Panca 4x8'),
        );
      },
    );

    test('JSON malformato → 1 retry correttivo, poi risposta valida', () async {
      enqueueResponses([ok('non è JSON'), ok(_validPlanJson)]);

      final extraction = await provider.extractPlan(text: 'Panca');

      expect(extraction.usedFallback, isFalse);
      expect(requests, hasLength(2));
      final retry = requests[1].data as Map<String, dynamic>;
      final contents = retry['contents'] as List;
      expect(contents, hasLength(3));
      // Il ruolo dell'assistente su Gemini si chiama `model`.
      expect(contents[1]['role'], 'model');
      expect(contents[2]['role'], 'user');
    });

    test(
      'due fallimenti → fallback freeText, input mai perso (RNF-05)',
      () async {
        enqueueResponses([ok('non è JSON'), ok('nemmeno adesso')]);

        final extraction = await provider.extractPlan(text: 'Scheda a mano');

        expect(extraction.usedFallback, isTrue);
        final block = extraction.plan.days.single.blocks.single;
        expect(block.type, BlockType.freeText.name);
        expect(block.content, contains('Scheda a mano'));
      },
    );

    test('risposta troncata (finishReason: MAX_TOKENS) → errore esplicito, '
        'nessun retry che accorcia la scheda', () async {
      enqueueResponses([ok(_validPlanJson, finishReason: 'MAX_TOKENS')]);

      await expectLater(
        provider.extractPlan(text: 'Scheda lunga'),
        throwsA(
          isA<AiResponseException>().having(
            (e) => e.message,
            'message',
            contains('troncata'),
          ),
        ),
      );
      expect(requests, hasLength(1));
    });

    test('budget finito prima di scrivere: nessun testo e MAX_TOKENS → '
        'troncamento, non "risposta vuota"', () async {
      enqueueResponses([ok('', finishReason: 'MAX_TOKENS')]);

      await expectLater(
        provider.extractPlan(text: 'Scheda lunga'),
        throwsA(
          isA<AiResponseException>().having(
            (e) => e.message,
            'message',
            contains('troncata'),
          ),
        ),
      );
    });

    test(
      'rifiuto del modello (finishReason: SAFETY) → messaggio parlante',
      () async {
        enqueueResponses([ok('', finishReason: 'SAFETY')]);

        await expectLater(
          provider.extractPlan(text: 'Panca'),
          throwsA(
            isA<AiResponseException>().having(
              (e) => e.message,
              'message',
              contains('rifiutato'),
            ),
          ),
        );
      },
    );

    test(
      'prompt bloccato a monte (promptFeedback) → stesso messaggio',
      () async {
        enqueueResponses([
          status(
            200,
            body: jsonEncode({
              'promptFeedback': {'blockReason': 'SAFETY'},
            }),
          ),
        ]);

        await expectLater(
          provider.extractPlan(text: 'Panca'),
          throwsA(
            isA<AiResponseException>().having(
              (e) => e.message,
              'message',
              contains('rifiutato'),
            ),
          ),
        );
      },
    );

    test(
      'i riassunti del pensiero non finiscono nel JSON da parsare',
      () async {
        enqueueResponses([
          status(
            200,
            body: jsonEncode({
              'candidates': [
                {
                  'content': {
                    'role': 'model',
                    'parts': [
                      {'text': 'Sto leggendo la scheda…', 'thought': true},
                      {'text': _validPlanJson},
                    ],
                  },
                  'finishReason': 'STOP',
                },
              ],
            }),
          ),
        ]);

        final extraction = await provider.extractPlan(text: 'Panca 4x8');

        expect(extraction.usedFallback, isFalse);
        expect(extraction.plan.name, 'Scheda');
      },
    );

    test('senza key salvata non parte nessuna chiamata (RNF-07)', () async {
      settings.apiKey = null;
      enqueueResponses([ok(_validPlanJson)]);

      await expectLater(
        provider.extractPlan(text: 'Panca'),
        throwsA(isA<AiConfigurationException>()),
      );
      expect(requests, isEmpty);
    });

    test('400 sulla key invalida → auth, non un secondo tentativo', () async {
      enqueueResponses([
        errorBody(400, 'API key not valid. Please pass a valid API key.'),
      ]);

      await expectLater(
        provider.extractPlan(text: 'Panca'),
        throwsA(
          isA<AiAuthException>().having(
            (e) => e.message,
            'message',
            contains('impostazioni AI'),
          ),
        ),
      );
      // La key invalida non è un rifiuto dello schema: niente secondo giro.
      expect(requests, hasLength(1));
    });

    test('403 → AiAuthException con il rimando alle impostazioni', () async {
      enqueueResponses([errorBody(403, 'PERMISSION_DENIED')]);

      await expectLater(
        provider.extractPlan(text: 'Panca'),
        throwsA(
          isA<AiAuthException>().having(
            (e) => e.message,
            'message',
            contains('impostazioni AI'),
          ),
        ),
      );
    });

    test('429 → AiQuotaException che nomina il piano gratuito', () async {
      enqueueResponses([errorBody(429, 'Resource has been exhausted')]);

      await expectLater(
        provider.extractPlan(text: 'Panca'),
        throwsA(
          isA<AiQuotaException>().having(
            (e) => e.message,
            'message',
            contains('gratuito'),
          ),
        ),
      );
      expect(requests, hasLength(1));
    });

    test('503 → sovraccarico temporaneo', () async {
      enqueueResponses([errorBody(503, 'The model is overloaded')]);

      await expectLater(
        provider.extractPlan(text: 'Panca'),
        throwsA(
          isA<AiNetworkException>().having(
            (e) => e.message,
            'message',
            contains('sovraccarichi'),
          ),
        ),
      );
    });

    test('errore di rete → AiNetworkException', () async {
      when(() => adapter.fetch(any(), any(), any())).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/models/x:generateContent'),
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(
        provider.extractPlan(text: 'Panca'),
        throwsA(
          isA<AiNetworkException>().having(
            (e) => e.message,
            'message',
            contains('Google'),
          ),
        ),
      );
    });

    test(
      'responseSchema rifiutato dal modello (400) → ritenta prompt-based (S-02)',
      () async {
        enqueueResponses([
          errorBody(400, 'Invalid JSON payload: unknown name "responseSchema"'),
          ok('```json\n$_validPlanJson\n```'),
        ]);

        final extraction = await provider.extractPlan(text: 'Panca');

        expect(extraction.plan.name, 'Scheda');
        expect(requests, hasLength(2));
        expect(generationConfig(0).containsKey('responseSchema'), isTrue);
        expect(generationConfig(1).containsKey('responseSchema'), isFalse);
      },
    );
  });

  group('testConnection', () {
    test('completa con una key valida', () async {
      enqueueResponses([status(200, body: '{"models":[]}')]);

      await provider.testConnection();

      expect(requests.single.path, contains('/models'));
      expect(requests.single.method, 'GET');
      expect(requests.single.headers['x-goog-api-key'], 'AIza-test');
    });

    test('400 sulla key invalida → AiAuthException', () async {
      enqueueResponses([errorBody(400, 'API_KEY_INVALID')]);

      await expectLater(
        provider.testConnection(),
        throwsA(isA<AiAuthException>()),
      );
    });
  });
}
