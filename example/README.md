# BiometricShield Example App

This example demonstrates how to integrate `biometric_shield` in a real Flutter app flow.

## Run

```bash
cd example
flutter pub get
flutter run
```

## What It Demonstrates

- Login flow + token storage (`storeToken`)
- Biometric authentication (`authenticate`, `requireFresh`)
- Session validation (`validateOrAuthenticate`)
- Protected screens with `BiometricGate`
- Reactive auth UI with `BiometricBuilder`
- Custom fallback handler (`FallbackHandler`) with custom PIN flow
- Runtime user preferences (`BiometricPreferences`)
- Multi-user namespacing (`userId`) for session/token/lockout isolation
- Lockout status and reset behavior
- Analytics event hooks via `onEvent`

## Screens

- `login_screen.dart`: initial login + biometric unlock
- `home_screen.dart`: central hub for auth/session actions
- `sensitive_data_screen.dart`: gate-protected content
- `biometric_builder_screen.dart`: reactive auth states
- `custom_fallback_screen.dart`: custom fallback UI integration
- `settings_screen.dart`: user-configurable biometric preferences
- `multi_user_screen.dart`: per-user storage/session isolation

## Notes

- This app intentionally uses simple in-app mock behavior for demo clarity.
- For production backend wiring, see:
  - `../doc/INTEGRATION.md`
  - `./example.md`
