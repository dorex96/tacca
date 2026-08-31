# Lock-screen confirmation

During a workout the current exercise is published to the phone's lock screen,
with a button that ticks the set you just finished. You confirm the set,
the rest countdown starts, and you never unlock the phone.

The two platforms get there differently:

| | iOS | Android |
| --- | --- | --- |
| Surface | Live Activity (ActivityKit) + Dynamic Island | ongoing notification |
| Countdown | `Text(timerInterval:)`, drawn by the system | `usesChronometer` + `chronometerCountDown` |
| Button | App Intent running in the widget extension (iOS 17+) | notification action → broadcast |
| Minimum version | iOS 16.2 for the banner, 17.0 for the button | Android 8.0 (`minSdk 26`) |
| Extra setup | **yes** — a second Xcode target, see below | none |

Below 16.2 (or with Live Activities switched off in Settings) `isSupported`
answers `false` and the session behaves exactly as it did before: no banner,
no button, everything else unchanged.

## How a confirmation travels

The tap does not reach the Dart engine. On iOS the App Intent runs in the
*extension's* process; on Android the broadcast may arrive after the app's
process has been killed. Neither can open ObjectBox. So both do the same
thing:

1. write the action into a durable queue — App Group `UserDefaults` on iOS, a
   small JSON file on Android;
2. update the surface optimistically, so the tap has a visible effect (iOS
   only: see the limitation below);
3. schedule the rest-end notification, because the app is not awake to beep.

When the app returns to the foreground, `WorkoutSessionBloc` drains the queue
and applies each action **with the timestamp of the tap** — the rest timer
starts from when the set actually ended, not from when the app woke up. An
action whose `logId` belongs to another session is discarded, and every action
carries an id so the same confirmation delivered twice (once live, once from
the queue) is applied once.

Known limitation, Android only: if the process was killed, the notification's
text does not refresh until you reopen the app. Re-initialising the plugin
inside a background isolate that is about to be torn down is not worth the
failure modes — the confirmation itself is never lost, and the countdown
keeps running because the system draws it.

## Xcode setup (iOS)

The widget extension target `TaccaLiveActivity` is already in
`ios/Runner.xcodeproj`, with its sources, `Info.plist` and entitlements. Two
things still need a human with Xcode, because they touch your developer
account:

1. **App Group.** Open `Runner.xcworkspace` → select the **Runner** target →
   *Signing & Capabilities* → **+ Capability** → *App Groups*, and tick (or
   add) `group.com.tverdohleb.tacca`. Repeat on the **TaccaLiveActivity**
   target. The identifier must match `LiveSessionShared.appGroupId` in
   `ios/LiveSessionShared/TaccaSessionAttributes.swift` — it is the only
   channel between the app and the extension. App Groups need a paid Apple
   Developer Program membership; free personal teams cannot enable them.
2. **Signing.** The extension has its own bundle id,
   `com.tverdohleb.tacca.LiveActivity`. With automatic signing Xcode creates
   the profile on first build; check that *Team* is set on both targets.

Then build as usual — `flutter run` builds and embeds the extension, no
separate step:

```bash
flutter run --release        # Live Activities also work on the simulator (16.2+)
```

If Xcode ever refuses to open the project, the target can be recreated from
its template: *File → New → Target… → Widget Extension*, name it
`TaccaLiveActivity`, tick *Include Live Activity*, then delete the generated
sources and drag in the files under `ios/TaccaLiveActivity/` (extension target
only) and `ios/LiveSessionShared/` (**both** targets — the attributes and the
queue are compiled into each process). Set the deployment target to 16.2 and
the base configuration to `Flutter/LiveActivity.xcconfig`, which is what keeps
the extension's version in step with the app's; Apple rejects a bundle whose
extension version differs.

## What to check on a device

Nothing here is covered by CI: the Linux runner cannot build iOS, and the
Swift side has no tests. The Dart side of the contract — snapshot payload,
action parsing, the queue, and the Bloc applying a confirmation with the tap's
timestamp — is covered by `test/services/live_session/` and the *schermata di
blocco* group in `test/features/workout/bloc/workout_session_bloc_test.dart`.

Worth walking through by hand at least once:

- [ ] Start a session: the banner appears on the lock screen and in the
      Dynamic Island.
- [ ] Lock the phone, press **Serie fatta**: the set counter advances and the
      rest countdown starts, without opening the app.
- [ ] Wait for the countdown to end: the notification fires **once** (the app
      cancels the extension's reminder when it wakes up — a double beep here
      means that cancellation is not working).
- [ ] Reopen the app: the set is in the log with the time you pressed the
      button, and the rest timer shows the time actually left.
- [ ] Confirm the last set of an exercise: the button disappears until the app
      is reopened, then the banner moves to the next exercise.
- [ ] Finish the session: the banner disappears.
- [ ] On an iPhone without Dynamic Island, and on iOS 16.x: banner yes, button
      only from 17.
