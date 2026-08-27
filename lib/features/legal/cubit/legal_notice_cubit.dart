import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants.dart';
import '../../../data/repositories/settings_repository.dart';

/// Stato dell'informativa legale.
enum LegalNoticeStatus {
  /// La preferenza non è ancora stata letta: non si sa se mostrarla.
  unknown,

  /// Da accettare: l'utente non ha mai accettato, oppure ha accettato una
  /// versione precedente dei termini.
  pending,

  /// Accettata: l'app può partire.
  accepted,
}

/// Manleva del primo avvio: dice se l'informativa va mostrata e registra
/// l'accettazione.
///
/// L'accettazione è **versionata** ([AppConstants.legalNoticeVersion]): non
/// salva un booleano ma il numero di versione, così alzando la costante
/// l'avviso ricompare a chi aveva accettato la versione vecchia.
///
/// Un errore di lettura del secure storage vale "mai accettato": è il default
/// prudente — al massimo si rilegge un avviso già letto.
class LegalNoticeCubit extends Cubit<LegalNoticeStatus> {
  LegalNoticeCubit({required SettingsRepository settings})
    : _settings = settings,
      super(LegalNoticeStatus.unknown) {
    _load();
  }

  final SettingsRepository _settings;

  Future<void> _load() async {
    int? accepted;
    try {
      accepted = await _settings.getAcceptedLegalNoticeVersion();
    } on Exception {
      accepted = null;
    }
    if (isClosed) return;
    emit(_statusFor(accepted));
  }

  /// Registra l'accettazione della versione corrente e sblocca l'app.
  Future<void> accept() async {
    try {
      await _settings.setAcceptedLegalNoticeVersion(
        AppConstants.legalNoticeVersion,
      );
    } on Exception {
      // Se il salvataggio fallisce l'avviso tornerà al prossimo avvio:
      // ripeterlo è meno grave che lasciare l'utente bloccato qui.
    }
    if (isClosed) return;
    emit(LegalNoticeStatus.accepted);
  }

  static LegalNoticeStatus _statusFor(int? acceptedVersion) {
    if (acceptedVersion == null) return LegalNoticeStatus.pending;
    return acceptedVersion >= AppConstants.legalNoticeVersion
        ? LegalNoticeStatus.accepted
        : LegalNoticeStatus.pending;
  }
}
