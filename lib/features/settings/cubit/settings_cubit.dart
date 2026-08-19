import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/errors/ai_exception.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../services/ai/ai_provider.dart';
import '../../../services/ai/model_catalog.dart';
import 'settings_state.dart';

/// Configurazione AI (RF-08): key OpenRouter, scelta del modello dal
/// catalogo JSON, test connessione.
class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit({
    required SettingsRepository settings,
    required AiProvider provider,
    required this.catalog,
  }) : _settings = settings,
       _provider = provider,
       super(const SettingsState()) {
    _load();
  }

  final SettingsRepository _settings;
  final AiProvider _provider;

  /// Catalogo dei modelli selezionabili (da `assets/ai/models.json`),
  /// immutabile per la vita del cubit: la UI lo legge da qui.
  final AiModelCatalog catalog;

  Future<void> _load() async {
    try {
      final apiKey = await _settings.getOpenRouterApiKey();
      final modelId = await _settings.getOpenRouterModelId();
      emit(
        state.copyWith(
          isLoading: false,
          hasApiKey: apiKey != null,
          selectedModelId: _knownModelIdOrDefault(modelId),
        ),
      );
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> saveApiKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return;
    await _settings.setOpenRouterApiKey(trimmed);
    emit(
      state.copyWith(
        hasApiKey: true,
        testStatus: AiConnectionTestStatus.idle,
        testErrorMessage: null,
      ),
    );
  }

  Future<void> removeApiKey() async {
    await _settings.setOpenRouterApiKey(null);
    emit(
      state.copyWith(
        hasApiKey: false,
        testStatus: AiConnectionTestStatus.idle,
        testErrorMessage: null,
      ),
    );
  }

  Future<void> selectModel(String modelId) async {
    await _settings.setOpenRouterModelId(modelId);
    emit(state.copyWith(selectedModelId: modelId));
  }

  Future<void> testConnection() async {
    emit(
      state.copyWith(
        testStatus: AiConnectionTestStatus.testing,
        testErrorMessage: null,
      ),
    );
    try {
      await _provider.testConnection();
      emit(state.copyWith(testStatus: AiConnectionTestStatus.success));
    } on AiException catch (e) {
      emit(
        state.copyWith(
          testStatus: AiConnectionTestStatus.failure,
          testErrorMessage: e.message,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          testStatus: AiConnectionTestStatus.failure,
          testErrorMessage: e.toString(),
        ),
      );
    }
  }

  void dismissError() => emit(state.copyWith(errorMessage: null));

  /// Un id salvato che non esiste più nel catalogo (JSON modificato) torna
  /// al default: la UI non deve mostrare una voce fantasma nel dropdown.
  String _knownModelIdOrDefault(String? modelId) {
    if (modelId != null && catalog.byId(modelId) != null) return modelId;
    return catalog.defaultModelId;
  }
}
