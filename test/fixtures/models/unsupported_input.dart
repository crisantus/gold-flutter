// ignore_for_file: prefer_single_quotes

class ReportModel {
  final Map<String, List<Object?>> grouped;

  ReportModel({required this.grouped});

  factory ReportModel.fromJson(Map<String, dynamic>? json) => ReportModel(
        grouped: json?["grouped"] as Map<String, List<Object?>>,
      );
}
