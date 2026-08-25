# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

Flutter app for managing gym workout plans ("schede di allenamento"). **M0–M2 are implemented**: plans archive + manual editor (RF-01/RF-02), workout session with `TimerEngine` and `WorkoutSessionBloc` (RF-06), and history (RF-07). **M3 (AI layer) is implemented in reduced scope**: **OpenRouter is the only provider** (Anthropic/Gemini deliberately not built; `AiProvider` remains the seam to add them), AI settings (RF-08) at `/settings/ai`, and import from camera photo / gallery images / pasted text (RF-03) at `/plans/new/import` with review through the manual editor (`PlanEditorCubit.draft`, route `/plans/new/review`). The models offered in the settings dropdown are **configuration, not code**: edit `assets/ai/models.json` (id, label, `supportsVision`, `supportsJsonSchema`, `defaultModelId`), loaded once in `main()` into `AiModelCatalog`. Chat-based create/edit (RF-04/RF-05) is **out of scope and will not be built**: importing a plan and then editing it in the manual editor covers the need, so do not propose or start it. The real specification lives in `items/` (Italian):

- `items/analisi-funzionale-app-schede-allenamento.md` — functional requirements (RF-01…RF-09), data model, UX rules.
- `items/analisi-tecnica-app-schede-allenamento.md` — the authoritative technical design: stack, ADRs, folder layout, entities, state management, AI service, milestones.

`items/` is git-ignored on purpose: it exists only in the maintainer's working copy, not in the public repository. What the public sees is `README.md` (what the app is, setup, architecture), `CONTRIBUTING.md` (conventions, tests, PR checklist) and `SECURITY.md` (BYOK key handling, how to report) — keep those three in sync when behaviour changes, and never quote the private spec verbatim into them.

**Read the technical analysis before implementing anything.** Decisions there are already made (ObjectBox as DB, flutter_bloc, go_router, dio, BYOK AI) and should not be re-litigated. The UI language is Italian; user-facing strings go through ARB files (`app_it.arb`), never hardcoded.

## Commands

```bash
flutter pub get                         # install dependencies
flutter run                             # run on connected device/emulator
flutter analyze                         # static analysis / lint (uses flutter_lints)
dart format .                           # format (CI fails on any difference)
flutter test                            # run all tests
flutter test test/path/to/foo_test.dart # run a single test file
flutter test --name "substring"         # run tests matching a name

# Codegen — ObjectBox, freezed, json_serializable all go through build_runner:
dart run build_runner build --delete-conflicting-outputs
dart run build_runner watch             # regenerate on change during development
```

Generated files (`*.g.dart`, `*.freezed.dart`) are gitignored and must be regenerated; `objectbox-model.json` **is** versioned and its UIDs must never be reused (see §4.3 of the technical analysis for rename procedures).

## Architecture (target design from the technical analysis)

**Dependency direction is strictly downward** — arrows only point down, never up:

```
Widgets (features/*/pages, widgets)
   → Cubit / Bloc (feature state)
      → Repository interfaces (PlanRepository, WorkoutLogRepository, SettingsRepository)
         → ObjectBox Store/Box   |   AiService → dio → AI provider
```

Enforced rules:
- The UI never touches repositories or services directly; Cubits/Blocs never touch `Box`, `dio`, or `SecureStorage` directly.
- **`Box`/`Store` may only be used inside `data/`.** ObjectBox entities are plain Dart POJOs and double as the domain model (ADR-01, Option C: repository pattern, no separate domain layer). DTOs exist only at the AI boundary.
- DI is explicit composition in `app/di.dart` via `RepositoryProvider`/`BlocProvider` — no service locator, no `get_it`. The ObjectBox `Store` is opened in `main()` before `runApp`.

**Folder layout** (feature-first presentation, shared `data/` layer): `app/`, `core/`, `data/` (db, entities, repositories), `services/` (ai, timer, notifications, images), `features/` (plans, ai_import, workout, history, settings). No barrel files — use direct imports. Files `snake_case.dart`; suffixes `*Cubit`, `*Bloc`, `*Repository`, `*Page`, `*Dto`.

### Design system
L'aspetto viene da un file di design ("Gym full figma"), non da un seed color Material, e vive in due posti soli — mai nelle pagine:

