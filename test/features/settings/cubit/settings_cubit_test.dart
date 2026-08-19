import 'package:tacca/core/errors/ai_exception.dart';
import 'package:tacca/features/settings/cubit/settings_cubit.dart';
import 'package:tacca/features/settings/cubit/settings_state.dart';
import 'package:tacca/services/ai/ai_provider.dart';
import 'package:tacca/services/ai/model_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fakes.dart';

class _FakeAiProvider implements AiProvider {
  Object? testError;
  int testCalls = 0;

  @override
  Future<PlanExtraction> extractPlan({
    List<AiImage> images = const [],
    String? text,
    String? userHint,
  }) => throw UnimplementedError();

  @override
  Future<void> testConnection() async {
    testCalls++;
    final error = testError;
    if (error != null) throw error;
  }
}

const _catalog = AiModelCatalog(
  defaultModelId: 'a/default',
  models: [
    AiModelOption(id: 'a/default', label: 'Default', supportsVision: true),
    AiModelOption(id: 'b/other', label: 'Altro'),
  ],
);

void main() {
  late FakeSettingsRepository settings;
  late _FakeAiProvider provider;

  setUp(() {
    settings = FakeSettingsRepository();
    provider = _FakeAiProvider();
  });

  SettingsCubit buildCubit() =>
      SettingsCubit(settings: settings, provider: provider, catalog: _catalog);

  test(
    'senza key: hasApiKey false e modello di default del catalogo',
    () async {
      final cubit = buildCubit();
      await pumpEventQueue();

      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.hasApiKey, isFalse);
      expect(cubit.state.selectedModelId, 'a/default');
    },
  );

  test('carica key e modello salvati', () async {
    settings
      ..apiKey = 'sk-or-x'
      ..modelId = 'b/other';
    final cubit = buildCubit();
    await pumpEventQueue();

    expect(cubit.state.hasApiKey, isTrue);
    expect(cubit.state.selectedModelId, 'b/other');
  });

  test(
    'un modello salvato rimosso dal catalogo JSON torna al default',
    () async {
      settings.modelId = 'x/rimosso';
      final cubit = buildCubit();
      await pumpEventQueue();

      expect(cubit.state.selectedModelId, 'a/default');
    },
  );

  test('saveApiKey persiste (trim) e azzera l\'esito del test', () async {
    final cubit = buildCubit();
    await pumpEventQueue();

    await cubit.saveApiKey('  sk-or-nuova  ');

    expect(settings.apiKey, 'sk-or-nuova');
    expect(cubit.state.hasApiKey, isTrue);
    expect(cubit.state.testStatus, AiConnectionTestStatus.idle);
  });

  test('removeApiKey cancella la key', () async {
    settings.apiKey = 'sk-or-x';
    final cubit = buildCubit();
    await pumpEventQueue();

    await cubit.removeApiKey();

    expect(settings.apiKey, isNull);
    expect(cubit.state.hasApiKey, isFalse);
  });

  test('selectModel persiste la scelta', () async {
    final cubit = buildCubit();
    await pumpEventQueue();

    await cubit.selectModel('b/other');

    expect(settings.modelId, 'b/other');
    expect(cubit.state.selectedModelId, 'b/other');
  });

  test('test connessione riuscito', () async {
    settings.apiKey = 'sk-or-x';
    final cubit = buildCubit();
    await pumpEventQueue();

    await cubit.testConnection();

    expect(provider.testCalls, 1);
    expect(cubit.state.testStatus, AiConnectionTestStatus.success);
  });

  test('key invalida: fallimento con messaggio parlante (§9)', () async {
    settings.apiKey = 'sk-or-x';
    provider.testError = const AiAuthException('API key non valida.');
    final cubit = buildCubit();
    await pumpEventQueue();

    await cubit.testConnection();

    expect(cubit.state.testStatus, AiConnectionTestStatus.failure);
    expect(cubit.state.testErrorMessage, 'API key non valida.');
  });
}
