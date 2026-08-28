import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/design/app_colors.dart';
import '../core/design/linear_icons.dart';
import '../core/widgets/app_scaffold.dart';
import '../core/widgets/confirm_dialog.dart';
import '../core/widgets/home_tab_bar.dart';
import '../data/entities/workout_log.dart';
import '../data/repositories/plan_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/workout_log_repository.dart';
import '../features/ai_import/cubit/ai_import_cubit.dart';
import '../features/ai_import/cubit/ai_paste_import_cubit.dart';
import '../features/ai_import/pages/ai_import_page.dart';
import '../features/ai_import/pages/ai_import_review_args.dart';
import '../features/ai_import/pages/ai_paste_import_page.dart';
import '../features/history/cubit/history_detail_cubit.dart';
import '../features/history/pages/history_detail_page.dart';
import '../features/history/pages/history_page.dart';
import '../features/legal/pages/legal_notice_page.dart';
import '../features/plans/cubit/plan_editor_cubit.dart';
import '../features/plans/pages/plan_detail_page.dart';
import '../features/plans/pages/plan_editor_page.dart';
import '../features/plans/pages/plan_images_page.dart';
import '../features/plans/pages/plans_page.dart';
import '../features/settings/cubit/settings_cubit.dart';
import '../features/settings/pages/ai_settings_page.dart';
import '../features/settings/pages/settings_page.dart';
import '../features/workout/bloc/workout_session_bloc.dart';
import '../features/workout/bloc/workout_session_event.dart';
import '../features/workout/cubit/resume_session_cubit.dart';
import '../features/workout/pages/workout_session_page.dart';
import '../l10n/app_localizations.dart';
import '../services/ai/ai_provider.dart';
import '../services/ai/ai_selection.dart';
import '../services/clipboard/clipboard_service.dart';
import '../services/feedback/session_feedback.dart';
import '../services/images/image_input.dart';
import '../services/images/ocr_service.dart';
import '../services/images/plan_image_store.dart';
import '../services/notifications/session_notifier.dart';
import '../services/timer/timer_engine.dart';
import '../services/wakelock/screen_wake.dart';

