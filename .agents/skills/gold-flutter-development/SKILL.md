---
name: gold-flutter-development
description: Use when creating, changing, refactoring, debugging, testing, profiling, or reviewing the Gold Flutter generator, its Flutter templates, or the AI instructions bundled with generated projects.
---

# Gold Flutter Development

## Required context

Read the repository `AGENTS.md`,
`docs/development/FLUTTER_STYLE_GUIDE.md`, and
`docs/development/FLUTTER_PERFORMANCE_GUIDE.md` completely before changing
Flutter templates or guidance. Read the relevant generator templates and the
nearest analogous tests before making a change. Inspect the generated
`AGENTS.md` and `.agents/skills/gold-flutter-development/SKILL.md` entries in
`lib/src/templates/base_templates.dart` when changing the AI experience after
project setup. Direct user requirements and more specific project instructions
take precedence.

## Generator contract

- Keep generated files coherent across the base, API, authentication, refresh
  token, and sample API choices. Change only the templates that own the feature.
- Preserve the generated app's layer boundaries:
  `presentation -> business ViewModel -> repository -> remote/local source`.
  Network decisions belong in repositories, not widgets.
- Preserve Riverpod 3 state and dependency injection, AutoRoute typed routes,
  semantic themes, local spacing, and the established folder layout. Do not
  introduce a second architecture through one template.
- Keep generated `AGENTS.md` and its Flutter skill aligned with what the
  generator actually creates. Guidance for optional features must be
  conditional. Do not copy Kri-only locale lists, file paths, or audit scripts
  into every generated project.

## Flutter behavior represented by templates

- Keep UI build methods focused on composition and actions. Put subscriptions
  at the smallest widget boundary that renders their state; keep independent
  mutations independent.
- Keep model parsing in models. Use defensive `fromJson` and `toJson`, `empty`,
  and list parsing where the API feature requires them.
- Give each request, subscription, controller, timer, animation, media
  resource, and WebView one owner. Dispose it and ignore late callbacks.
- Deduplicate identical in-flight reads, prevent stale responses from replacing
  newer data, bound caches, and preserve usable data during refresh where the
  flow needs those behaviors. Do not retry sensitive mutations without backend
  idempotency support.
- If localization is enabled, use the project's localization API for new
  app-authored copy and update every supported locale. Keep user-generated
  and backend-returned content unchanged.
- For landscape, split-screen, tablet, or enlarged-text problems, use
  `$flutter-landscape-responsiveness` when available. Preserve portrait
  behavior, allow text-bearing content to grow, and test the affected viewport
  and text scale.

## Verification

Format changed Dart files. Run focused generator tests, `dart analyze`, and
broader tests when shared templates or option combinations change. Render a
sample project when generated file structure or instructions change, and
inspect the resulting files. For performance claims about generated Flutter
apps, compare the same scenario in profile mode on supported physical devices;
report missing device evidence instead of inferring it from debug mode or a
simulator. Report checks that could not run and why.
