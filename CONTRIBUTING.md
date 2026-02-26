# Contributing to BiometricShield

Thanks for your interest in contributing to BiometricShield.

## Development setup

```bash
# Clone the repo
git clone https://github.com/biometric-shield/biometric_shield.git
cd biometric_shield

# Get dependencies
flutter pub get

# Run the analyzer
flutter analyze

# Run tests
flutter test
```

## Project structure

The SDK follows a strict layered architecture:

- `lib/src/core/` — Pure Dart. No Flutter imports. Business logic, config, result types.
- `lib/src/platform/` — Platform capability detection and handlers.
- `lib/src/session/` — Session lifecycle and lockout management.
- `lib/src/fallback/` — Fallback chain orchestration.
- `lib/src/storage/` — Token storage interface and default implementation.
- `lib/src/analytics/` — Event types and models.
- `lib/src/ui/` — Optional Flutter widgets (BiometricBuilder, BiometricGate).
- `lib/src/testing/` — Mock and fake helpers for consumers.

## Code style

- Follow `flutter_lints` rules (included in `analysis_options.yaml`).
- Use `on Exception catch` instead of bare `catch` — let programming errors propagate.
- All `DateTime.now()` calls must use `.toUtc()` for consistency.
- Nullable fields that are read more than once must be captured to a local variable (TOCTOU prevention).
- Public API methods return `BiometricResult` — never throw exceptions to callers.

## Adding a new result variant

1. Add the variant to the `BiometricResult` sealed class in `biometric_result.dart`.
2. Add the corresponding parameter to the `.when()` method.
3. Add the switch case in `.when()`.
4. Create a concrete class extending `BiometricResult`.
5. Add a factory method to `FakeBiometricResult` in `testing/`.
6. Update the mock in `biometric_shield_mock.dart` if needed.

## Commit messages

Use descriptive commit messages that explain the "why":

- `Fix iOS crash: add NSFaceIDUsageDescription to Info.plist`
- `Fix concurrency: atomic check-and-set for auth guard`

## Pull requests

- One feature or fix per PR.
- Include tests for new functionality.
- Run `flutter analyze` and `flutter test` before submitting.
- Update CHANGELOG.md with your changes.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
