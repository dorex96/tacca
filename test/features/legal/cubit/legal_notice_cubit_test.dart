import 'package:tacca/core/constants.dart';
import 'package:tacca/features/legal/cubit/legal_notice_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fakes.dart';

/// Portachiavi che non risponde: leggere o scrivere la preferenza esplode.
class _BrokenSettingsRepository extends FakeSettingsRepository {
  @override
  Future<int?> getAcceptedLegalNoticeVersion() async {
    throw Exception('portachiavi non disponibile');
  }

  @override
  Future<void> setAcceptedLegalNoticeVersion(int version) async {
    throw Exception('portachiavi non disponibile');
  }
}

void main() {
  test('al primo avvio la manleva va accettata', () async {
    final cubit = LegalNoticeCubit(settings: FakeSettingsRepository());

    expect(cubit.state, LegalNoticeStatus.unknown);
    await pumpEventQueue();

    expect(cubit.state, LegalNoticeStatus.pending);
  });

  test('chi ha accettato la versione corrente non rivede nulla', () async {
    final settings = FakeSettingsRepository(
      acceptedLegalNoticeVersion: AppConstants.legalNoticeVersion,
    );
    final cubit = LegalNoticeCubit(settings: settings);
    await pumpEventQueue();

    expect(cubit.state, LegalNoticeStatus.accepted);
  });

  test('una versione precedente dei termini torna da accettare', () async {
    final settings = FakeSettingsRepository(
      acceptedLegalNoticeVersion: AppConstants.legalNoticeVersion - 1,
    );
    final cubit = LegalNoticeCubit(settings: settings);
    await pumpEventQueue();

    expect(cubit.state, LegalNoticeStatus.pending);
  });

  test('accettare salva la versione corrente', () async {
    final settings = FakeSettingsRepository();
    final cubit = LegalNoticeCubit(settings: settings);
    await pumpEventQueue();

    await cubit.accept();

    expect(cubit.state, LegalNoticeStatus.accepted);
    expect(
      settings.acceptedLegalNoticeVersion,
      AppConstants.legalNoticeVersion,
    );
  });

  test('se la lettura fallisce la manleva si rilegge', () async {
    final cubit = LegalNoticeCubit(settings: _BrokenSettingsRepository());
    await pumpEventQueue();

    expect(cubit.state, LegalNoticeStatus.pending);
  });

  test("un salvataggio fallito non blocca l'utente", () async {
    final cubit = LegalNoticeCubit(settings: _BrokenSettingsRepository());
    await pumpEventQueue();

    await cubit.accept();

    expect(cubit.state, LegalNoticeStatus.accepted);
  });
}
