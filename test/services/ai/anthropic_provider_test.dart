import 'dart:convert';
import 'dart:typed_data';

import 'package:tacca/core/errors/ai_exception.dart';
import 'package:tacca/data/entities/block.dart';
import 'package:tacca/services/ai/ai_provider.dart';
import 'package:tacca/services/ai/ai_selection.dart';
import 'package:tacca/services/ai/model_catalog.dart';
import 'package:tacca/services/ai/providers/anthropic_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fakes.dart';

class _MockAdapter extends Mock implements HttpClientAdapter {}

const _catalog = AiModelCatalog(
  defaultProviderId: AiProviderId.anthropic,
  providers: [
    AiProviderOption(
      id: AiProviderId.anthropic,
      label: 'Anthropic',
      defaultModelId: 'schema/model',
      models: [
        AiModelOption(
          id: 'schema/model',
          label: 'Con schema',
          supportsVision: true,
          supportsJsonSchema: true,
          maxOutputTokens: 12345,
        ),
        AiModelOption(id: 'plain/model', label: 'Senza schema'),
        AiModelOption(
          id: 'effort/model',
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

/// Corpo di risposta della Messages API con [text] come testo del modello.
String _messageBody(String text, {String stopReason = 'end_turn'}) =>
    jsonEncode({
      'id': 'msg_1',
      'type': 'message',
      'role': 'assistant',
      'content': [
        {'type': 'text', 'text': text},
      ],
      'stop_reason': stopReason,
      'usage': {'input_tokens': 10, 'output_tokens': 20},
    });

void main() {
  late _MockAdapter adapter;
  late FakeSettingsRepository settings;
  late AnthropicProvider provider;

  /// Richieste catturate dall'adapter, nell'ordine di invio.
  late List<RequestOptions> requests;

  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/'));
  });

  setUp(() {
    adapter = _MockAdapter();
    settings = FakeSettingsRepository(
      apiKey: 'sk-ant-test',
      defaultProviderId: 'anthropic',
    );
    requests = [];
    final dio = Dio(BaseOptions(baseUrl: 'https://api.anthropic.com/v1'))
      ..httpClientAdapter = adapter;
    provider = AnthropicProvider(
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

  ResponseBody ok(String text, {String stopReason = 'end_turn'}) =>
      ResponseBody.fromString(
        _messageBody(text, stopReason: stopReason),
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
      'type': 'error',
      'error': {'type': 'invalid_request_error', 'message': message},
    }),
  );

  group('extractPlan', () {
    test('risposta valida al primo colpo, con output_config.format', () async {
      enqueueResponses([ok(_validPlanJson)]);

      final extraction = await provider.extractPlan(text: 'Panca 4x8');

      expect(extraction.usedFallback, isFalse);
      expect(extraction.plan.name, 'Scheda');
      expect(requests, hasLength(1));

      final request = requests.single;
      expect(request.path, contains('/messages'));
      expect(request.headers['x-api-key'], 'sk-ant-test');
      expect(request.headers['anthropic-version'], '2023-06-01');

      final body = request.data as Map<String, dynamic>;
      expect(body['model'], 'schema/model');
      expect(body['max_tokens'], 12345);
      expect(body['system'], isA<String>());
      final format =
          (body['output_config'] as Map<String, dynamic>)['format']
              as Map<String, dynamic>;
      expect(format['type'], 'json_schema');
      // I vincoli non supportati dallo structured output vanno tolti, o la
      // richiesta viene rifiutata.
      expect(jsonEncode(format['schema']), isNot(contains('minItems')));
    });

    test(
      'max_tokens ricade sul default quando il catalogo non lo indica',
      () async {
        settings.modelId = 'plain/model';
        enqueueResponses([ok('```json\n$_validPlanJson\n```')]);

        await provider.extractPlan(text: 'Panca 4x8');

        final body = requests.single.data as Map<String, dynamic>;
        expect(body['max_tokens'], AiModelOption.defaultMaxOutputTokens);
      },
    );

    test(
      'il modello senza supporto schema usa la richiesta prompt-based',
      () async {
        settings.modelId = 'plain/model';
        enqueueResponses([ok('```json\n$_validPlanJson\n```')]);

        final extraction = await provider.extractPlan(text: 'Panca 4x8');

        expect(extraction.plan.name, 'Scheda');
        final body = requests.single.data as Map<String, dynamic>;
        expect(body.containsKey('output_config'), isFalse);
      },
    );

    test('effort nel catalogo finisce in output_config', () async {
      settings.modelId = 'effort/model';
      enqueueResponses([ok(_validPlanJson)]);

      await provider.extractPlan(text: 'Panca 4x8');

      final body = requests.single.data as Map<String, dynamic>;
      final outputConfig = body['output_config'] as Map<String, dynamic>;
      expect(outputConfig['effort'], 'low');
      // Il modello non dichiara lo schema: solo l'effort, niente format.
      expect(outputConfig.containsKey('format'), isFalse);
    });

    test('senza effort nel catalogo, niente campo effort', () async {
      enqueueResponses([ok(_validPlanJson)]);

      await provider.extractPlan(text: 'Panca 4x8');

      final body = requests.single.data as Map<String, dynamic>;
      final outputConfig = body['output_config'] as Map<String, dynamic>;
      expect(outputConfig.containsKey('effort'), isFalse);
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

        // Fase 1: l'immagine viaggia come blocco base64, senza schema.
        final transcription = requests[0].data as Map<String, dynamic>;
        final content =
            (transcription['messages'] as List).single['content']
                as List<dynamic>;
        final imageBlock = content.first as Map<String, dynamic>;
        expect(imageBlock['type'], 'image');
        expect(imageBlock['source'], {
          'type': 'base64',
          'media_type': 'image/jpeg',
          'data': base64Encode([1, 2, 3]),
        });
        expect((content[1] as Map<String, dynamic>)['type'], 'text');
        expect(transcription.containsKey('output_config'), isFalse);

        // Fase 2: solo testo, con lo schema, e nessuna immagine allegata.
        final structuring = requests[1].data as Map<String, dynamic>;
        expect(structuring.containsKey('output_config'), isTrue);
        final structuringContent =
            (structuring['messages'] as List).single['content']
                as List<dynamic>;
        expect(structuringContent, hasLength(1));
        expect(
          (structuringContent.single as Map<String, dynamic>)['text'],
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
      final messages = retry['messages'] as List;
      expect(messages, hasLength(3));
      expect(messages[1]['role'], 'assistant');
      expect(messages[2]['role'], 'user');
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

    test('risposta troncata (stop_reason: max_tokens) → errore esplicito, '
        'nessun retry che accorcia la scheda', () async {
      enqueueResponses([ok(_validPlanJson, stopReason: 'max_tokens')]);

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

    test(
      'rifiuto del modello (stop_reason: refusal) → messaggio parlante',
      () async {
        enqueueResponses([ok('', stopReason: 'refusal')]);

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

    test('senza key salvata non parte nessuna chiamata (RNF-07)', () async {
      settings.apiKey = null;
      enqueueResponses([ok(_validPlanJson)]);

      await expectLater(
        provider.extractPlan(text: 'Panca'),
        throwsA(isA<AiConfigurationException>()),
      );
      expect(requests, isEmpty);
    });

    test('401 → AiAuthException con il rimando alle impostazioni', () async {
      enqueueResponses([errorBody(401, 'invalid x-api-key')]);

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

    test('429 → AiQuotaException (limite temporaneo)', () async {
      enqueueResponses([errorBody(429, 'rate limit exceeded')]);

      await expectLater(
        provider.extractPlan(text: 'Panca'),
        throwsA(isA<AiQuotaException>()),
      );
    });

    test('400 sul credito → quota, non un errore generico', () async {
      enqueueResponses([
        errorBody(400, 'Your credit balance is too low to access the API'),
      ]);

      await expectLater(
        provider.extractPlan(text: 'Panca'),
        throwsA(
          isA<AiQuotaException>().having(
            (e) => e.message,
            'message',
            allOf(contains('Credito Anthropic'), contains('billing')),
          ),
        ),
      );
      // Il credito finito non è un rifiuto dello schema: niente secondo giro.
      expect(requests, hasLength(1));
    });

    test('529 → sovraccarico temporaneo', () async {
      enqueueResponses([errorBody(529, 'overloaded')]);

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
          requestOptions: RequestOptions(path: '/messages'),
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(
        provider.extractPlan(text: 'Panca'),
        throwsA(
          isA<AiNetworkException>().having(
            (e) => e.message,
            'message',
            contains('Anthropic'),
          ),
        ),
      );
    });

    test(
      'output_config rifiutato dal modello (400) → ritenta prompt-based (S-02)',
      () async {
        enqueueResponses([
          errorBody(400, 'output_config.format: unsupported parameter'),
          ok('```json\n$_validPlanJson\n```'),
        ]);

        final extraction = await provider.extractPlan(text: 'Panca');

        expect(extraction.plan.name, 'Scheda');
        expect(requests, hasLength(2));
        final first = requests[0].data as Map<String, dynamic>;
        final second = requests[1].data as Map<String, dynamic>;
        expect(first.containsKey('output_config'), isTrue);
        expect(second.containsKey('output_config'), isFalse);
      },
    );
  });

  group('testConnection', () {
    test('completa con una key valida', () async {
      enqueueResponses([status(200, body: '{"data":[]}')]);

      await provider.testConnection();

      expect(requests.single.path, contains('/models'));
      expect(requests.single.method, 'GET');
      expect(requests.single.headers['x-api-key'], 'sk-ant-test');
    });

    test('401 → AiAuthException', () async {
      enqueueResponses([errorBody(401, 'invalid x-api-key')]);

      await expectLater(
        provider.testConnection(),
        throwsA(isA<AiAuthException>()),
      );
    });
  });
}
