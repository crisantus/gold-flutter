const baseTemplates = <String, String>{
  'lib/main.dart': r'''import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: App()));
}
''',
  'lib/app.dart': r'''import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/route/app_router.dart';
import 'core/theme/app_theme.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: '{{display_name_dart}}',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router.config(),
    );
  }
}
''',
  'lib/core/route/app_router.dart':
      r'''import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../presentation/screens/home_screen.dart';

part 'app_router.gr.dart';

final appRouterProvider = Provider<AppRouter>((ref) {
  final router = AppRouter();
  ref.onDispose(router.dispose);
  return router;
});

@AutoRouterConfig(replaceInRouteName: 'Screen,Route')
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: HomeRoute.page, initial: true),
  ];
}
''',
  'lib/core/theme/app_colors.dart': r'''import 'package:flutter/material.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.page,
    required this.surface,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.success,
    required this.danger,
  });

  final Color page;
  final Color surface;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color accent;
  final Color success;
  final Color danger;

  static const light = AppColors(
    page: Color(0xFFF6F7FB),
    surface: Color(0xFFFFFFFF),
    border: Color(0xFFE5E7EB),
    textPrimary: Color(0xFF111827),
    textSecondary: Color(0xFF667085),
    accent: Color(0xFF635BFF),
    success: Color(0xFF14804A),
    danger: Color(0xFFB42318),
  );

  static const dark = AppColors(
    page: Color(0xFF0F1117),
    surface: Color(0xFF181B23),
    border: Color(0xFF2B303B),
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFFAAB2C0),
    accent: Color(0xFF9B96FF),
    success: Color(0xFF66D9A0),
    danger: Color(0xFFFF8A80),
  );

  @override
  AppColors copyWith({
    Color? page,
    Color? surface,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? accent,
    Color? success,
    Color? danger,
  }) {
    return AppColors(
      page: page ?? this.page,
      surface: surface ?? this.surface,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      accent: accent ?? this.accent,
      success: success ?? this.success,
      danger: danger ?? this.danger,
    );
  }

  @override
  AppColors lerp(covariant AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      page: Color.lerp(page, other.page, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      success: Color.lerp(success, other.success, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

extension AppThemeColors on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}
''',
  'lib/core/theme/app_theme.dart': r'''import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light, AppColors.light);
  static ThemeData get dark => _build(Brightness.dark, AppColors.dark);

  static ThemeData _build(Brightness brightness, AppColors colors) {
    final scheme = ColorScheme.fromSeed(
      seedColor: colors.accent,
      brightness: brightness,
      surface: colors.surface,
      error: colors.danger,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.page,
      extensions: [colors],
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: colors.page,
        foregroundColor: colors.textPrimary,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
''',
  'lib/business/starter/starter_viewmodel.dart':
      r'''import 'package:flutter_riverpod/flutter_riverpod.dart';

final starterViewModelProvider = NotifierProvider<StarterViewModel, int>(
  StarterViewModel.new,
);

class StarterViewModel extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state++;
}
''',
  'lib/presentation/widgets/app_surface_card.dart':
      r'''import 'package:flutter/material.dart';

class AppSurfaceCard extends StatelessWidget {
  const AppSurfaceCard({
    required this.icon,
    required this.title,
    required this.description,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(height: 18),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(description, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
''',
  'lib/presentation/widgets/home/home_counter_header.dart':
      r'''import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../business/starter/starter_viewmodel.dart';

class HomeCounterHeader extends ConsumerWidget {
  const HomeCounterHeader({
    this.onOpenSampleApi,
    super.key,
  });

  final VoidCallback? onOpenSampleApi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(starterViewModelProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your foundation is ready',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            const Text(
              'Riverpod, AutoRoute, themes, layers, assets, and focused tests are connected.',
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              key: const Key('starter-action'),
              onPressed: () =>
                  ref.read(starterViewModelProvider.notifier).increment(),
              icon: const Icon(Icons.auto_awesome),
              label: Text('Try Riverpod · $count'),
            ),
            if (onOpenSampleApi != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('sample-api-action'),
                onPressed: onOpenSampleApi,
                icon: const Icon(Icons.cloud_outlined),
                label: const Text('Open sample API'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
''',
  'lib/presentation/widgets/home/home_foundation_grid.dart':
      r'''import 'package:flutter/material.dart';

import '../app_surface_card.dart';

class HomeFoundationGrid extends StatelessWidget {
  const HomeFoundationGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 700
            ? (constraints.maxWidth - 16) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: width,
              child: const AppSurfaceCard(
                icon: Icons.account_tree_outlined,
                title: 'Clear architecture',
                description: 'Remote, repository, business, and presentation responsibilities stay separate.',
              ),
            ),
            SizedBox(
              width: width,
              child: const AppSurfaceCard(
                icon: Icons.palette_outlined,
                title: 'Consistent UI',
                description: 'Semantic light and dark themes keep every screen visually aligned.',
              ),
            ),
          ],
        );
      },
    );
  }
}
''',
  'lib/presentation/screens/home_screen.dart':
      r'''import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

{{sample_route_import}}
import '../widgets/home/home_counter_header.dart';
import '../widgets/home/home_foundation_grid.dart';

@RoutePage()
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('{{display_name_dart}}')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
{{home_header_widget}}
                  const SizedBox(height: 24),
                  const HomeFoundationGrid(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
''',
  'test/widget_test.dart': r'''import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:{{project_name}}/core/theme/app_theme.dart';
import 'package:{{project_name}}/presentation/screens/home_screen.dart';

void main() {
  testWidgets('starter screen demonstrates Riverpod state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
      ),
    );

    expect(find.text('Your foundation is ready'), findsOneWidget);
    expect(find.text('Try Riverpod · 0'), findsOneWidget);

    await tester.tap(find.byKey(const Key('starter-action')));
    await tester.pump();

    expect(find.text('Try Riverpod · 1'), findsOneWidget);
  });
}
''',
  'README.md': r'''# {{display_name}}

Flutter project generated by [Gold Flutter](https://github.com/crisantus/gold-flutter).

- Project name: `{{project_name}}`
- Application ID: `{{application_id}}`
- State management: Riverpod 3
- Navigation: AutoRoute
- API support: {{uses_api}}
- Authentication: {{uses_authentication}}
- Refresh tokens: {{uses_refresh_tokens}}
- Sample API feature: {{includes_sample_api}}

## Start

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

## Verify

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Read `AGENTS.md` before using Codex on this project.
''',
  'AGENTS.md': r'''# {{display_name}} Flutter Instructions

## Mandatory project skill

For every task that creates, changes, refactors, debugs, tests, or reviews
Flutter/Dart code, load and follow `$gold-flutter-development` from
`.agents/skills/gold-flutter-development/SKILL.md` before inspecting or editing
that code.

## Defaults

- Use Riverpod 3 for application state and dependency injection.
- Use AutoRoute and generated typed routes.
- Preserve `remote -> repository -> business -> presentation`.
- Build UI from semantic themes and reusable components.
- Keep layout spacing explicit and local.
- Add focused tests and run proportional verification.
''',
  '.agents/skills/gold-flutter-development/SKILL.md': r'''---
name: gold-flutter-development
description: Use when creating, changing, refactoring, debugging, testing, or reviewing Flutter and Dart code in this generated application.
---

# Gold Flutter Development

Continue this project in the same architecture and visual language established
by the generator. Inspect the nearest analogous production and test files
before editing.

## Architecture contract

Keep dependencies flowing:

```text
presentation -> business ViewModel -> repository interface -> repository implementation -> remote/local source
```

Place feature files in the existing layer-first paths:

- models: `lib/domain/models/`
- request payloads: `lib/domain/form_data/`
- abstract remotes: `lib/data/remote-apis/abst_remote/`
- concrete remotes: `lib/data/remote-apis/remote/`
- abstract repositories: `lib/data/repository_impl/abst_repository/`
- concrete repositories: `lib/data/repository_impl/repository/`
- ViewModels: `lib/business/<feature>/`
- screens and widgets: `lib/presentation/`

API features use each applicable seam above. Do not replace this with
feature-first scaffolding, add a use-case layer, put transport in UI, or
introduce GetIt/global provider containers.

## Riverpod 3

Use Riverpod for state and dependency injection. Prefer
`Notifier<AsyncValue<T>>` for explicit fetch and mutation actions; use
`AsyncNotifier<T>` when async construction is genuinely the state. Preserve
usable data during refresh and keep independent mutations independent. Do not
add `package:provider`, Bloc, `StateNotifier`, ChangeNotifier, GetIt, or global
provider containers for new state; Riverpod's own `Provider` remains the normal
choice for synchronous state and derivations.

Subscribe to state at the smallest widget boundary that renders it:

- Keep only genuinely page-wide rendered state in a screen-level `build()`.
  Put secondary provider subscriptions in focused `Consumer` or
  `ConsumerWidget` sections so unrelated changes do not rebuild the page. The
  smallest-boundary rule takes precedence over labeling a watch "primary."
  Prefer one cohesive provider-aware section over making every leaf widget a
  consumer; keep fields and other visual leaves provider-agnostic.
- Use `ref.watch` for rendered state and `select` when a widget renders only a
  stable slice. Use event-time `ref.read(provider)` for the latest value needed
  only by a tap, submission, sheet, or navigation action;
  `ref.read(provider.notifier)` invokes mutations.
- Use `ref.listen` for one-time UI effects such as snackbars, dialogs, and
  navigation. Do not use listeners as a second rendering mechanism.
- Do not hide provider subscriptions in ordinary `_build...` helper methods.
  Pass the required value explicitly or extract a focused provider-owning
  widget.
- Move shared or nontrivial repeated filtering, lookup, combination, or
  projection into a derived provider; a cheap one-off presentation transform
  may remain local. Prefer `Provider.autoDispose.family` for a temporary
  synchronous parameterized derivation when retained caching is not required,
  and use equality-safe parameters. Auto-disposal and retention apply to each
  argument-specific provider instance; retain an instance only when the
  product explicitly needs its cache after listeners disappear. Choose the
  corresponding asynchronous Riverpod provider when the derivation is async.
- Keep forms, controllers, `PageView`, and other stateful UI outside unrelated
  rebuild scopes. Do not mechanically count watches: colocate multiple watches
  only when the same smallest UI region genuinely renders all of them.

## Routing and UI

Use `@RoutePage()`, central AutoRoute declarations, generated typed routes, and
the single Riverpod-owned `AppRouter`. Regenerate `*.gr.dart`; never edit it by
hand or navigate with raw route-name strings.

Build screens from semantic theme values and focused reusable primitives.
Screen `build()` methods should stay short and read as orchestration. Move a
substantial feature-specific `_Field`, `_Section`, `_Card`, or similar widget
to `lib/presentation/widgets/<feature>/`, or the nearest existing feature-local
`widgets/` directory. Because imported Dart declarations cannot remain
library-private, give each extracted widget a descriptive public name such as
`GuideProfileField`, not a generic `Field`. Keep small one-off layout fragments
private when extraction would only add indirection. For example,
`screens/home_screen.dart` may extract `_SummarySection` to
`widgets/home/home_summary_section.dart` as `HomeSummarySection`.

Pure presentation widgets receive typed values and callbacks. A widget should
consume a provider directly only when that widget owns the responsibility for
reacting to it. Keep `_handle...` actions near the state or navigation they
coordinate, and convert a `ConsumerStatefulWidget` to a simpler widget only
when it no longer owns controllers, lifecycle work, or local mutable state. Use
`ConsumerWidget` while the screen still calls `ref.watch`, `ref.read`, or
`ref.listen`; use `StatelessWidget` only after all Riverpod access has moved
into descendants.

Cover loading, data, empty, initial error, retained-data refresh, disabled,
light/dark, landscape, wide, enlarged-text, and long-copy states as applicable.
Do not add a global spacing class or renamed equivalent—use local `Padding`,
`EdgeInsets`, `SizedBox`, and component-owned dimensions.

## Data and tests

API models use immutable fields, defensive parsing, `empty`, `fromJson`,
`toJson`, list parsing, and `copyWith` where applicable. Models own standard
response-envelope parsing. Repositories own connectivity, cache, retry, and
typed failure mapping.

Add the smallest focused behavioral test for each change. Use provider
overrides, real production widgets, and small fakes rather than mocking
internals. For provider-scope refactors, add rebuild-isolation tests that prove
the affected mounted region responds when its selected value changes while an
unrelated mounted region does not; also test event-time reads and family
disposal when those behaviors matter. A zero rebuild count after a widget
unmounts is not evidence. When a rebuild rule is project-wide, prefer an
analyzer/AST architecture test over source-text grep.

Format changed Dart files, regenerate routes when needed, run focused tests,
then `flutter analyze` and the broader suite for shared architecture or UI
changes.

## Common mistakes

- Moving UI into helper methods but leaving all watches at screen level.
- Watching state only because an action might need it later.
- Recomputing the same filtered collection in several widget builds.
- Extracting every tiny fragment or placing feature-only widgets in a global
  shared folder.
- Claiming performance gains from cleaner ownership without measuring on a
  physical device in profile mode.
''',
};
