import 'package:flutter/material.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/square_icon_button.dart';
import '../../../l10n/app_localizations.dart';
import '../widgets/legal_notice_body.dart';

/// Impostazioni → Termini e responsabilità: la stessa manleva accettata al
/// primo avvio, rileggibile in qualsiasi momento. Qui non si accetta niente,
/// si legge e basta.
class LegalNoticePage extends StatelessWidget {
  const LegalNoticePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AppScaffold(
      leading: const AppBackButton(),
      title: l10n.legalPageTitle,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.tabBarClearance,
        ),
        children: const [LegalNoticeBody()],
      ),
    );
  }
}
