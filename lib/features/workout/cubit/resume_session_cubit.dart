import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/entities/workout_log.dart';
import '../../../data/repositories/workout_log_repository.dart';

/// Sessione rimasta aperta da proporre alla ripresa (§8): lo stato è il log
/// da riprendere, `null` quando non ce n'è uno o l'utente ha rinviato.
///
/// Esiste perché la UI non interroga mai i repository da sé: il controllo
/// all'avvio passa comunque da un Cubit.
class ResumeSessionCubit extends Cubit<WorkoutLog?> {
  ResumeSessionCubit({required WorkoutLogRepository repository})
    : _repository = repository,
      super(null);

  final WorkoutLogRepository _repository;

  /// Cerca una sessione interrotta. Va chiamata all'apertura dell'app, dopo
  /// il primo frame, così l'emissione arriva a un listener già montato.
  void check() {
    try {
      emit(_repository.findInProgress());
    } catch (_) {
      emit(null);
    }
  }

  /// L'utente ha scelto "più tardi" oppure ha aperto la sessione: la proposta
  /// non va ripetuta.
  void dismiss() => emit(null);
}
