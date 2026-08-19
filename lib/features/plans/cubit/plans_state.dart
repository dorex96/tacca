import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../data/entities/workout_plan.dart';

part 'plans_state.freezed.dart';

/// Stato dell'archivio schede (RF-01): liste attiva/archiviata già filtrate
/// per [searchQuery], così la UI legge direttamente i getter senza rifiltrare.
@freezed
sealed class PlansState with _$PlansState {
  const PlansState._();

  const factory PlansState({
    @Default(true) bool isLoading,
    @Default([]) List<WorkoutPlan> activePlans,
    @Default([]) List<WorkoutPlan> archivedPlans,
    @Default('') String searchQuery,
    String? errorMessage,
  }) = _PlansState;

  /// La scheda marcata "in uso", se presente (mai tra le archiviate).
  WorkoutPlan? get inUsePlan {
    for (final plan in activePlans) {
      if (plan.isActive) return plan;
    }
    return null;
  }

  List<WorkoutPlan> get filteredActivePlans => _filtered(activePlans);

  List<WorkoutPlan> get filteredArchivedPlans => _filtered(archivedPlans);

  List<WorkoutPlan> _filtered(List<WorkoutPlan> plans) {
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) return plans;
    return plans.where((p) => p.name.toLowerCase().contains(query)).toList();
  }
}
