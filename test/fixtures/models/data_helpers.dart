// ignore_for_file: prefer_single_quotes

import 'dart:convert';

ReportModel reportModelFromJson(String str) => ReportModel.fromJson(
      (json.decode(str) as Map<String, dynamic>)["data"]
          as Map<String, dynamic>?,
    );

String reportModelToJson(ReportModel data) => json.encode({
      "data": data.toJson(),
    });

class ReportModel {
  final String id;

  ReportModel({required this.id});

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        id: (json?["id"] ?? "").toString(),
      );

  Map<String, dynamic> toJson() => {"id": id};
}
