final class ChangeReport {
  ChangeReport({
    required this.success,
    required this.restored,
    required Iterable<String> created,
    required Iterable<String> modified,
    required Iterable<String> skipped,
    required this.output,
  })  : created = List.unmodifiable(created),
        modified = List.unmodifiable(modified),
        skipped = List.unmodifiable(skipped);

  final bool success;
  final bool restored;
  final List<String> created;
  final List<String> modified;
  final List<String> skipped;
  final String output;
}
