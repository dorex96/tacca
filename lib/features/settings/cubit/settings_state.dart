import 'package:freezed_annotation/freezed_annotation.dart';

part 'settings_state.freezed.dart';

/// Esito del "test connessione" (RF-08).
enum AiConnectionTestStatus { idle, testing, success, failure }

/// Stato della configurazione AI (RF-08). La key non compare mai qui:
/// lo stato espone solo la sua presenza (RNF-03).
@freezed
sealed class SettingsState with _$SettingsState {
  const factory SettingsState({
    @Default(true) bool isLoading,
    @Default(false) bool hasApiKey,
    String? selectedModelId,
    @Default(AiConnectionTestStatus.idle) AiConnectionTestStatus testStatus,
    String? testErrorMessage,
    String? errorMessage,
  }) = _SettingsState;
}