- `lib/app/theme.dart` — i temi di **tutti** i componenti (app bar, card, campi, pulsanti, chip, bottom sheet, dialog, menu, snackbar), costruiti dai token. Le pagine non passano `border:`, `elevation:`, colori o raggi a mano. Nota tecnica dentro il file: gli stili dei component theme vanno costruiti da `AppTypography` e mai ripresi da `ThemeData(...).textTheme`, perché `ThemeData` fonde le **dimensioni** tipografiche solo dentro `textTheme` (uno stile preso da lì arriverebbe senza `fontSize`).
- `lib/core/design/` — `AppColors`, `AppTypography`, `AppRadius`, `AppSpacing`, `AppChrome` (ombre + barre di sistema) e `linear_icons.dart`.

**Un tema solo.** La palette disegnata è una: `themeMode` è bloccato su chiaro in `app.dart`. Un tema scuro sarebbe una seconda interfaccia inventata a mano.

**Palette.** Fondo `#F4F4F6`; superfici bianche raggio 26; inchiostro `#192126`; prosa `#232A3A`; secondario `#8C9092`; contorni `#D4D8E0`; accento lime `#BBF246` — sopra il lime il testo è **sempre** inchiostro. Regola non negoziabile: **un solo elemento lime per schermata** (la scheda in uso, l'esercizio corrente, la tab attiva). È l'intero meccanismo con cui si legge "cosa è vivo adesso": il secondo lime annulla il primo. Il rosa `#FF5678` è il distruttivo e compare come *testo* (voci di menu, "Rimuovi serie") ovunque tranne che nella conferma finale di eliminazione, l'unico punto in cui diventa un fondo.

**Tipografia.** Lato per l'interfaccia, carattere di sistema per i paragrafi (un paragrafo lungo in Lato serrato non si legge: i token `paragraph`/`paragraphSmall`/`caption` lasciano `fontFamily` a null apposta, e `ThemeData.fontFamily` non va mai impostato). Google Fonts pubblica Lato solo in 400/700/900: i pesi 500 e 800 nominati dal design non esistono, quindi i token usano quelli veri.

**Icone.** Solo i glifi del set "Linear Icons" del file di design, in `AppIcons`, disegnati da `LinearIcon` a partire dai tracciati SVG. Niente `Icons.*` nell'interfaccia: la griglia ottica di Material accanto a queste forme si vede. Se manca un glifo si prende dal file di design, non si sostituisce con un Material.

**Impaginato.** Niente `AppBar`: `AppScaffold` disegna la testata (pulsanti icona quadrati 40 su bersaglio 48), il titolo Lato Black 24 nel contenuto e la pillola dell'azione principale agganciata in fondo (`dock`) al posto del FAB. La tab bar flottante (`HomeTabBar`, 340×56) la disegna la shell del router in uno `Stack`, non `bottomNavigationBar` — perciò i bottom sheet **devono** aprirsi sul navigator radice (`showAppSheet` lo fa già), altrimenti finiscono sotto la barra. Le liste lasciano in fondo `dockClearance` / `actionClearance` / `tabBarClearance` a seconda di cosa ci galleggia sopra.

I pezzi ricorrenti stanno in `lib/core/widgets/`: `AppScaffold` + `AppDock`, `PillButton` (l'unico pulsante grande), `SquareIconButton`/`GhostIconButton`, `SurfaceCard`, `MetaChip` (dati secondari, al posto delle stringhe unite da " · "), `Section`/`SectionHeader`, `EmptyState`, `InfoBanner`, `AppSheet`/`showAppSheet` + `SheetOption`, `AppField` (le due sole forme di campo) + `LabeledField`, `AppMenuButton`/`appMenuItem` e `showConfirmDialog` (ogni conferma, con `destructive: true` per le eliminazioni). Vincolo UX di riferimento: RNF-04 — target tappabili ≥ 48dp anche dove il design ne disegna 40 (`SquareIconButton` dipinge 40 dentro 48 apposta), alto contrasto, leggibilità a distanza.

### State management convention
**Cubit for CRUD/list/form; Bloc only where flow is genuinely event-driven.** The one Bloc is `WorkoutSessionBloc` (workout session): its inputs come from the user, `TimerEngine`, and app lifecycle, and event order matters. Critical rule there — **autosave on every state-mutating handler** (persist the `WorkoutLog` immediately; this is how the crash-recovery requirement RF-06 is met, not periodic saves). Never `emit` from external callbacks; the Bloc subscribes to `TimerEngine.stream` and re-dispatches as `TimerTicked`.

### Data model notes (ObjectBox)
- `ToMany` does not preserve order → every child has an `int sortOrder`; repositories return already-sorted lists.
- Enums are not persisted → stored as `String` (`enum.name`) with `@Transient()` getter/setter exposing the enum.
- Block-type parameters are **flat nullable fields** on `Block` (no polymorphism, no JSON blob).
- **ObjectBox does not cascade updates.** `box.put(aggregate)` only applies pending `ToMany` add/remove; edits to fields of children that are *already persisted* are silently dropped. Repositories therefore walk the tree and `put` every child explicitly, then delete the ids that disappeared from the in-memory tree (see `savePlan` and `saveLog`). Any new aggregate write must follow the same pattern — it is what makes the editor and the session autosave actually persist.
- History is snapshot-based: `LogEntry`/`WorkoutLog` store the exercise/plan *name* so history stays readable after the plan is edited or deleted. `WorkoutPlan` link in logs is a weak reference.
- Logged weight is `double? weightKg`; prescribed load on an exercise stays a free `String` (e.g. `"70% 1RM"`).

### AI service (BYOK — Bring Your Own Key)
`AiProvider` is an abstract interface with three dio-based implementations (Anthropic `/v1/messages` tool-use, Gemini `generateContent` responseSchema, OpenRouter OpenAI-compatible json_schema with a prompt-based JSON fallback). All responses flow through **one** pipeline in `plan_parser.dart`: extract JSON → decode to `PlanDto` (freezed) → semantic validation → shape normalization (`plan_normalizer.dart`) → **1 automatic retry** feeding the parse error back → on second failure the raw text becomes an editable `freeText` block (never discard user input). Validation runs *before* normalization on purpose: its error messages ("giorno 2, blocco 3") go back to the model in the retry, so they must match what the model wrote. Normalization exists because models translate line-by-line and emit one `standard` block per exercise, while a block is a *grouping*: consecutive note-less `standard` blocks are merged into one. The prompt asks for the same grouping (`prompts.dart`), but only the normalizer guarantees it — it also runs again after `mergePlanDtos`, since page boundaries re-create adjacent standard blocks. API keys live in `flutter_secure_storage` (one per provider), never logged or exported. No AI call happens without an explicit user action; everything except AI create/edit works fully offline.

### TimerEngine
UI-independent service. **Wall-clock based**, not tick-count: state is always computed from `startedAt` + `DateTime.now()`, so it stays exact after backgrounding (the 250ms `Timer.periodic` only drives UI updates). Only one timer active at a time. Foreground: `audioplayers` beep + `vibration` + `wakelock_plus`. Background: schedule `flutter_local_notifications`, reconcile from wall-clock on return. iOS background beep punctuality is an open risk (spike S-01).

## Testing

`test/` mirrors `lib/`. Priorities: `TimerEngine` (fakeAsync + injectable clock), `plan_parser` (real provider JSON fixtures, malformed → retry → freeText fallback, DTO→entity mapping), repositories (ObjectBox Store on a temp directory in setUp/tearDown), Cubits/Blocs (`mocktail` or the in-memory fakes in `test/support/fakes.dart`, over repository interfaces — no real DB). Widget tests cover the critical paths (editor, session, import review, AI settings). Golden tests are out of scope for v1.

Notes that bite:
- **`bloc_test` cannot be added**: on Dart 3.9 its `test` constraint conflicts with `json_serializable ^6.14.1`. Bloc tests dispatch events and assert on `bloc.state` after `pumpEventQueue()`.
- ObjectBox repository tests run on the host only because `lib/libobjectbox.dylib` is present; `objectBoxNativeLibSkipReason()` skips them otherwise.
- Localized dates go through `DateFormat`, so tests touching them need `initializeDateFormatting('it')` in `setUpAll` (production does it in `main()`).
- Widget tests that mount a session must inject a `TimerEngine` with a long `tickInterval`, otherwise the periodic timer keeps scheduling frames and `pumpAndSettle` never settles.
- Session cards are as tall as the design draws them: in the default 800×600 window a `ListView` never builds the second exercise of a superset. Tests that assert on it raise the window (`tester.view.physicalSize` + `addTearDown(tester.view.reset)`).
- Tests no longer look for Material icons: set checkmarks carry the key `set-toggle-<label>`, tab bar destinations `home-tab-<label>`, and icon actions are found by tooltip.

## Milestone order

M0 setup → M1 plans (entities/repos/editor) → M2 workout (TimerEngine + session + history) → M3 AI (providers + parser + import) → M4 polish. The offline core (M1–M2) is built and must stand on its own before the AI layer (M3) is touched.
