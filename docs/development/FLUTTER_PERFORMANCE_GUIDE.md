# Gold Flutter Performance Guide

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
