// ignore_for_file: prefer_single_quotes, unused_import

import 'dart:convert';

class ReportModel {
  final String id;
  final int page;
  final double price;
  final num total;
  final bool ready;
  final DateTime createdAt;
  final DateTime? deletedAt;
  final UserModel user;
  final List<ItemModel> items;

  ReportModel({
    required this.id,
    required this.page,
    required this.price,
    required this.total,
    required this.ready,
    required this.createdAt,
    required this.deletedAt,
    required this.user,
    required this.items,
  });

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        id: (json?["id"] ?? "").toString(),
        page: int.tryParse((json?["current_page"] ?? "").toString()) ?? 1,
        price: double.tryParse((json?["price"] ?? "").toString()) ?? 1.0,
        total: num.tryParse((json?["total"] ?? "").toString()) ?? 1,
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

class UserModel {
  final String name;

  UserModel({required this.name});

  factory UserModel.fromJson(Map<String, dynamic>? json) => UserModel(
        name: (json?["name"] ?? "").toString(),
      );
}

class ItemModel {
  final String sku;

  ItemModel({required this.sku});

  factory ItemModel.fromJson(Map<String, dynamic>? json) => ItemModel(
        sku: (json?["sku"] ?? "").toString(),
      );
}
