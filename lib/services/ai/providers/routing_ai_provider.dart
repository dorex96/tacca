import '../../../core/errors/ai_exception.dart';
import '../ai_provider.dart';
import '../ai_selection.dart';

/// L'[AiProvider] che vede il resto dell'app: a ogni chiamata guarda quale
/// provider è selezionato nelle impostazioni e gira la richiesta alla sua
/// implementazione.
///
/// Serve perché la scelta vive nel secure storage (lettura asincrona) mentre
/// la composizione in `app/di.dart` è sincrona: senza questo strato ogni
/// cubit dovrebbe risolvere il provider da sé, o l'app andrebbe ricostruita
/// a ogni cambio di provider.
class RoutingAiProvider implements AiProvider {
  const RoutingAiProvider({
    required AiSelectionResolver selection,
    required Map<AiProviderId, AiProvider> providers,
  }) : _selection = selection,
       _providers = providers;

  final AiSelectionResolver _selection;
  final Map<AiProviderId, AiProvider> _providers;

  @override
  Future<PlanExtraction> extractPlan({
    List<AiImage> images = const [],
    String? text,
    String? userHint,
  }) async {
    final provider = await _current();
    return provider.extractPlan(images: images, text: text, userHint: userHint);
  }

  @override
  Future<void> testConnection() async => (await _current()).testConnection();

  Future<AiProvider> _current() async {
    final id = (await _selection.currentProvider()).id;
    final provider = _providers[id];
    if (provider == null) {
      throw AiConfigurationException(
        'Nessuna implementazione per il provider "${id.value}".',
      );
    }
    return provider;
  }
}
