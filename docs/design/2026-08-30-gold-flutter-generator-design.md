# Gold Flutter Generator Design

## Purpose

Gold Flutter is a public, portable Dart CLI that creates a complete Flutter
foundation in a consistent personal style. It works from a normal terminal and
does not depend on Codex or one computer.

## Isolation

The generator repository is `crisantus/gold-flutter`. ParkClock, EyeAsk, Kri,
and Retrofit were read-only architectural references and are never included in
this repository. Product code, assets, secrets, and Git history from those apps
must not be copied into the generator.

## Generated architecture

Dependencies flow in one direction:

```text
remote source -> repository -> Riverpod ViewModel -> presentation
```

Generated projects use Riverpod for state and dependency injection, AutoRoute
for typed navigation, semantic light/dark themes, reusable visual primitives,
and local explicit spacing. They do not generate GetIt, global provider
containers, `StateNotifier`, a use-case layer, or a global spacing class.

## Variants

The base variant has no networking dependencies. API support adds Dio,
connectivity, services, typed errors, remote and repository seams, and Riverpod
providers. Authentication adds secure token storage and authorization.
Refresh-token support adds one coordinated refresh operation and at-most-once
request replay. A sample API feature exercises the complete architecture while
remaining testable without a live backend.

## Safety

Creation happens in a generator-owned sibling staging directory. A completed
project is published only after generation and verification. A pre-existing
non-empty destination is rejected and `0.1.0` has no force-overwrite option.
Templates never contain credentials or product secrets.

## Portability

The CLI invokes `flutter create`, retains standard platform projects, applies
the requested application identity, and bundles its templates within the Dart
package so Git activation works on macOS, Linux, and Windows.

