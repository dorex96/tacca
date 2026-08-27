import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/design/linear_icons.dart';
import '../../../core/widgets/linear_icon.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/clipboard/clipboard_service.dart';
import '../../../services/links/link_opener.dart';

/// Il testo della manleva.
///
/// Sta in un widget solo perché le due schermate che lo mostrano — l'avviso
/// bloccante del primo avvio e la voce in Impostazioni — devono dire
/// esattamente la stessa cosa: due copie divergenti di una manleva sono un
/// problema, non un dettaglio di presentazione.
class LegalNoticeBody extends StatelessWidget {
  const LegalNoticeBody({this.highlightIntro = false, super.key});

  /// True nell'avviso del primo avvio: l'introduzione diventa la card lime
  /// della schermata — l'unico elemento accentato, come vuole il design.
  /// False in Impostazioni, dove il lime ce l'ha già la riga dell'elenco.
  final bool highlightIntro;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (highlightIntro)
          SurfaceCard(
            color: AppColors.lime,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LinearIcon(
                  AppIcons.shield,
                  size: 20,
                  color: AppColors.ink,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    l10n.legalNoticeIntro,
                    // Sopra il lime il testo è sempre inchiostro.
                    style: AppTypography.paragraph.copyWith(
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Text(l10n.legalNoticeIntro, style: AppTypography.paragraph),
        const SizedBox(height: AppSpacing.card),
        _LegalPoint(
          title: l10n.legalNoticeMedicalTitle,
          body: l10n.legalNoticeMedicalBody,
        ),
        const SizedBox(height: AppSpacing.sm),
        _LegalPoint(
          title: l10n.legalNoticeRiskTitle,
          body: l10n.legalNoticeRiskBody,
        ),
        const SizedBox(height: AppSpacing.sm),
        _LegalPoint(
          title: l10n.legalNoticeContentTitle,
          body: l10n.legalNoticeContentBody,
        ),
        const SizedBox(height: AppSpacing.sm),
        _LegalPoint(
          title: l10n.legalNoticeImportTitle,
          body: l10n.legalNoticeImportBody,
        ),
        const SizedBox(height: AppSpacing.sm),
        _LegalPoint(
          title: l10n.legalNoticeWarrantyTitle,
          body: l10n.legalNoticeWarrantyBody,
        ),
        const SizedBox(height: AppSpacing.card),
        const TermsLinkCard(),
      ],
    );
  }
}

/// Un punto della manleva: titolo breve e la frase che lo spiega.
class _LegalPoint extends StatelessWidget {
  const _LegalPoint({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.cardTitle),
          const SizedBox(height: AppSpacing.sm),
          Text(body, style: AppTypography.paragraph),
        ],
      ),
    );
  }
}

/// Riga che porta ai termini e condizioni completi.
///
/// Il testo integrale sta sul sito, non nell'app: si apre nel **browser di
/// sistema** ([LinkOpener]), non in una WebView incorporata. Se nessun
/// browser risponde, il link finisce negli appunti — l'utente resta comunque
/// in grado di leggerlo.
class TermsLinkCard extends StatelessWidget {
  const TermsLinkCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SurfaceCard(
      onTap: () => _openTerms(context),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.card,
        AppSpacing.lg,
        AppSpacing.card,
        AppSpacing.lg,
      ),
      child: Row(
        children: [
          const LinearIcon(AppIcons.shield, size: 20, color: AppColors.muted),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.legalTermsLinkTitle, style: AppTypography.rowStrong),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.legalTermsLinkSubtitle,
                  style: AppTypography.paragraphSmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const LinearIcon(
            AppIcons.chevronRight,
            size: 20,
            color: AppColors.muted,
          ),
        ],
      ),
    );
  }

  Future<void> _openTerms(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final opener = context.read<LinkOpener>();
    final clipboard = context.read<ClipboardService>();

    final opened = await opener.open(Uri.parse(AppConstants.termsUrl));
    if (opened) return;

    await clipboard.write(AppConstants.termsUrl);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.legalTermsLinkCopied)));
  }
}
