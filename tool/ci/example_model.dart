class ExampleModel {
  final String id;
  final int count;

  ExampleModel({required this.id, required this.count});

  factory ExampleModel.fromJson(Map<String, dynamic>? json) => ExampleModel(
        id: (json?['id'] ?? '').toString(),
        count: int.tryParse((json?['count'] ?? '').toString()) ?? 0,
      );
}
