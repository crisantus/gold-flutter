# Gold Flutter Style Guide

Use this guide for Flutter apps created with Gold Flutter. Apply optional API,
authentication, offline, and localization rules only when those features exist.
Follow the app's own requirements when they are more specific.

## Architecture and naming

- Keep `presentation -> business ViewModel -> repository interface -> repository
  implementation -> remote/local source`. Widgets do not call Dio, Firebase,
  sockets, or remote sources for app data.
- Use the generated layer-first paths under `lib/presentation`, `lib/business`,
  `lib/domain`, and `lib/data`. Pair abstract remote and repository contracts
  with their implementations. Do not add a use-case layer or global provider
  container.
- Keep one business file per focused operation. Use `snake_case` files,
  `*_viewmodel.dart` business files, PascalCase classes, camelCase providers,
  and verb-based action methods.
- Use AutoRoute declarations and generated typed routes. Regenerate route code;
  never hand-edit generated files or navigate with raw route-name strings.

## Riverpod 3 and actions

- Prefer `Notifier<AsyncValue<T>>` for explicit reads and mutations. Use
  `AsyncNotifier<T>` when asynchronous construction is the state. Initialize
  with a useful empty model only when that is an honest, safe state for the
  feature.
- Keep independent actions independent. A card with multiple mutations needs
  state by item identity and action type; local loading booleans must not become
  the owner of server-backed work.
- Use `ref.watch` for rendered state, `select` for a stable slice, event-time
  `ref.read` for action inputs, and `ref.read(provider.notifier)` for mutations.
  Put subscriptions at the smallest widget region that renders them.
- Use `ref.listen` for one-time effects such as feedback or navigation. Keep
  submit/save listeners near their action section, check `mounted` after awaits,
  and avoid registering listeners or starting requests in `build()`.
- Preserve useful data while refreshing. Distinguish initial loading, retained
  data refresh, empty, error, disabled, pending, and successful states.

## Data, models, and platform services

- Keep transport in remote sources and connectivity, caching, retries, and
  offline decisions in repositories. ViewModels call repository methods and
  expose state; widgets render and dispatch actions.
- API models own defensive parsing: immutable fields, `empty`, null-safe
  `fromJson`, `toJson`, list parsing, and `copyWith` when needed. Unwrap a
  standard response envelope in the model rather than repeating helpers in
  remote files. Nested models parse their own plain maps.
- Convert typed repository failures into the app's existing error and feedback
  presentation. Keep noncritical cleanup after a successful mutation from
  turning that mutation into a reported failure.
- Keep permission prompts with the feature that needs them, after the first
  frame when appropriate. Platform services orchestrate plugins and delegate
  backend writes to repositories. Do not request unrelated permissions during
  app bootstrap.

## UI, copy, and accessibility

- Make screen `build()` methods read as composition. Extract focused sections
  and action handlers; move substantial reusable widgets to the nearest
  feature widget directory. Avoid extraction that only adds indirection.
- Use semantic theme values and local spacing. Do not create a global spacing
  class. Let text-bearing content grow; verify portrait, landscape, split
  screen, tablet, keyboard, long copy, and enlarged text where relevant.
- Do not derive font size from landscape width or manually apply the ambient
  `TextScaler` to theme font sizes; Flutter applies it during layout. Preserve
  visible fixed actions and one intentional scroll owner per axis.
- If localization is enabled, use the project's localization API for new
  app-authored visible copy and update every supported locale. Do not localize
  user-generated content or backend-returned names, messages, and data. Flag
  unreviewed translations before release.

## Offline and realtime behavior

- When offline reads matter, read a validated, timestamped, non-sensitive cache
  first; refresh from the server when connected; keep useful cached content if
  an optional refresh fails. Show offline or pending status where it changes
  user expectations. Never store tokens, payment URLs, or verification files in
  a general content cache.
- Queue writes only when the operation is safe to repeat and has a durable
  client identity. Persist retry state, bound attempts, surface pending or
  failed work, and reconcile with server truth. Payments, withdrawals,
  passwords, account deletion, and verification need explicit backend
  idempotency before automatic retry or offline queueing.
- Realtime updates should reconcile the affected repository cache. Register
  one subscription per owner and avoid a full refetch for every burst event.

## Tests and maintenance

- Reuse nearby production patterns and test helpers. Add focused behavioral
  tests for new logic, including failure, stale response, disposal, offline,
  and accessibility cases when relevant.
- Run `dart format`, focused tests, `flutter analyze`, and wider tests when a
  shared contract changes. Run route generation and `flutter gen-l10n` when
  those inputs change. Keep project-specific audits synchronized if present.
- Use the companion [performance guide](FLUTTER_PERFORMANCE_GUIDE.md) for
  lifecycle, rendering, device evidence, and performance claims.
