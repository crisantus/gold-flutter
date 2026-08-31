const authTemplates = <String, String>{
  'lib/core/network/token_storage.dart':
      r'''import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class TokenStorage {
  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();
  Future<void> saveTokens({required String accessToken, String? refreshToken});
  Future<void> clear();
}

class SecureTokenStorage implements TokenStorage {
  const SecureTokenStorage(this._storage);

  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  @override
  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _storage.write(key: _refreshTokenKey, value: refreshToken);
    }
  }

  @override
  Future<void> clear() => _storage.deleteAll();
}

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return const SecureTokenStorage(FlutterSecureStorage());
});
''',
  'lib/core/network/session_manager.dart':
      r'''import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'token_storage.dart';

abstract interface class SessionManager {
  Future<void> clearSession();
}

class SessionManagerImpl implements SessionManager {
  const SessionManagerImpl(this._tokenStorage);

  final TokenStorage _tokenStorage;

  @override
  Future<void> clearSession() => _tokenStorage.clear();
}

final sessionManagerProvider = Provider<SessionManager>((ref) {
  return SessionManagerImpl(ref.watch(tokenStorageProvider));
});
''',
  'lib/core/network/authorization_interceptor.dart':
      r'''import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'token_storage.dart';

final authorizationInterceptorProvider = Provider<AuthorizationInterceptor>((ref) {
  return AuthorizationInterceptor(ref.watch(tokenStorageProvider));
});

class AuthorizationInterceptor extends Interceptor {
  AuthorizationInterceptor(this._tokenStorage);

  final TokenStorage _tokenStorage;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.extra['requiresAuth'] == false) {
      handler.next(options);
      return;
    }
    final token = await _tokenStorage.readAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}
''',
  'lib/core/network/dio_provider.dart': r'''import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constant/endpoints.dart';
import 'authorization_interceptor.dart';

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: Endpoints.baseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: const {'Accept': 'application/json'},
    ),
  );
  dio.interceptors.add(ref.watch(authorizationInterceptorProvider));
  if (kDebugMode) {
    dio.interceptors.add(
      LogInterceptor(
        requestBody: false,
        responseBody: false,
        logPrint: (value) => debugPrint(value.toString()),
      ),
    );
  }
  ref.onDispose(dio.close);
  return dio;
});
''',
  'test/core/network/authorization_interceptor_test.dart':
      r'''import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:{{project_name}}/core/network/authorization_interceptor.dart';
import 'package:{{project_name}}/core/network/token_storage.dart';

void main() {
  test('public requests remain unauthenticated', () async {
    final dio = Dio();
    dio.interceptors.add(AuthorizationInterceptor(_FakeTokenStorage()));
    final adapter = _RecordingAdapter();
    dio.httpClientAdapter = adapter;

    await dio.get<void>('/public', options: Options(extra: {'requiresAuth': false}));

    expect(adapter.authorization, isNull);
  });
}

class _FakeTokenStorage implements TokenStorage {
  @override
  Future<String?> readAccessToken() async => 'secret';
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}
  @override
  Future<void> clear() async {}
}

class _RecordingAdapter implements HttpClientAdapter {
  String? authorization;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    authorization = options.headers['Authorization']?.toString();
    return ResponseBody.fromString('', 204);
  }

  @override
  void close({bool force = false}) {}
}
''',
};

