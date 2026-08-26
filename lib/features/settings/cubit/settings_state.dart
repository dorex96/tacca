import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../services/ai/ai_provider.dart';

part 'settings_state.freezed.dart';

/// Esito del "test connessione" (RF-08).
enum AiConnectionTestStatus { idle, testing, success, failure }

/// Stato della configurazione AI (RF-08). La key non compare mai qui:
/// lo stato espone solo la sua presenza (RNF-03).
///
/// Key e modello sono quelli del provider selezionato: cambiando provider
/// cambiano entrambi, perché ogni provider ha le sue impostazioni salvate.
@freezed
sealed class SettingsState with _$SettingsState {
  const factory SettingsState({
    @Default(true) bool isLoading,
    AiProviderId? selectedProviderId,
    @Default(false) bool hasApiKey,
    String? selectedModelId,
    @Default(AiConnectionTestStatus.idle) AiConnectionTestStatus testStatus,
    String? testErrorMessage,
    String? errorMessage,
  }) = _SettingsState;
}
