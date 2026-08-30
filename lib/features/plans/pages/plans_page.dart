import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/linear_icons.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/section_header.dart';
import '../../../data/entities/workout_plan.dart';
import '../../../l10n/app_localizations.dart';
import '../../workout/widgets/active_session_card.dart';
import '../cubit/plans_cubit.dart';
import '../cubit/plans_state.dart';
import '../widgets/plan_list_tile.dart';

/// Archivio schede (RF-01): ricerca, scheda in uso in evidenza, sezioni
/// attive/archiviate, azioni di lista.
class PlansPage extends StatelessWidget {
  const PlansPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AppScaffold(
      title: l10n.plansTitle,
      // La sessione rimasta aperta sta sopra la ricerca e non scorre con la
      // lista: è la strada per rientrare nell'allenamento lasciato a metà, e
      // deve essere lì appena si apre l'app.
      header: Padding(
        padding: AppSpacing.pageInsets,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ActiveSessionBanner(),
            PlanSearchField(onChanged: context.read<PlansCubit>().search),
          ],
        ),
      ),
      dock: PillButton(
        label: l10n.plansNewPlan,
        icon: AppIcons.add,
        onPressed: () => _pickCreationMode(context, l10n),
      ),
      aboveTabBar: true,
      body: BlocConsumer<PlansCubit, PlansState>(
        listenWhen: (previous, current) =>
            previous.errorMessage != current.errorMessage,
        listener: (context, state) {
          if (state.errorMessage != null) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(state.errorMessage!)));
            context.read<PlansCubit>().dismissError();
          }
        },
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          return _PlansListBody(state: state);
        },
      ),
    );
  }

  /// Nuova scheda: editor manuale (RF-02), import via AI con la propria key,
  /// oppure lo stesso import fatto passare da una chat AI qualsiasi (RF-03).
  ///
  /// La lime è su quest'ultima: è l'unica delle tre strade con l'AI che
  /// funziona su un'app appena installata, senza key e senza account presso
  /// nessuno. Le altre due restano neutre — nel pannello la lime è una sola.
  Future<void> _pickCreationMode(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    final route = await showAppSheet<String>(
      context,
      builder: (context) => AppSheet(
        title: l10n.plansNewPlan,
        children: [
          SheetOption(
            icon: AppIcons.pencil,
            title: l10n.plansNewPlanManual,
            onTap: () => Navigator.of(context).pop('/plans/new'),
          ),
          const SizedBox(height: AppSpacing.sm),
          SheetOption(
            icon: AppIcons.gallery,
            title: l10n.plansNewPlanAi,
            subtitle: l10n.plansNewPlanAiSubtitle,
            onTap: () => Navigator.of(context).pop('/plans/new/import'),
          ),
          const SizedBox(height: AppSpacing.sm),
          SheetOption(
            icon: AppIcons.cpu,
            title: l10n.plansNewPlanChat,
            subtitle: l10n.plansNewPlanChatSubtitle,
            highlighted: true,
            onTap: () => Navigator.of(context).pop('/plans/new/import/paste'),
          ),
        ],
      ),
    );
    if (route != null && context.mounted) context.push(route);
  }
}

class _PlansListBody extends StatelessWidget {
  const _PlansListBody({required this.state});

  final PlansState state;

  WorkoutPlan? _firstActive(List<WorkoutPlan> plans) {
    for (final plan in plans) {
      if (plan.isActive) return plan;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<PlansCubit>();

    final hasAnyPlan =
        state.activePlans.isNotEmpty || state.archivedPlans.isNotEmpty;

    final filteredActive = state.filteredActivePlans;
    final filteredArchived = state.filteredArchivedPlans;
    final inUse = _firstActive(filteredActive);
    final otherActive = filteredActive.where((p) => p.id != inUse?.id).toList();

    if (!hasAnyPlan) {
      return EmptyState(icon: AppIcons.noteAdd, message: l10n.plansEmpty);
    }
    if (inUse == null && otherActive.isEmpty && filteredArchived.isEmpty) {
      return EmptyState(
        icon: AppIcons.search,
        message: l10n.plansNoSearchResults,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.dockClearance,
      ),
      children: [
        if (inUse != null)
          Section(
            label: l10n.plansInUseBadge,
            child: PlanListTile(
              key: ValueKey('plan-${inUse.id}'),
              plan: inUse,
              highlighted: true,
              onOpen: () => context.push('/plans/${inUse.id}'),
              onEdit: () => context.push('/plans/${inUse.id}/edit'),
              onDuplicate: () => cubit.duplicatePlan(inUse.id),
              onArchiveToggle: () => cubit.archivePlan(inUse.id),
              onDelete: () => cubit.deletePlan(inUse.id),
            ),
          ),
        if (otherActive.isNotEmpty)
          Section(
            label: l10n.plansSectionActive,
            child: _rows([
              for (final plan in otherActive)
                PlanListTile(
                  key: ValueKey('plan-${plan.id}'),
                  plan: plan,
                  onOpen: () => context.push('/plans/${plan.id}'),
                  onEdit: () => context.push('/plans/${plan.id}/edit'),
                  onSetActive: () => cubit.setActivePlan(plan.id),
                  onDuplicate: () => cubit.duplicatePlan(plan.id),
                  onArchiveToggle: () => cubit.archivePlan(plan.id),
                  onDelete: () => cubit.deletePlan(plan.id),
                ),
            ]),
          ),
        if (filteredArchived.isNotEmpty)
          Section(
            label: l10n.plansSectionArchived,
            child: _rows([
              for (final plan in filteredArchived)
                PlanListTile(
                  key: ValueKey('plan-${plan.id}'),
                  plan: plan,
                  onOpen: () => context.push('/plans/${plan.id}'),
                  onEdit: () => context.push('/plans/${plan.id}/edit'),
                  onDuplicate: () => cubit.duplicatePlan(plan.id),
                  onArchiveToggle: () => cubit.restorePlan(plan.id),
                  onDelete: () => cubit.deletePlan(plan.id),
                ),
            ]),
          ),
      ],
    );
  }

  /// Le righe non hanno margine proprio: la distanza fra loro la decide la
  /// sezione, così resta identica ovunque.
  Widget _rows(List<Widget> tiles) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          tiles[i],
        ],
      ],
    );
  }
}
