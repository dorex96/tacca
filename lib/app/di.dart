import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/db/object_box.dart';
import '../data/repositories/plan_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/workout_log_repository.dart';
import '../features/history/cubit/history_cubit.dart';
import '../features/plans/cubit/plans_cubit.dart';
import '../features/workout/cubit/resume_session_cubit.dart';
import '../services/ai/ai_provider.dart';
import '../services/ai/ai_selection.dart';
import '../services/ai/model_catalog.dart';
import '../services/ai/providers/anthropic_provider.dart';
import '../services/ai/providers/google_provider.dart';
import '../services/ai/providers/open_router_provider.dart';
import '../services/ai/providers/routing_ai_provider.dart';
import '../services/clipboard/clipboard_service.dart';
import '../services/feedback/session_feedback.dart';
import '../services/images/image_input.dart';
import '../services/images/ocr_service.dart';
import '../services/images/plan_image_store.dart';
import '../services/notifications/session_notifier.dart';
import '../services/timer/timer_engine.dart';
import '../services/wakelock/screen_wake.dart';

/// Composition root dell'app (DI esplicita, nessun service locator).
///
/// Espone i repository come `RepositoryProvider<...Repository>`, costruiti a
/// partire dallo [ObjectBox] store. La UI dipende sempre dalle interfacce
/// repository, mai da [ObjectBox] direttamente.
///
/// [PlansCubit] e [HistoryCubit] vivono qui (non scoped a una singola route)
/// perché i loro elenchi servono sia alla lista sia alle pagine di dettaglio,
/// che nella navigazione di `go_router` sono pagine sorelle nello stack, non
/// genitore/figlio nell'albero widget. `PlanEditorCubit`,
/// `HistoryDetailCubit` e `WorkoutSessionBloc` restano invece scoped alla
/// singola route.
///
/// I servizi della sessione ([TimerEngine], feedback, notifiche, wake lock)
/// sono singoli per tutta l'app: possiedono risorse di piattaforma (player
/// audio, canale notifiche) e una sola sessione può essere attiva per volta.
class AppProviders extends StatelessWidget {
  const AppProviders({
    required this.objectBox,
    required this.aiModelCatalog,
    required this.child,
    super.key,
  });

  final ObjectBox objectBox;

  /// Catalogo dei modelli AI (da `assets/ai/models.json`), caricato in
  /// `main()` come lo Store: da qui in poi la composizione è sincrona.
  final AiModelCatalog aiModelCatalog;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<ObjectBox>.value(value: objectBox),
        RepositoryProvider<PlanRepository>(
          create: (context) => ObjectBoxPlanRepository(objectBox),
        ),
        RepositoryProvider<WorkoutLogRepository>(
          create: (context) => ObjectBoxWorkoutLogRepository(objectBox),
        ),
        RepositoryProvider<TimerEngine>(create: (context) => TimerEngine()),
        RepositoryProvider<SessionFeedback>(
          create: (context) => PluginSessionFeedback(),
        ),
        RepositoryProvider<SessionNotifier>(
          create: (context) => LocalSessionNotifier(),
        ),
        RepositoryProvider<ScreenWake>(
          create: (context) => const PluginScreenWake(),
        ),
        RepositoryProvider<SettingsRepository>(
          create: (context) => SecureSettingsRepository(),
        ),
        RepositoryProvider<AiModelCatalog>.value(value: aiModelCatalog),
        RepositoryProvider<AiSelectionResolver>(
          create: (context) => AiSelectionResolver(
            settings: context.read<SettingsRepository>(),
            catalog: aiModelCatalog,
          ),
        ),
        // Un'implementazione per provider, dietro un unico [AiProvider] che
        // smista in base alla scelta salvata: cubit e pagine non sanno con
        // chi stanno parlando.
        RepositoryProvider<AiProvider>(
          create: (context) {
            final selection = context.read<AiSelectionResolver>();
            return RoutingAiProvider(
              selection: selection,
              providers: {
                AiProviderId.openRouter: OpenRouterProvider(
                  selection: selection,
                ),
                AiProviderId.anthropic: AnthropicProvider(selection: selection),
                AiProviderId.google: GoogleProvider(selection: selection),
              },
            );
          },
        ),
        RepositoryProvider<PlanImageStore>(
          create: (context) => PlanImageStore(),
        ),
        RepositoryProvider<ImageInput>(create: (context) => PickerImageInput()),
        RepositoryProvider<OcrService>(create: (context) => NativeOcrService()),
        RepositoryProvider<ClipboardService>(
          create: (context) => const SystemClipboardService(),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<PlansCubit>(
            create: (context) =>
                PlansCubit(repository: context.read<PlanRepository>()),
          ),
          BlocProvider<HistoryCubit>(
            create: (context) =>
                HistoryCubit(repository: context.read<WorkoutLogRepository>()),
          ),
          BlocProvider<ResumeSessionCubit>(
            create: (context) => ResumeSessionCubit(
              repository: context.read<WorkoutLogRepository>(),
            ),
          ),
        ],
        child: child,
      ),
    );
  }
}
