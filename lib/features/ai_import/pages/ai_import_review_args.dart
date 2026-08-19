import '../../../data/entities/workout_plan.dart';

/// Argomenti della route di revisione `/plans/new/review`: la bozza proposta
/// dall'AI (non ancora persistita), con le immagini originali già allegate
/// in `draft.imagePaths`.
class AiImportReviewArgs {
  final WorkoutPlan draft;

  const AiImportReviewArgs({required this.draft});
}
