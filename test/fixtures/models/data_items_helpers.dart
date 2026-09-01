// ignore_for_file: prefer_single_quotes

import 'dart:convert';

List<ReportModel> reportModelFromJson(String str) =>
    (((json.decode(str) as Map<String, dynamic>)["data"]
            as Map<String, dynamic>)["items"] as List)
        .map(
          (item) => ReportModel.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();

String reportModelToJson(List<ReportModel> data) => json.encode({
      "data": {
        "items": data.map((item) => item.toJson()).toList(),
      },
    });

class ReportModel {
  final String id;

  ReportModel({required this.id});

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        id: (json?["id"] ?? "").toString(),
      );

  Map<String, dynamic> toJson() => {"id": id};

  static List<ReportModel> fromJsonList(dynamic json) {
    final data = json is Map ? json["data"] : json;
    final items = data is Map ? data["items"] : data;
    final values = items is List ? items : const [];
    return values
        .whereType<Map>()
        .map((item) => ReportModel.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  static List<Map<String, dynamic>> toJsonList(List<ReportModel> values) {
    return values.map((value) => value.toJson()).toList(growable: false);
  }
}
