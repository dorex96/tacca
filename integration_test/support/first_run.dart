import 'package:flutter_test/flutter_test.dart';

/// Al primo avvio su un device pulito l'app mostra la manleva bloccante
/// (`LegalGate`): accettarla è il primo gesto anche per l'utente vero. Su un
/// device che l'ha già accettata non compare nulla, quindi il passo è
/// condizionale e i flussi restano rieseguibili.
Future<void> acceptLegalNoticeIfShown(WidgetTester tester) async {
  final accept = find.text('Accetto e continuo');
  if (accept.evaluate().isEmpty) return;

  await tester.tap(accept);
  await tester.pumpAndSettle();
}
