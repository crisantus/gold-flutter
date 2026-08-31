import 'dart:io';

abstract interface class PromptIO {
  String? readLine();
  void write(String message);
  void writeLine(String message);
}

final class ConsolePromptIO implements PromptIO {
  const ConsolePromptIO();

  @override
  String? readLine() => stdin.readLineSync();

  @override
  void write(String message) => stdout.write(message);

  @override
  void writeLine(String message) => stdout.writeln(message);
}
