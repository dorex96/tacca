import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../data/entities/workout_log.dart';

part 'active_session_state.freezed.dart';

/// La sessione aperta, se c'è: al più una in tutta l'app (RF-06).
///
/// [promptPending] non è "c'è una sessione", è "va ancora proposta": la
/// proposta di ripresa (§8) riguarda solo la sessione trovata all'apertura
/// dell'app, mentre [log] resta popolato finché la sessione è aperta, perché
/// è quello che disegna la card di ripresa nell'archivio.
@freezed
sealed class ActiveSessionState with _$ActiveSessionState {
  const ActiveSessionState._();

  const factory ActiveSessionState({
    WorkoutLog? log,
    @Default(false) bool promptPending,
  }) = _ActiveSessionState;

  bool get hasSession => log != null;
}
