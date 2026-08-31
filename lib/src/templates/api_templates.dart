const apiTemplates = <String, String>{
  'lib/core/constant/endpoints.dart': r'''abstract final class Endpoints {
  static const baseUrl = '{{api_base_url}}';
  static const sampleItems = '/items';
  static const signIn = '/auth/sign-in';
  static const refreshToken = '/auth/refresh';
}
''',
  'lib/core/exceptions/exception_message.dart': r'''class ExceptionMessage {
  const ExceptionMessage({required this.code, required this.message});

  final int code;
  final String message;

  static const noInternet = ExceptionMessage(
    code: 503,
    message: 'No internet connection. Please try again.',
  );
}
''',
  'lib/core/exceptions/api_exception.dart': r'''import 'package:dio/dio.dart';

import 'exception_message.dart';

class ApiException implements Exception {
  const ApiException(this.exception);

  final ExceptionMessage exception;

  factory ApiException.fromDio(DioException error) {
    final response = error.response;
    final data = response?.data;
    final backendMessage = data is Map
        ? (data['message'] ?? data['error'])?.toString()
        : null;
    final message = backendMessage ?? _messageFor(error.type);
    return ApiException(
      ExceptionMessage(
        code: response?.statusCode ?? _codeFor(error.type),
        message: message,
      ),
    );
  }

  static int _codeFor(DioExceptionType type) => switch (type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.transformTimeout => 408,
    DioExceptionType.cancel => 499,
    DioExceptionType.connectionError ||
    DioExceptionType.badCertificate => 503,
    DioExceptionType.badResponse || DioExceptionType.unknown => 500,
  };

  static String _messageFor(DioExceptionType type) => switch (type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.transformTimeout => 'The request timed out. Please try again.',
    DioExceptionType.cancel => 'The request was cancelled.',
    DioExceptionType.connectionError => 'Could not connect to the server.',
    DioExceptionType.badCertificate => 'The server certificate is not trusted.',
    DioExceptionType.badResponse => 'The server could not complete the request.',
    DioExceptionType.unknown => 'Something went wrong. Please try again.',
  };

  @override
  String toString() => exception.message;
}
''',
  'lib/core/exceptions/failure.dart': r'''class Failure<T> {
  const Failure({required this.exception});

  final T exception;
}
''',
  'lib/core/network/network_info.dart':
      r'''import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

abstract interface class NetworkInfo {
  Future<bool> get isConnected;
}

class NetworkInfoImpl implements NetworkInfo {
  const NetworkInfoImpl(this._connection);

  final InternetConnection _connection;

  @override
  Future<bool> get isConnected => _connection.hasInternetAccess;
}

final networkInfoProvider = Provider<NetworkInfo>((ref) {
  return NetworkInfoImpl(InternetConnection());
});
''',
  'lib/core/network/dio_provider.dart': r'''import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constant/endpoints.dart';

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
  'lib/core/services/services.dart': r'''import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../exceptions/api_exception.dart';
import '../network/dio_provider.dart';

final servicesProvider = Provider<Services>((ref) {
  return Services(ref.watch(dioProvider));
});

class Services {
  const Services(this._dio);

  final Dio _dio;

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _guard(
      () => _dio.get<T>(
        path,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      ),
    );
  }

  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
  }) {
    return _guard(
      () => _dio.post<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
      ),
    );
  }

  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Options? options,
    CancelToken? cancelToken,
  }) => _guard(
    () => _dio.put<T>(path, data: data, options: options, cancelToken: cancelToken),
  );

  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Options? options,
    CancelToken? cancelToken,
  }) => _guard(
    () => _dio.patch<T>(path, data: data, options: options, cancelToken: cancelToken),
  );

  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Options? options,
    CancelToken? cancelToken,
  }) => _guard(
    () => _dio.delete<T>(path, data: data, options: options, cancelToken: cancelToken),
  );

  Future<Response<T>> multipart<T>(
    String path, {
    required FormData data,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
  }) => post<T>(
    path,
    data: data,
    cancelToken: cancelToken,
    onSendProgress: onSendProgress,
  );

  Future<Response<T>> _guard<T>(Future<Response<T>> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
''',
  'test/core/exceptions/api_exception_test.dart':
      r'''import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:{{project_name}}/core/exceptions/api_exception.dart';

void main() {
  test('maps a connection timeout to a user-safe timeout', () {
    final exception = ApiException.fromDio(
      DioException(
        requestOptions: RequestOptions(path: '/items'),
        type: DioExceptionType.connectionTimeout,
      ),
    );

    expect(exception.exception.code, 408);
    expect(exception.exception.message, contains('timed out'));
  });
}
''',
};
