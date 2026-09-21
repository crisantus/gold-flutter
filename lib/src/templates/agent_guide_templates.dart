// The Markdown sources live in docs/development/. Keep these copies in sync.
const agentGuideTemplates = <String, String>{
  'docs/development/FLUTTER_STYLE_GUIDE.md': r'''# Gold Flutter Style Guide

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
''',
  'docs/development/FLUTTER_PERFORMANCE_GUIDE.md':
      r'''# Gold Flutter Performance Guide

Performance means preserving approved UI, accessibility, and behavior while
keeping input, scrolling, navigation, loading, media, and lifecycle transitions
responsive. Code cleanup and passing tests alone do not prove smoother frames.
Use this guide for generated Flutter apps; apply each rule to features the app
actually has.

## Evidence and frame budgets

- Name the exact scenario and capture a before trace in profile mode. Repeat
  that scenario after the change on supported physical Android and iOS devices.
  Record device, OS, build, refresh rate, trace location, janky frames, worst
  relevant UI/raster frame, first useful content, duplicate requests, and
  unexpected memory growth.
- A 60 Hz display has about 16.7 ms per frame; a 120 Hz display has about
  8.3 ms. Judge sustained work against the active refresh budget, including
  both UI and raster time.
- For release-significant flows, include a lower-tier Android phone and an
  older supported iPhone at 60 Hz, plus representative current devices at
  their native refresh rates when available. Profile launch, navigation,
  scrolling, search input, refresh, keyboard, image-heavy content, and the
  feature's busiest path.
- Never claim physical-device smoothness from debug mode, simulators,
  emulators, or tests. Mark unavailable hardware evidence pending. Do not
  remove content, interaction, or animation merely to improve a measurement.

## Ownership, rebuilds, and lifecycle

- Give every request, subscription, controller, observer, timer, animation,
  player, and WebView one owner that disposes it. Ignore callbacks after
  disposal. Start first-load work once from a ViewModel, `initState`, or an
  intentional post-frame owner; never create resources or start requests in
  `build()`.
- Keep server-backed, shared, retryable state in business/ViewModel owners and
  short-lived visual state local. Use focused `Consumer` regions and `select`
  so a badge, countdown, progress value, or row mutation does not rebuild the
  whole screen.
- Check `mounted` after awaits before using widget context or `setState`.
  On resume, reconcile stale data once rather than recreating every provider
  or issuing a burst of requests.

## Lists, images, media, and animation

- Use lazy lists or slivers for potentially growing data. Give mutable,
  reorderable, animated, and paginated rows stable domain keys. Preserve rows
  and scroll position during refresh or append; deduplicate by domain ID.
- Keep one primary scroll owner per axis. Avoid shrink-wrapped nested lists for
  large collections. Prepare sorting, filtering, parsing, and expensive
  formatting outside item builders. Pagination needs an in-flight guard,
  stable cursor, stale-response protection, and an end condition.
- Decode remote images near their rendered pixel dimensions, accounting for
  device pixel ratio. Keep placeholders and error states dimensionally stable.
  Avoid full-resolution thumbnail decoding and unbounded image caches.
- Pause tickers, carousels, audio, video, countdowns, and decorative animation
  while hidden or inactive. Prefer transform and opacity animation over
  repeated layout work; profile heavy clipping and save layers in scrolling
  surfaces.
- Create a WebView controller once, keep progress updates local, ignore late
  callbacks, and make completion or payment navigation one-shot. Never log
  tokens, payment URLs, personal data, or sensitive payloads.

## Requests, cache, and mutation safety

- Share identical in-flight reads at the repository or ViewModel owner.
  Normalize cache keys and bound cache size and lifetime. Debounce replaceable
  input and use request generations so late results cannot replace newer ones.
- Keep useful data visible during refresh, then replace it atomically. Cache
  only validated, timestamped, non-sensitive content when persistence is
  appropriate. Retain usable data if an optional refresh fails offline.
- Coalesce realtime bursts into one logical reconciliation. Mutations need
  duplicate-submit guards and clear success/failure ownership. Optimistic
  changes need rollback or authoritative reconciliation.
- Never automatically retry or queue a high-risk mutation without an
  idempotency key supplied and used by the backend.

## Android, iOS, and verification

- Exercise resume, inactive, paused, detached, and restoration paths relevant
  to the feature. On Android, check back navigation, low-memory recreation,
  keyboard resizing, high-refresh behavior, and lower-tier image memory. On
  iOS, check interactive back, safe areas, keyboard transitions, 60 Hz and
  ProMotion, and WebView or media teardown.
- Make platform-channel and plugin callbacks safe when they arrive late.
  Completion should be idempotent and disposal deterministic on both platforms.
- Run focused unit, widget, integration, architecture, and golden tests as
  relevant, then `flutter analyze`. Run `flutter gen-l10n` after localization
  changes and project audit checks when present. Tests with perpetual
  animation must advance bounded frames or await a specific state.
- A performance change is ready only when behavior and accessibility remain
  correct, lifecycle and retry safety are reviewed, relevant checks pass, and
  the same before/after scenario has device evidence. Report any missing
  measurement, device, or translation review as pending.
''',
};