const refreshTokenTemplates = <String, String>{
  'lib/core/network/token_refresh_coordinator.dart':
      r'''import 'package:dio/dio.dart';

import '../constant/endpoints.dart';
import 'token_storage.dart';

class TokenRefreshCoordinator {
  TokenRefreshCoordinator({required Dio dio, required TokenStorage tokenStorage})
    : _dio = dio,
      _tokenStorage = tokenStorage;

  final Dio _dio;
  final TokenStorage _tokenStorage;
  Future<String?>? _inFlight;

  Future<String?> refresh() {
    final active = _inFlight;
    if (active != null) return active;
    final operation = _refresh();
    _inFlight = operation;
    return operation.whenComplete(() => _inFlight = null);
  }

  Future<String?> _refresh() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return null;
    final response = await _dio.post<dynamic>(
      Endpoints.refreshToken,
      data: {'refresh_token': refreshToken},
      options: Options(extra: {'requiresAuth': false, 'goldRefresh': true}),
    );
    final body = response.data;
    final payload = body is Map && body['data'] is Map ? body['data'] as Map : body;
    if (payload is! Map) return null;
    final accessToken = (payload['access_token'] ?? '').toString();
    if (accessToken.isEmpty) return null;
    final nextRefreshToken = (payload['refresh_token'] ?? refreshToken).toString();
    await _tokenStorage.saveTokens(
      accessToken: accessToken,
      refreshToken: nextRefreshToken,
    );
    return accessToken;
  }
}
''',
  'lib/core/network/authorization_interceptor.dart':
      r'''import 'package:dio/dio.dart';

import 'session_manager.dart';
import 'token_refresh_coordinator.dart';
import 'token_storage.dart';

class AuthorizationInterceptor extends Interceptor {
  AuthorizationInterceptor({
    required Dio dio,
    required TokenStorage tokenStorage,
    required SessionManager sessionManager,
  }) : _dio = dio,
       _tokenStorage = tokenStorage,
       _sessionManager = sessionManager,
       _refreshCoordinator = TokenRefreshCoordinator(
         dio: dio,
         tokenStorage: tokenStorage,
       );

  final Dio _dio;
  final TokenStorage _tokenStorage;
  final SessionManager _sessionManager;
  final TokenRefreshCoordinator _refreshCoordinator;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.extra['requiresAuth'] == false) {
      handler.next(options);
      return;
    }
    final token = await _tokenStorage.readAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final request = err.requestOptions;
    final canRefresh = err.response?.statusCode == 401 &&
        request.extra['requiresAuth'] != false &&
        request.extra['goldRetried'] != true &&
        request.extra['goldRefresh'] != true;
    if (!canRefresh) {
      handler.next(err);
      return;
    }
    try {
      final token = await _refreshCoordinator.refresh();
      if (token == null) {
        await _sessionManager.clearSession();
        handler.next(err);
        return;
      }
      request.extra['goldRetried'] = true;
      request.headers['Authorization'] = 'Bearer $token';
      handler.resolve(await _dio.fetch<dynamic>(request));
    } on Exception {
      await _sessionManager.clearSession();
      handler.next(err);
    }
  }
}
''',
  'lib/core/network/dio_provider.dart': r'''import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constant/endpoints.dart';
import 'authorization_interceptor.dart';
import 'session_manager.dart';
import 'token_storage.dart';

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: Endpoints.baseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: const {'Accept': 'application/json'},
    ),
  );
  dio.interceptors.add(
    AuthorizationInterceptor(
      dio: dio,
      tokenStorage: ref.watch(tokenStorageProvider),
      sessionManager: ref.watch(sessionManagerProvider),
    ),
  );
  if (kDebugMode) {
    dio.interceptors.add(
      LogInterceptor(
        requestBody: false,
        responseBody: false,
        logPrint: (value) => debugPrint(value.toString()),
      ),
    );
  }
  ref.onDispose(dio.close);
  return dio;
});
''',
  'test/core/network/authorization_interceptor_test.dart':
      r'''import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:{{project_name}}/core/network/authorization_interceptor.dart';
import 'package:{{project_name}}/core/network/session_manager.dart';
import 'package:{{project_name}}/core/network/token_storage.dart';

void main() {
  test('public requests remain unauthenticated with refresh enabled', () async {
    final dio = Dio();
    final storage = _FakeTokenStorage();
    dio.interceptors.add(
      AuthorizationInterceptor(
        dio: dio,
        tokenStorage: storage,
        sessionManager: _FakeSessionManager(storage),
      ),
    );
    final adapter = _RecordingAdapter();
    dio.httpClientAdapter = adapter;

    await dio.get<void>(
      '/public',
      options: Options(extra: {'requiresAuth': false}),
    );

    expect(adapter.authorization, isNull);
  });
}

class _FakeTokenStorage implements TokenStorage {
  @override
  Future<String?> readAccessToken() async => 'secret';
  @override
  Future<String?> readRefreshToken() async => 'refresh';
  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}
  @override
  Future<void> clear() async {}
}

class _FakeSessionManager implements SessionManager {
  _FakeSessionManager(this.storage);
  final TokenStorage storage;

  @override
  Future<void> clearSession() => storage.clear();
}

class _RecordingAdapter implements HttpClientAdapter {
  String? authorization;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    authorization = options.headers['Authorization']?.toString();
    return ResponseBody.fromString('', 204);
  }

  @override
  void close({bool force = false}) {}
}
''',
};
