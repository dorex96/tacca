import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../../data/entities/workout_plan.dart';
import '../../../l10n/app_localizations.dart';
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

    return Scaffold(
      appBar: AppBar(title: Text(l10n.plansTitle)),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _pickCreationMode(context, l10n),
        icon: const Icon(Icons.add),
        label: Text(l10n.plansNewPlan),
      ),
    );
  }

  /// Nuova scheda: editor manuale (RF-02) o import via AI da foto, immagini
  /// o testo (RF-03).
  Future<void> _pickCreationMode(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    final route = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.sm,
              ),
              child: Text(
                l10n.plansNewPlan,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            _CreationOption(
              icon: Icons.edit_outlined,
              title: l10n.plansNewPlanManual,
              onTap: () => Navigator.of(context).pop('/plans/new'),
            ),
            _CreationOption(
              icon: Icons.auto_awesome_outlined,
              title: l10n.plansNewPlanAi,
              subtitle: l10n.plansNewPlanAiSubtitle,
              onTap: () => Navigator.of(context).pop('/plans/new/import'),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (route != null && context.mounted) context.push(route);
  }
}

/// Voce del pannello di creazione: icona in evidenza, titolo e spiegazione.
class _CreationOption extends StatelessWidget {
  const _CreationOption({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xs,
      ),
      leading: Container(
        height: 44,
        width: 44,
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Icon(icon, color: scheme.onSecondaryContainer),
      ),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
    );
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

    final isSearching = state.searchQuery.trim().isNotEmpty;
    final noSearchResults =
        isSearching &&
        inUse == null &&
        otherActive.isEmpty &&
        filteredArchived.isEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: l10n.plansSearchHint,
            ),
            textInputAction: TextInputAction.search,
            onChanged: cubit.search,
          ),
        ),
        Expanded(
          child: !hasAnyPlan
              ? EmptyState(
                  icon: Icons.fitness_center_outlined,
                  message: l10n.plansEmpty,
                )
              : noSearchResults
              ? EmptyState(
                  icon: Icons.search_off_outlined,
                  message: l10n.plansNoSearchResults,
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.fabClearance,
                  ),
                  children: [
                    if (inUse != null) ...[
                      SectionHeader(label: l10n.plansInUseBadge),
                      _tile(
                        PlanListTile(
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
                    ],
                    if (otherActive.isNotEmpty) ...[
                      SectionHeader(label: l10n.plansSectionActive),
                      for (final plan in otherActive)
                        _tile(
                          PlanListTile(
                            key: ValueKey('plan-${plan.id}'),
                            plan: plan,
                            onOpen: () => context.push('/plans/${plan.id}'),
                            onEdit: () =>
                                context.push('/plans/${plan.id}/edit'),
                            onSetActive: () => cubit.setActivePlan(plan.id),
                            onDuplicate: () => cubit.duplicatePlan(plan.id),
                            onArchiveToggle: () => cubit.archivePlan(plan.id),
                            onDelete: () => cubit.deletePlan(plan.id),
                          ),
                        ),
                    ],
                    if (filteredArchived.isNotEmpty) ...[
                      SectionHeader(label: l10n.plansSectionArchived),
                      for (final plan in filteredArchived)
                        _tile(
                          PlanListTile(
                            key: ValueKey('plan-${plan.id}'),
                            plan: plan,
                            onOpen: () => context.push('/plans/${plan.id}'),
                            onEdit: () =>
                                context.push('/plans/${plan.id}/edit'),
                            onDuplicate: () => cubit.duplicatePlan(plan.id),
                            onArchiveToggle: () => cubit.restorePlan(plan.id),
                            onDelete: () => cubit.deletePlan(plan.id),
                          ),
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  /// Le card non hanno margine proprio (tema): la distanza fra righe la
  /// decide la lista, così resta identica in tutte le sezioni.
  Widget _tile(Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: child,
  );
}
