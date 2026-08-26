import 'dart:io';

import 'package:tacca/services/ai/ai_provider.dart';
import 'package:tacca/services/ai/model_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiModelCatalog.fromJsonString', () {
    test('carica provider, modelli, capacità e default dal JSON', () {
      final catalog = AiModelCatalog.fromJsonString('''
      {
        "defaultProviderId": "anthropic",
        "providers": [
          {
            "id": "openrouter",
            "label": "OpenRouter",
            "keyHint": "sk-or-…",
            "defaultModelId": "b/two",
            "models": [
              { "id": "a/one", "label": "Uno", "supportsVision": true, "supportsJsonSchema": true },
              { "id": "b/two", "label": "Due", "supportsVision": false }
            ]
          },
          {
            "id": "anthropic",
            "label": "Anthropic",
            "defaultModelId": "claude-opus-5",
            "models": [
              { "id": "claude-opus-5", "label": "Opus", "supportsVision": true, "effort": "low" }
            ]
          }
        ]
      }
      ''');

      expect(catalog.providers, hasLength(2));
      expect(catalog.defaultProviderId, AiProviderId.anthropic);
      expect(catalog.defaultProvider.label, 'Anthropic');

      final openRouter = catalog.byId(AiProviderId.openRouter)!;
      expect(openRouter.keyHint, 'sk-or-…');
      expect(openRouter.defaultModelId, 'b/two');
      expect(openRouter.models, hasLength(2));
      expect(openRouter.byId('a/one')!.supportsVision, isTrue);
      expect(openRouter.byId('a/one')!.supportsJsonSchema, isTrue);
      expect(openRouter.byId('b/two')!.supportsVision, isFalse);
      expect(openRouter.byId('b/two')!.supportsJsonSchema, isFalse);
      expect(openRouter.byId('a/one')!.disableReasoning, isFalse);
      expect(openRouter.byId('a/one')!.effort, isNull);
      expect(openRouter.byId('c/three'), isNull);

      final anthropic = catalog.byId(AiProviderId.anthropic)!;
      expect(anthropic.keyHint, isNull);
      expect(anthropic.byId('claude-opus-5')!.effort, 'low');
    });

    test('il provider google si legge come gli altri', () {
      final catalog = AiModelCatalog.fromJsonString('''
      {
        "defaultProviderId": "google",
        "providers": [
          {
            "id": "google",
            "label": "Google Gemini",
            "keyHint": "AIza…",
            "defaultModelId": "gemini-3.7-flash",
            "models": [
              { "id": "gemini-3.7-flash", "label": "Flash", "supportsVision": true, "supportsJsonSchema": true, "effort": "low" }
            ]
          }
        ]
      }
      ''');

      expect(catalog.defaultProviderId, AiProviderId.google);
      final google = catalog.byId(AiProviderId.google)!;
      expect(google.keyHint, 'AIza…');
      expect(google.defaultModel.label, 'Flash');
      expect(google.defaultModel.supportsVision, isTrue);
      expect(google.defaultModel.supportsJsonSchema, isTrue);
      expect(google.defaultModel.effort, 'low');
    });

    test('disableReasoning si legge dal JSON, default false', () {
      final provider = _singleProvider('''
        { "id": "a/one", "disableReasoning": true },
        { "id": "b/two" }
      ''');
      expect(provider.byId('a/one')!.disableReasoning, isTrue);
      expect(provider.byId('b/two')!.disableReasoning, isFalse);
    });

    test('un modello di default inesistente ripiega sul primo', () {
      final catalog = AiModelCatalog.fromJsonString('''
      {
        "providers": [
          {
            "id": "openrouter",
            "defaultModelId": "x/rimosso",
            "models": [ { "id": "a/one" } ]
          }
        ]
      }
      ''');
      expect(catalog.providers.single.defaultModelId, 'a/one');
    });

    test('un provider di default inesistente ripiega sul primo', () {
      final catalog = AiModelCatalog.fromJsonString('''
      {
        "defaultProviderId": "anthropic",
        "providers": [
          { "id": "openrouter", "models": [ { "id": "a/one" } ] }
        ]
      }
      ''');
      expect(catalog.defaultProviderId, AiProviderId.openRouter);
    });

    test('label mancante ripiega sull\'id; voci senza id vengono ignorate', () {
      final provider = _singleProvider('''
        { "id": "a/one" }, { "label": "senza id" }
      ''');
      expect(provider.label, 'openrouter');
      expect(provider.models.single.label, 'a/one');
    });

    test('un provider senza implementazione viene scartato', () {
      final catalog = AiModelCatalog.fromJsonString('''
      {
        "providers": [
          { "id": "provider-inventato", "models": [ { "id": "x/one" } ] },
          { "id": "anthropic", "models": [ { "id": "claude-opus-5" } ] }
        ]
      }
      ''');
      expect(catalog.providers.single.id, AiProviderId.anthropic);
    });

    test('un provider senza modelli validi viene scartato', () {
      final catalog = AiModelCatalog.fromJsonString('''
      {
        "providers": [
          { "id": "openrouter", "models": [] },
          { "id": "anthropic", "models": [ { "id": "claude-opus-5" } ] }
        ]
      }
      ''');
      expect(catalog.providers.single.id, AiProviderId.anthropic);
    });

    test('JSON senza provider validi è un errore di configurazione', () {
      expect(
        () => AiModelCatalog.fromJsonString('{ "providers": [] }'),
        throwsFormatException,
      );
      expect(() => AiModelCatalog.fromJsonString('[]'), throwsFormatException);
    });

    test('modelOrDefault ignora un id non più nel catalogo', () {
      final provider = _singleProvider('{ "id": "a/one" }, { "id": "b/two" }');
      expect(provider.modelOrDefault('b/two').id, 'b/two');
      expect(provider.modelOrDefault('x/rimosso').id, 'a/one');
      expect(provider.modelOrDefault(null).id, 'a/one');
    });
  });

  // L'asset è configurazione: se si rompe (o nomina un provider senza
  // implementazione) l'app non parte, e nessun altro test se ne accorge.
  test('assets/ai/models.json è un catalogo valido', () {
    final catalog = AiModelCatalog.fromJsonString(
      File(AiModelCatalog.assetPath).readAsStringSync(),
    );

    expect(
      catalog.providers.map((provider) => provider.id),
      containsAll(AiProviderId.values),
      reason: 'ogni provider implementato deve essere offerto nel catalogo',
    );
    for (final provider in catalog.providers) {
      expect(provider.byId(provider.defaultModelId), isNotNull);
      expect(provider.models, isNotEmpty);
    }
  });
}

/// Catalogo con un solo provider OpenRouter e i [models] passati come JSON.
AiProviderOption _singleProvider(String models) =>
    AiModelCatalog.fromJsonString(
      '{ "providers": [ { "id": "openrouter", "models": [$models] } ] }',
    ).providers.single;
