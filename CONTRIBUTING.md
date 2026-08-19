# Contributing to Tacca

Thanks for taking a look. Tacca is a personal project built against a written specification, so the fastest way to get a change merged is to understand the constraints before writing code.

## Before you start

- **Open an issue first** for anything larger than a typo, a bug fix or a translation. Describe the problem, not only the patch.
- **The architecture decisions are settled**: ObjectBox as the database, `flutter_bloc` for state, `go_router` for navigation, `dio` for HTTP, bring-your-own-key AI with no backend of our own. A PR that swaps one of them out will be declined however good it is — those are load-bearing choices, not defaults nobody thought about.
- **The full functional and technical specification is not public** (it lives outside this repository, in Italian). If a behaviour looks arbitrary, it usually encodes a requirement — ask in the issue and you'll get the reasoning.
- `CLAUDE.md` at the repository root is the working agreement used when this codebase is edited with AI assistance. It is also the shortest complete description of the conventions below; read it.

## Setup

Flutter **3.35.x** (Dart 3.9), Android 8.0+ or iOS 15.6+.

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run

dart run build_runner watch     # regenerate while you work
```

`*.g.dart` and `*.freezed.dart` are generated and git-ignored, so a fresh clone does not compile before the `build_runner` step. `lib/objectbox-model.json` is the exception: it **is** versioned. Commit it whenever you touch an entity, and never reuse or hand-edit its UIDs — that file is how ObjectBox knows a field was renamed rather than dropped and re-added.

To run the repository tests locally you also need the ObjectBox native library on the host; without it they skip themselves:

```bash
bash <(curl -s https://raw.githubusercontent.com/objectbox/objectbox-dart/main/install.sh)
```

## Conventions

**Dependencies point downward, never up.** Widgets → Cubit/Bloc → repository interfaces → ObjectBox / `AiProvider`. The UI never touches a repository or a service directly, and a Cubit never touches `Box`, `dio` or secure storage. `Box`/`Store` may only appear inside `data/`. Dependency injection is explicit composition in `lib/app/di.dart` — no service locator, no `get_it`.

**Layout and naming.** Feature-first under `features/`, shared data layer under `data/`, no barrel files (import directly). Files are `snake_case.dart`; classes end in `Cubit`, `Bloc`, `Repository`, `Page` or `Dto`.

**State management.** Cubit for CRUD, lists and forms. Bloc only where the flow is genuinely event-driven and ordering matters — today that means `WorkoutSessionBloc` alone. Two rules there: every state-mutating handler persists the log immediately (that autosave *is* the crash-recovery feature, not a periodic save), and nothing ever emits from an external callback — the Bloc subscribes to `TimerEngine.stream` and re-dispatches a `TimerTicked` event.

**Data layer.** `ToMany` does not preserve order, so every child has an `int sortOrder` and repositories return sorted lists. Enums are stored as `String` with a `@Transient()` getter. Block parameters are flat nullable fields — no polymorphism, no JSON blobs. ObjectBox does **not** cascade updates: a repository that writes an aggregate must walk the tree, `put` every child explicitly and delete the ids that disappeared, exactly like `savePlan` and `saveLog`. History is snapshot-based on purpose: logs keep the plan and exercise names so they stay readable after the plan changes.

**Appearance.** Colours, elevations, radii and typography live in `lib/app/theme.dart`; spacing and radius tokens in `lib/core/design/`. Pages pass no hand-tuned numbers. Recurring pieces (`EmptyState`, `SectionHeader`, `MetaChip`, `InfoBanner`, `showConfirmDialog`) live in `lib/core/widgets/`. Tap targets stay ≥ 48dp.

**Strings.** Every user-facing string goes through `lib/l10n/app_it.arb`. Never hardcode text in a widget, not even temporarily.

**AI layer.** All provider responses go through the single pipeline in `plan_parser.dart` (extract → decode → validate → normalize → one retry → free-text fallback). Validation runs before normalization deliberately: its messages are fed back to the model. API keys are read from secure storage, never logged, never persisted anywhere else. No network call happens without an explicit user action, and everything except the AI import must keep working offline. The selectable models are configuration in `assets/ai/models.json` — adding one is not a code change.

**Comments.** The existing comments and docs in the code are in Italian; match the language of the file you are editing. Issues and PR descriptions can be in Italian or English.

**Dependencies.** Adding a package is a real cost for an offline app that stores personal data. Say in the PR why the standard library or the existing dependencies are not enough.

## Tests

`test/` mirrors `lib/`.

```bash
flutter test
flutter test test/services/timer/timer_engine_test.dart
flutter test --name "substring"
flutter test integration_test          # needs a device or emulator
```

Things that will bite you:

- `bloc_test` is deliberately absent — its `test` constraint conflicts with `json_serializable` on Dart 3.9. Bloc tests dispatch events and assert on `bloc.state` after `pumpEventQueue()`.
- Tests touching localized dates need `initializeDateFormatting('it')` in `setUpAll` (production does it in `main()`).
- A widget test that mounts a session must inject a `TimerEngine` with a long `tickInterval`, otherwise the periodic timer keeps scheduling frames and `pumpAndSettle` never settles.
- Repository tests open a real ObjectBox `Store` in a temp directory created in `setUp` and removed in `tearDown`; Cubit and Bloc tests use `mocktail` or the in-memory fakes in `test/support/fakes.dart` over the repository interfaces — never a real database.

## Before opening a pull request

```bash
dart format .
flutter analyze
flutter test
```

CI runs the same three on Ubuntu and fails on any formatting difference. Keep the PR focused on one thing, explain the why in the description, and call out explicitly if you changed `lib/objectbox-model.json` (database schema) or added a dependency.

Using an AI assistant to write the patch is fine — this codebase was built that way. What is not fine is submitting code you cannot explain: you own what you open the PR with, and "the model wrote it" is not a review answer.

## Licensing of contributions

By submitting a pull request you agree that your contribution is licensed under the [Apache License 2.0](LICENSE), the same license as the project, as described in section 5 of that license. Copyright stays with you; the project keeps the right to distribute it under Apache-2.0.

## Conduct

Be civil, be concrete, assume the other person had a reason. Harassment, personal attacks or bad-faith argument get the thread locked and the account blocked — there is no longer document behind this one.
