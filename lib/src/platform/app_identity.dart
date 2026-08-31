final class AppIdentity {
  const AppIdentity({
    required this.displayName,
    required this.projectName,
    required this.applicationId,
  });

  final String displayName;
  final String projectName;
  final String applicationId;

  String get organization {
    final segments = applicationId.split('.');
    return segments.take(segments.length - 1).join('.');
  }

  String get generatedAndroidApplicationId => '$organization.$projectName';

  String get generatedAppleApplicationId {
    final parts = projectName.split('_');
    final appleName = [
      parts.first,
      ...parts.skip(1).map(
            (part) => part.isEmpty
                ? ''
                : '${part[0].toUpperCase()}${part.substring(1)}',
          ),
    ].join();
    return '$organization.$appleName';
  }
}
