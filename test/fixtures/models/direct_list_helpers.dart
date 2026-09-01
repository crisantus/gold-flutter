// ignore_for_file: prefer_single_quotes

import 'dart:convert';

List<ReportModel> reportModelFromJson(String str) => (json.decode(str) as List)
    .map(
      (item) => ReportModel.fromJson(
        Map<String, dynamic>.from(item as Map),
      ),
    )
    .toList();

String reportModelToJson(List<ReportModel> data) =>
    json.encode(data.map((item) => item.toJson()).toList());

class ReportModel {
  final String id;

  ReportModel({required this.id});

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        id: (json?["id"] ?? "").toString(),
      );

  Map<String, dynamic> toJson() => {"id": id};
}
