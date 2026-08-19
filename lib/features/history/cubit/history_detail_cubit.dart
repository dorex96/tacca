import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/entities/workout_log.dart';
import '../../../data/repositories/workout_log_repository.dart';

/// Dettaglio di una singola sessione (RF-07).
///
/// Carica il log per id invece di pescarlo dalla lista dello storico: la
/// pagina è raggiungibile anche subito dopo la chiusura di una sessione,
/// prima che lo stream dell'elenco abbia riemesso.
///
/// Lo stato è direttamente il log (`null` = non trovato o eliminato): non
/// serve altro, e l'entity è già il modello di dominio (ADR-01).
class HistoryDetailCubit extends Cubit<WorkoutLog?> {
  HistoryDetailCubit({
    required WorkoutLogRepository repository,
    required int logId,
  }) : _repository = repository,
       super(null) {
    emit(_repository.getById(logId));
  }

  final WorkoutLogRepository _repository;

  void delete() {
    final log = state;
    if (log == null) return;
    _repository.deleteLog(log.id);
    emit(null);
  }
}
