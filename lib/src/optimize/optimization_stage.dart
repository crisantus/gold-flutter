enum OptimizationStageKind { pubGet, buildRunner, format, analyze, test }

final class OptimizationStage {
  OptimizationStage({
    required this.kind,
    required this.executable,
    required List<String> arguments,
    required this.mutatesFiles,
  }) : arguments = List.unmodifiable(arguments);

  final OptimizationStageKind kind;
  final String executable;
  final List<String> arguments;
  final bool mutatesFiles;

  String get command => [executable, ...arguments].join(' ');
}
