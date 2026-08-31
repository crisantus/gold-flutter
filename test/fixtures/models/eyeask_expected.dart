// ignore_for_file: prefer_single_quotes

import 'dart:convert';

ReportModel reportModelFromJson(String str) =>
    ReportModel.fromJson(json.decode(str) as Map<String, dynamic>);

String reportModelToJson(ReportModel data) => json.encode(data.toJson());

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
        page: int.tryParse((json?["current_page"] ?? "").toString()) ?? 0,
        price: double.tryParse((json?["price"] ?? "").toString()) ?? 0.0,
        total: num.tryParse((json?["total"] ?? "").toString()) ?? 0,
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

  factory ReportModel.empty() => ReportModel(
        id: "",
        page: 0,
        price: 0.0,
        total: 0,
        ready: false,
        createdAt: DateTime.now(),
        deletedAt: null,
        user: UserModel.empty(),
        items: [],
      );

  Map<String, dynamic> toJson() => {
        "id": id,
        "current_page": page,
        "price": price,
        "total": total,
        "ready": ready,
        "created_at": createdAt.toIso8601String(),
        "deleted_at": deletedAt?.toIso8601String(),
        "user": user.toJson(),
        "items": items.map((item) => item.toJson()).toList(),
      };

  String get label => '$id:$page';
}

class UserModel {
  final String name;

  UserModel({required this.name});

  factory UserModel.fromJson(Map<String, dynamic>? json) => UserModel(
        name: (json?["name"] ?? "").toString(),
      );

  factory UserModel.empty() => UserModel(
        name: "",
      );

  Map<String, dynamic> toJson() => {
        "name": name,
      };
}

class ItemModel {
  final String sku;

  ItemModel({required this.sku});

  factory ItemModel.fromJson(Map<String, dynamic>? json) => ItemModel(
        sku: (json?["sku"] ?? "").toString(),
      );

  factory ItemModel.empty() => ItemModel(
        sku: "",
      );

  Map<String, dynamic> toJson() => {
        "sku": sku,
      };
}
