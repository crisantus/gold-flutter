import 'package:gold_flutter/src/prompts/prompt_io.dart';

final class FakePromptIO implements PromptIO {
  FakePromptIO(Iterable<String> input) : _input = input.iterator;

  final Iterator<String> _input;
  final List<String> prompts = [];
  final List<String> output = [];

  @override
  String? readLine() => _input.moveNext() ? _input.current : null;

  @override
  void write(String message) {
    prompts.add(message);
  }

  @override
  void writeLine(String message) {
    output.add(message);
  }
}
