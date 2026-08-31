enum TargetPlatform { android, ios, web, macos, windows, linux }

final class ProjectAnswers {
  ProjectAnswers({
    required this.displayName,
    required this.projectName,
    required this.applicationId,
    required Set<TargetPlatform> platforms,
    required this.usesApi,
    required this.apiBaseUri,
    required this.usesAuthentication,
    required this.usesRefreshTokens,
    required this.includesSampleApi,
  }) : platforms = Set.unmodifiable(platforms) {
    if (platforms.isEmpty) {
      throw ArgumentError('Select at least one target platform.');
    }
    if (usesApi && apiBaseUri == null) {
      throw ArgumentError('API projects require an HTTP(S) base URI.');
    }
    if (!usesApi &&
        (apiBaseUri != null ||
            usesAuthentication ||
            usesRefreshTokens ||
            includesSampleApi)) {
      throw ArgumentError('API-only options require API support.');
    }
    if (!usesAuthentication && usesRefreshTokens) {
      throw ArgumentError('Refresh tokens require authentication.');
    }
  }

  final String displayName;
  final String projectName;
  final String applicationId;
  final Set<TargetPlatform> platforms;
  final bool usesApi;
  final Uri? apiBaseUri;
  final bool usesAuthentication;
  final bool usesRefreshTokens;
  final bool includesSampleApi;

  factory ProjectAnswers.base({
    required String displayName,
    required String projectName,
    required String applicationId,
    required Set<TargetPlatform> platforms,
  }) {
    return ProjectAnswers(
      displayName: displayName,
      projectName: projectName,
      applicationId: applicationId,
      platforms: platforms,
      usesApi: false,
      apiBaseUri: null,
      usesAuthentication: false,
      usesRefreshTokens: false,
      includesSampleApi: false,
    );
  }

  ProjectAnswers copyWith({
    String? displayName,
    String? projectName,
    String? applicationId,
    Set<TargetPlatform>? platforms,
    bool? usesApi,
    Uri? apiBaseUri,
    bool clearApiBaseUri = false,
    bool? usesAuthentication,
    bool? usesRefreshTokens,
    bool? includesSampleApi,
  }) {
    final nextUsesApi = usesApi ?? this.usesApi;
    return ProjectAnswers(
      displayName: displayName ?? this.displayName,
      projectName: projectName ?? this.projectName,
      applicationId: applicationId ?? this.applicationId,
      platforms: platforms ?? this.platforms,
      usesApi: nextUsesApi,
      apiBaseUri: nextUsesApi
          ? (clearApiBaseUri ? null : apiBaseUri ?? this.apiBaseUri)
          : null,
      usesAuthentication:
          nextUsesApi ? (usesAuthentication ?? this.usesAuthentication) : false,
      usesRefreshTokens:
          nextUsesApi ? (usesRefreshTokens ?? this.usesRefreshTokens) : false,
      includesSampleApi:
          nextUsesApi ? (includesSampleApi ?? this.includesSampleApi) : false,
    );
  }
}
