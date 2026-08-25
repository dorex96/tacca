import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/app_chrome.dart';
import '../design/app_colors.dart';
import '../design/app_radius.dart';
import '../design/app_spacing.dart';
import '../design/app_typography.dart';
import '../design/linear_icons.dart';
import 'linear_icon.dart';

/// Una destinazione della [HomeTabBar].
class HomeTab {
  const HomeTab({required this.icon, required this.label});

  final LinearIconData icon;
  final String label;
}

/// Tab bar flottante: 340×56, raggio 32, fondo inchiostro, con la
/// destinazione attiva in una pillola lime che porta anche l'etichetta.
///
/// Solo la tab attiva è etichettata: è quello che rende leggibile una barra
/// scura alta 56 senza schiacciarci dentro tre testi. Le altre restano icone,
/// e l'etichetta arriva comunque all'accessibilità via [Semantics].
class HomeTabBar extends StatelessWidget {
  const HomeTabBar({
    required this.tabs,
    required this.currentIndex,
    required this.onSelected,
    super.key,
  });

  final List<HomeTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  static const double _width = 340;

  /// Altezza della barra: le pagine della shell la sommano allo spazio che
  /// lasciano in fondo alle liste.
  static const double height = 56;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) => Container(
          width: math.min(_width, constraints.maxWidth),
          height: height,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm + 2,
            0,
            AppSpacing.xl + AppSpacing.xs,
            0,
          ),
          decoration: const BoxDecoration(
            color: AppColors.ink,
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.xl)),
            boxShadow: AppChrome.floating,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < tabs.length; i++)
                // Solo la tab attiva porta l'etichetta, quindi solo lei può
                // diventare troppo larga: è l'unica flessibile.
                if (i == currentIndex)
                  Flexible(
                    child: _Tab(
                      key: ValueKey('home-tab-${tabs[i].label}'),
                      tab: tabs[i],
                      selected: true,
                      onTap: () => onSelected(i),
                    ),
                  )
                else
                  _Tab(
                    key: ValueKey('home-tab-${tabs[i].label}'),
                    tab: tabs[i],
                    selected: false,
                    onTap: () => onSelected(i),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.tab,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final HomeTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final content = selected
        ? Container(
            height: 36,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.card - 1,
              0,
            ),
            decoration: BoxDecoration(
              color: AppColors.lime,
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearIcon(tab.icon, color: AppColors.ink),
                const SizedBox(width: AppSpacing.lg),
                Flexible(
                  child: Text(
                    tab.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.meta.copyWith(color: AppColors.ink),
                  ),
                ),
              ],
            ),
          )
        : LinearIcon(tab.icon, color: AppColors.surface);

    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: SizedBox(
          height: HomeTabBar.height,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: selected ? 0 : AppSpacing.sm,
            ),
            child: Center(child: content),
          ),
        ),
      ),
    );
  }
}
