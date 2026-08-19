import 'package:app_palestra/services/ai/model_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiModelCatalog.fromJsonString', () {
    test('carica modelli, capacità e default dal JSON', () {
      final catalog = AiModelCatalog.fromJsonString('''
      {
        "defaultModelId": "b/two",
        "models": [
          { "id": "a/one", "label": "Uno", "supportsVision": true, "supportsJsonSchema": true },
          { "id": "b/two", "label": "Due", "supportsVision": false }
        ]
      }
      ''');

      expect(catalog.models, hasLength(2));
      expect(catalog.defaultModelId, 'b/two');
      expect(catalog.byId('a/one')!.supportsVision, isTrue);
      expect(catalog.byId('a/one')!.supportsJsonSchema, isTrue);
      expect(catalog.byId('b/two')!.supportsVision, isFalse);
      expect(catalog.byId('b/two')!.supportsJsonSchema, isFalse);
      expect(catalog.byId('a/one')!.disableReasoning, isFalse);
      expect(catalog.byId('c/three'), isNull);
    });

    test('disableReasoning si legge dal JSON, default false', () {
      final catalog = AiModelCatalog.fromJsonString('''
      {
        "models": [
          { "id": "a/one", "disableReasoning": true },
          { "id": "b/two" }
        ]
      }
      ''');
      expect(catalog.byId('a/one')!.disableReasoning, isTrue);
      expect(catalog.byId('b/two')!.disableReasoning, isFalse);
    });

    test('un default inesistente ripiega sul primo modello', () {
      final catalog = AiModelCatalog.fromJsonString('''
      { "defaultModelId": "x/rimosso", "models": [ { "id": "a/one" } ] }
      ''');
      expect(catalog.defaultModelId, 'a/one');
    });

    test('label mancante ripiega sull\'id; voci senza id vengono ignorate', () {
      final catalog = AiModelCatalog.fromJsonString('''
      { "models": [ { "id": "a/one" }, { "label": "senza id" } ] }
      ''');
      expect(catalog.models.single.label, 'a/one');
    });

    test('JSON senza modelli validi è un errore di configurazione', () {
      expect(
        () => AiModelCatalog.fromJsonString('{ "models": [] }'),
        throwsFormatException,
      );
      expect(() => AiModelCatalog.fromJsonString('[]'), throwsFormatException);
    });
  });
}
