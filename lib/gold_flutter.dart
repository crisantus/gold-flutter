import 'src/cli/gold_flutter_cli.dart';
import 'src/prompts/prompt_io.dart';

export 'src/cli/gold_flutter_cli.dart';
export 'src/cli/doctor_command.dart';
export 'src/config/project_answers.dart';
export 'src/config/dependency_manifest.dart';
export 'src/generator/project_generator.dart';
export 'src/generator/project_verifier.dart';
export 'src/generator/staging_area.dart';
export 'src/generator/flutter_creator.dart';
export 'src/generator/template_renderer.dart';
export 'src/platform/app_identity.dart';
export 'src/platform/platform_patcher.dart';
export 'src/platform/repository_guard.dart';
export 'src/process/process_executor.dart';
export 'src/prompts/answers_collector.dart';
export 'src/prompts/prompt_io.dart';
export 'src/validation/input_validation.dart';

Future<int> runGoldFlutter(List<String> arguments) async {
  return GoldFlutterCli(io: const ConsolePromptIO()).run(arguments);
}
