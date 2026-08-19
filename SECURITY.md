# Security Policy

Tacca stores workout data locally and, if you enable the AI import, talks to a third-party API with **your** key. That makes two things worth protecting: the API key and the data on the device.

## Supported versions

This is a pre-1.0 personal project. Only the current `main` branch is supported — fixes land there, and there are no backports.

## Reporting a vulnerability

**Do not open a public issue for a security problem.**

Use GitHub's private vulnerability reporting: go to the [Security tab](https://github.com/dorex96/tacca/security) of this repository and choose *Report a vulnerability*. That opens a private thread visible only to the maintainer.

If you'd rather not use GitHub, email **dorin@tverdohleb.dev** instead. Plain email is not encrypted, so keep the first message short — "there is an issue in X, can we move somewhere private" is enough.

Useful things to include: what an attacker can do, how you reproduced it, the affected version or commit, and the platform. A proof of concept helps more than a description.

What to expect: this is a spare-time project maintained by one person, so the honest commitment is an acknowledgement within about a week and a fix, or an explanation of why it will not be fixed, once the issue is understood. Please give the fix a reasonable window before disclosing publicly; you'll be credited when it lands unless you'd rather not be.

**Never paste an API key, a key fragment, or a real device backup into a report, an issue or a pull request.** If you have leaked an OpenRouter key, revoke it immediately at [openrouter.ai/settings/keys](https://openrouter.ai/settings/keys) — a key stays valid until you do.

## In scope

- Anything that exposes the stored OpenRouter API key to another app, to a log, to a crash report, to an exported file or to the network beyond the intended request.
- Anything that lets a third party read or modify the local database or the plan images without the user's action.
- Injection or code-execution paths through the AI import: a hostile plan photo, a hostile pasted text, or a hostile model response walking through the parser.
- A vulnerable dependency that is actually reachable from this app's code.

## Out of scope

- Physical access to an unlocked device, and rooted or jailbroken devices — the platform secure storage cannot defend against an attacker who already owns the OS.
- The fact that the AI import sends your images or text to OpenRouter and the selected model: that is the documented purpose of the feature, it is stated in the UI, and it only ever happens after an explicit user action.
- Charges on your own OpenRouter account caused by your own use.
- Reports produced by an automated scanner with no demonstrated impact on this app.

## How the app handles secrets, for reference

The OpenRouter API key is written only to `flutter_secure_storage` (iOS Keychain / Android Keystore) by `SecureSettingsRepository`. It is never written to ObjectBox, never included in an export, never logged, and never leaves the device except as the `Authorization` header of a request to OpenRouter that the user triggered. The repository ships no key of its own, and `android/key.properties`, which holds the Android signing credentials on the maintainer's machine, is git-ignored and must never be committed.
