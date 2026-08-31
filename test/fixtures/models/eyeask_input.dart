// ignore_for_file: undefined_class, non_type_as_type_argument
// ignore_for_file: undefined_identifier, prefer_single_quotes

import 'dart:convert';

class ReportModel {
  final String id;
  final int page;
  final bool ready;
  final DateTime createdAt;
  final DateTime? deletedAt;
  final UserModel user;
  final List<ItemModel> items;

  ReportModel({
    required this.id,
    required this.page,
    required this.ready,
    required this.createdAt,
    required this.deletedAt,
    required this.user,
    required this.items,
  });

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        id: (json?["id"] ?? "").toString(),
        page: int.tryParse((json?["current_page"] ?? "").toString()) ?? 1,
        ready: json?["ready"] is bool
            ? json!["ready"] as bool
            : (json?["ready"] ?? "").toString() == "true",
        createdAt: DateTime.tryParse(
              (json?["created_at"] ?? "").toString(),
            ) ??
            DateTime.now(),
        deletedAt: DateTime.tryParse(
          (json?["deleted_at"] ?? "").toString(),
        ),
        user: UserModel.fromJson(json?["user"]),
        items: (json?["items"] is List ? json!["items"] as List : [])
            .map((item) => ItemModel.fromJson(item))
            .toList(),
      );

  String get label => '$id:$page';
}
