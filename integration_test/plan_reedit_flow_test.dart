import 'package:app_palestra/app/app.dart';
import 'package:app_palestra/app/di.dart';
import 'package:app_palestra/data/db/object_box.dart';
import 'package:app_palestra/services/ai/model_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Riproduce dal vivo la segnalazione: creare una scheda, salvarla, RIAPRIRLA
// in modifica, aggiungere un giorno, un blocco standard sul nuovo giorno e
// due esercizi, salvare di nuovo: gli esercizi devono comparire nel
// dettaglio. A differenza di plans_flow_test.dart (tutto in un'unica sessione
// di editor "nuova scheda"), qui il blocco/esercizi vengono aggiunti in una
// SECONDA sessione di editor su una scheda GIA' persistita.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'riapertura in modifica: giorno+blocco+esercizi aggiunti dopo il primo salvataggio compaiono nel dettaglio',
    (tester) async {
      final objectBox = await ObjectBox.open();
      final aiModelCatalog = await AiModelCatalog.load();
      await tester.pumpWidget(
        AppProviders(
          objectBox: objectBox,
          aiModelCatalog: aiModelCatalog,
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();

      final planName = 'Test reedit ${DateTime.now().millisecondsSinceEpoch}';

      // 1. Crea la scheda con solo il nome e salva (prima sessione di editor).
      await tester.tap(find.text('Nuova scheda'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editor manuale'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('plan-name')), planName);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      expect(find.text(planName), findsOneWidget);

      // 2. Riapri la scheda appena creata in modifica (SECONDA sessione di editor).
      await tester.tap(find.text(planName));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      // 3. Aggiungi un secondo giorno.
      await tester.tap(find.text('Aggiungi giorno'));
      await tester.pumpAndSettle();
      expect(find.text('Giorno B'), findsOneWidget);

      // 4. Aggiungi un blocco Standard sul giorno B (ora selezionato).
      await tester.tap(find.text('Aggiungi blocco'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Standard'));
      await tester.pumpAndSettle();

      // 5. Espandi la card del blocco appena creato.
      await tester.tap(find.text('Standard'));
      await tester.pumpAndSettle();

      // 6. Aggiungi due esercizi.
      final addExerciseButton = find.text('Aggiungi esercizio');
      await tester.ensureVisible(addExerciseButton);
      await tester.pumpAndSettle();
      await tester.tap(addExerciseButton);
      await tester.pumpAndSettle();
      await tester.ensureVisible(addExerciseButton);
      await tester.pumpAndSettle();
      await tester.tap(addExerciseButton);
      await tester.pumpAndSettle();

      final exerciseNameFields = find.widgetWithText(
        TextFormField,
        'Esercizio',
      );
      expect(exerciseNameFields, findsNWidgets(2));

      await tester.ensureVisible(exerciseNameFields.at(0));
      await tester.enterText(exerciseNameFields.at(0), 'Squat');
      await tester.pumpAndSettle();
      await tester.ensureVisible(exerciseNameFields.at(1));
      await tester.enterText(exerciseNameFields.at(1), 'Affondi');
      await tester.pumpAndSettle();

      // 7. Salva.
      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      // 8. Riapri il dettaglio: entrambi gli esercizi devono comparire su Giorno B.
      await tester.tap(find.text(planName));
      await tester.pumpAndSettle();

      expect(find.text('Giorno B'), findsOneWidget);
      expect(
        find.text('Squat'),
        findsOneWidget,
        reason: 'primo esercizio mancante nel dettaglio',
      );
      expect(
        find.text('Affondi'),
        findsOneWidget,
        reason: 'secondo esercizio mancante nel dettaglio',
      );

      // 9. Pulizia.
      await tester.tap(find.byWidgetPredicate((w) => w is PopupMenuButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elimina'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Elimina'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(planName), findsNothing);
    },
  );
}