/// Costruisce il router dell'app: una [StatefulShellRoute.indexedStack] con
/// tre rami (schede, storico, impostazioni) sotto una bottom navigation
/// condivisa. Ogni ramo mantiene il proprio stack di navigazione.
///
/// Dettaglio, editor, sessione e dettaglio sessione sono route di primo
/// livello (fuori dalla shell, come `/workout/:logId` in §8 dell'analisi
/// tecnica): sono pagine a schermo intero, la bottom nav non deve competere
/// con form, timer e tastiera.
GoRouter createRouter() {
  return GoRouter(
    initialLocation: '/plans',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            _HomeShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/plans',
                builder: (context, state) => const PlansPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/history',
                builder: (context, state) => const HistoryPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsPage(),
                routes: [
                  GoRoute(
                    path: 'ai',
                    builder: (context, state) => BlocProvider(
                      create: (context) => SettingsCubit(
                        settings: context.read<SettingsRepository>(),
                        provider: context.read<AiProvider>(),
                        selection: context.read<AiSelectionResolver>(),
                      ),
                      child: const AiSettingsPage(),
                    ),
                  ),
                  // La manleva accettata al primo avvio, rileggibile quando
                  // si vuole.
                  GoRoute(
                    path: 'legal',
                    builder: (context, state) => const LegalNoticePage(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/plans/new',
        builder: (context, state) => BlocProvider(
          create: (context) => PlanEditorCubit.create(
            repository: context.read<PlanRepository>(),
          ),
          child: const PlanEditorPage(),
        ),
      ),
      // Import AI da foto/galleria/testo (RF-03). Fuori dalla shell come le
      // altre pagine di lavoro a schermo intero.
      GoRoute(
        path: '/plans/new/import',
        builder: (context, state) => BlocProvider(
          create: (context) => AiImportCubit(
            provider: context.read<AiProvider>(),
            imageInput: context.read<ImageInput>(),
            imageStore: context.read<PlanImageStore>(),
            selection: context.read<AiSelectionResolver>(),
            ocr: context.read<OcrService>(),
          ),
          child: const AiImportPage(),
        ),
      ),
      // Lo stesso import, ma con l'AI fuori dall'app: l'utente porta il
      // prompt nella chat che preferisce e riporta indietro la risposta
      // (RF-03). Nessuna key, nessuna rete: qui non c'è AiProvider.
      GoRoute(
        path: '/plans/new/import/paste',
        builder: (context, state) => BlocProvider(
          create: (context) => AiPasteImportCubit(
            imageInput: context.read<ImageInput>(),
            imageStore: context.read<PlanImageStore>(),
            ocr: context.read<OcrService>(),
            clipboard: context.read<ClipboardService>(),
          ),
          child: const AiPasteImportPage(),
        ),
      ),
      // Revisione della proposta AI: l'editor manuale (RF-02) su una bozza
      // non ancora persistita. Il salvataggio è sempre esplicito (RF-03).
      GoRoute(
        path: '/plans/new/review',
        builder: (context, state) {
          final args = state.extra! as AiImportReviewArgs;
          return BlocProvider(
            create: (context) => PlanEditorCubit.draft(
              repository: context.read<PlanRepository>(),
              draft: args.draft,
            ),
            child: const PlanEditorPage(),
          );
        },
      ),
      // Immagini originali allegate a una scheda (RF-03).
      GoRoute(
        path: '/plan-images',
        builder: (context, state) =>
            PlanImagesPage(imagePaths: state.extra! as List<String>),
      ),
      GoRoute(
        path: '/plans/:id',
        builder: (context, state) =>
            PlanDetailPage(planId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/plans/:id/edit',
        builder: (context, state) => BlocProvider(
          create: (context) => PlanEditorCubit.edit(
            repository: context.read<PlanRepository>(),
            planId: int.parse(state.pathParameters['id']!),
          ),
          child: const PlanEditorPage(),
        ),
      ),
      // Nuova sessione: il log non esiste ancora, lo crea il Bloc a partire
      // da scheda e giorno scelti (§5.1, evento SessionStarted).
      GoRoute(
        path: '/workout/new',
        builder: (context, state) {
          final planId = int.parse(state.uri.queryParameters['planId']!);
          final dayId = int.parse(state.uri.queryParameters['dayId']!);
          return BlocProvider(
            create: (context) =>
                _createSessionBloc(context)
                  ..add(SessionStarted(planId: planId, dayId: dayId)),
            child: const WorkoutSessionPage(),
          );
        },
      ),
      GoRoute(
        path: '/workout/:logId',
        builder: (context, state) {
          final logId = int.parse(state.pathParameters['logId']!);
          return BlocProvider(
            create: (context) =>
                _createSessionBloc(context)..add(SessionResumed(logId)),
            child: const WorkoutSessionPage(),
          );
        },
      ),
      GoRoute(
        path: '/history/:logId',
        builder: (context, state) => BlocProvider(
          create: (context) => HistoryDetailCubit(
            repository: context.read<WorkoutLogRepository>(),
            logId: int.parse(state.pathParameters['logId']!),
          ),
          child: const HistoryDetailPage(),
        ),
      ),
    ],
  );
}

WorkoutSessionBloc _createSessionBloc(BuildContext context) {
  return WorkoutSessionBloc(
    planRepository: context.read<PlanRepository>(),
    logRepository: context.read<WorkoutLogRepository>(),
    timerEngine: context.read<TimerEngine>(),
    feedback: context.read<SessionFeedback>(),
    notifier: context.read<SessionNotifier>(),
    screenWake: context.read<ScreenWake>(),
  );
}

/// Radice delle tre schermate della shell: il corpo è lo `IndexedStack` dei
/// rami e sopra ci galleggia la tab bar del restyling (toccare una
/// destinazione cambia ramo, ri-tap = pop allo stack root).
///
/// È anche il punto in cui, dopo il primo frame, si verifica se esiste una
/// sessione rimasta aperta da riprendere (§8).
class _HomeShell extends StatefulWidget {
  const _HomeShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ResumeSessionCubit>().check();
    });
  }

  void _onDestinationSelected(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // La tab bar del restyling galleggia *sopra* il contenuto: sta nello
    // Stack della shell, non in `bottomNavigationBar`, e le pagine le
    // lasciano spazio in fondo alle liste (AppSpacing.tabBarClearance).
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          BlocListener<ResumeSessionCubit, WorkoutLog?>(
            listenWhen: (previous, current) =>
                previous == null && current != null,
            listener: (context, log) => _askToResume(context, l10n, log!),
            child: widget.navigationShell,
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AppDock(
              child: HomeTabBar(
                currentIndex: widget.navigationShell.currentIndex,
                onSelected: _onDestinationSelected,
                tabs: [
                  HomeTab(icon: AppIcons.noteAdd, label: l10n.navPlans),
                  HomeTab(icon: AppIcons.calendar, label: l10n.navHistory),
                  HomeTab(icon: AppIcons.settings, label: l10n.navSettings),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _askToResume(
    BuildContext context,
    AppLocalizations l10n,
    WorkoutLog log,
  ) async {
    final cubit = context.read<ResumeSessionCubit>();
    final resume = await showConfirmDialog(
      context,
      title: l10n.workoutResumeTitle,
      message: l10n.workoutResumeBody(
        log.planNameSnapshot,
        log.dayLabelSnapshot,
        log.startedAt,
      ),
      confirmLabel: l10n.workoutResumeConfirm,
      cancelLabel: l10n.workoutResumeDismiss,
    );

    cubit.dismiss();
    if (resume && context.mounted) {
      context.push('/workout/${log.id}');
    }
  }
}
