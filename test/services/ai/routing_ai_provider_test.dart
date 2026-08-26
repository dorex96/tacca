import 'package:tacca/services/ai/ai_provider.dart';
import 'package:tacca/services/ai/ai_selection.dart';
import 'package:tacca/services/ai/dto/plan_dto.dart';
import 'package:tacca/services/ai/model_catalog.dart';
import 'package:tacca/services/ai/providers/routing_ai_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

/// Provider fittizio che registra solo di essere stato chiamato.
class _SpyProvider implements AiProvider {
  _SpyProvider(this.name);

  final String name;
  int extractCalls = 0;
  int testCalls = 0;

  @override
  Future<PlanExtraction> extractPlan({
    List<AiImage> images = const [],
    String? text,
    String? userHint,
  }) async {
    extractCalls++;
    return PlanExtraction(
      plan: PlanDto(name: name, days: const []),
      usedFallback: false,
      rawResponse: name,
    );
  }

  @override
  Future<void> testConnection() async => testCalls++;
}

const _catalog = AiModelCatalog(
  defaultProviderId: AiProviderId.openRouter,
  providers: [
    AiProviderOption(
      id: AiProviderId.openRouter,
      label: 'OpenRouter',
      defaultModelId: 'a/one',
      models: [AiModelOption(id: 'a/one', label: 'Uno')],
    ),
    AiProviderOption(
      id: AiProviderId.anthropic,
      label: 'Anthropic',
      defaultModelId: 'claude-opus-5',
      models: [AiModelOption(id: 'claude-opus-5', label: 'Opus')],
    ),
  ],
);

void main() {
  late FakeSettingsRepository settings;
  late _SpyProvider openRouter;
  late _SpyProvider anthropic;
  late RoutingAiProvider provider;

  setUp(() {
    settings = FakeSettingsRepository();
    openRouter = _SpyProvider('openrouter');
    anthropic = _SpyProvider('anthropic');
    provider = RoutingAiProvider(
      selection: AiSelectionResolver(settings: settings, catalog: _catalog),
      providers: {
        AiProviderId.openRouter: openRouter,
        AiProviderId.anthropic: anthropic,
      },
    );
  });

  test(
    'senza scelta salvata usa il provider di default del catalogo',
    () async {
      final extraction = await provider.extractPlan(text: 'Panca');

      expect(extraction.plan.name, 'openrouter');
      expect(openRouter.extractCalls, 1);
      expect(anthropic.extractCalls, 0);
    },
  );

  test('con Anthropic selezionato la richiesta va ad Anthropic', () async {
    settings.providerId = 'anthropic';

    final extraction = await provider.extractPlan(text: 'Panca');

    expect(extraction.plan.name, 'anthropic');
    expect(anthropic.extractCalls, 1);
    expect(openRouter.extractCalls, 0);
  });

  test(
    'la scelta si rilegge a ogni chiamata, senza ricostruire nulla',
    () async {
      await provider.extractPlan(text: 'Panca');
      settings.providerId = 'anthropic';
      await provider.extractPlan(text: 'Panca');

      expect(openRouter.extractCalls, 1);
      expect(anthropic.extractCalls, 1);
    },
  );

  test('anche il test connessione segue il provider scelto', () async {
    settings.providerId = 'anthropic';

    await provider.testConnection();

    expect(anthropic.testCalls, 1);
    expect(openRouter.testCalls, 0);
  });

  test('un provider salvato non più implementato ricade sul default', () async {
    settings.providerId = 'provider-sparito';

    await provider.testConnection();

    expect(openRouter.testCalls, 1);
  });
}
