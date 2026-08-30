import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/entities/workout_log.dart';
import '../../../data/repositories/workout_log_repository.dart';
import 'active_session_state.dart';

/// La sessione aperta, seguita per tutta la vita dell'app.
///
/// È il punto da cui la UI sa che un allenamento è rimasto a metà: la card di
/// ripresa nell'archivio schede, la proposta all'avvio (§8) e il conflitto
/// quando se ne vuole iniziare un'altra leggono tutti da qui.
///
/// Sta **in ascolto** sul repository invece di interrogarlo una volta sola:
/// una sessione si apre e si chiude mentre l'app è viva, e prima di questo
/// una lettura all'avvio era l'unico modo di accorgersene — cioè bisognava
/// chiudere e riaprire l'app per ritrovare la propria sessione.
class ActiveSessionCubit extends Cubit<ActiveSessionState> {
  ActiveSessionCubit({required WorkoutLogRepository repository})
    : _repository = repository,
      super(const ActiveSessionState()) {
    _subscription = _repository.watchInProgress().listen(
      _onSessionChanged,
      // Un errore del database non deve lasciare in giro una proposta di
      // ripresa senza sessione dietro.
      onError: (Object _) => _onSessionChanged(null),
    );
  }

  final WorkoutLogRepository _repository;
  late final StreamSubscription<WorkoutLog?> _subscription;

  /// La proposta di ripresa riguarda solo la sessione che c'era **già**
  /// all'apertura dell'app: quella che l'utente ha appena aperto da sé non va
  /// riproposta appena torna all'archivio.
  bool _firstEmission = true;

  void _onSessionChanged(WorkoutLog? log) {
    final foundAtStartup = _firstEmission && log != null;
    _firstEmission = false;
    emit(ActiveSessionState(log: log, promptPending: foundAtStartup));
  }

  /// La proposta è stata mostrata: non va ripetuta. La sessione resta aperta
  /// e resta visibile nell'archivio — "più tardi" non la chiude.
  void dismissPrompt() {
    if (state.promptPending) emit(state.copyWith(promptPending: false));
  }

  /// La sessione aperta **adesso**, riletta dal repository.
  ///
  /// Lo stato osservato arriva un istante dopo la scrittura, e la decisione
  /// "una sola sessione per volta" non può dipendere da quell'istante: chi
  /// sta per aprirne una nuova chiede qui.
  WorkoutLog? currentSession() {
    try {
      return _repository.findInProgress();
    } catch (_) {
      return state.log;
    }
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
