import 'package:tacca/app/app.dart';
import 'package:tacca/app/di.dart';
import 'package:tacca/data/db/object_box.dart';
import 'package:tacca/services/ai/model_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/first_run.dart';

// Verifica dal vivo il flusso M1 (RF-01/RF-02) su un device reale, con
// ObjectBox nativo vero (non mockato): crea una scheda, la salva, la apre in
// consultazione, verifica il precompilamento in modifica, poi la elimina per
// non lasciare dati fittizi sul device.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('crea, salva, consulta, modifica ed elimina una scheda', (
    tester,
  ) async {
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
    await acceptLegalNoticeIfShown(tester);

    final planName =
        'Test integrazione ${DateTime.now().millisecondsSinceEpoch}';

    // 1. Nuova scheda dal FAB (il pannello ora chiede manuale o AI).
    await tester.tap(find.text('Nuova scheda'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editor manuale'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('plan-name')), planName);
    await tester.pumpAndSettle();

    // 2. Aggiungi un secondo giorno: i tab devono comparire.
    await tester.tap(find.text('Aggiungi giorno'));
    await tester.pumpAndSettle();
    expect(find.text('Giorno B'), findsOneWidget);

    // 3. Aggiungi un blocco EMOM e imposta l'intervallo.
    await tester.tap(find.text('Aggiungi blocco'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('EMOM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('EMOM')); // espandi la card
    await tester.pumpAndSettle();

    final intervalField = find.widgetWithText(TextFormField, 'Intervallo (s)');
    await tester.ensureVisible(intervalField);
    await tester.enterText(intervalField, '90');
    await tester.pumpAndSettle();

    // 4. Aggiungi un esercizio.
    final addExerciseButton = find.text('Aggiungi esercizio');
    await tester.ensureVisible(addExerciseButton);
    await tester.tap(addExerciseButton);
    await tester.pumpAndSettle();

    final exerciseNameField = find.widgetWithText(TextFormField, 'Esercizio');
    await tester.ensureVisible(exerciseNameField);
    await tester.enterText(exerciseNameField, 'Trazioni');
    await tester.pumpAndSettle();

    // 5. Salva.
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    // 6. Torna alla lista: la scheda appena creata deve essere visibile.
    expect(find.text(planName), findsOneWidget);

    // 7. Apri il dettaglio e verifica il contenuto salvato.
    await tester.tap(find.text(planName));
    await tester.pumpAndSettle();
    expect(find.text('Giorno B'), findsOneWidget);
    expect(find.text('EMOM'), findsWidgets);
    expect(find.text('Trazioni'), findsOneWidget);

    // 8. Apri la modifica: il nome deve arrivare già precompilato.
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    final nameField = tester.widget<TextFormField>(
      find.byKey(const ValueKey('plan-name')),
    );
    expect(nameField.initialValue, planName);

    // 9. Nessuna modifica fatta: il back non deve chiedere conferma di scarto.
    // (non uso tester.pageBack(): su iOS cerca solo un back button in stile
    // Cupertino, assente in questa app Material-only)
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    // 10. Pulizia: elimina la scheda di test creata da questo giro.
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
  });
}
