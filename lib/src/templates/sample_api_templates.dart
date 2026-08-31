const sampleApiTemplates = <String, String>{
  'lib/domain/models/sample_item_model.dart': r'''class SampleItemModel {
  SampleItemModel({
    required this.id,
    required this.title,
    required this.description,
    required this.message,
  });

  final int id;
  final String title;
  final String description;
  final String message;

  factory SampleItemModel.empty() => SampleItemModel(
    id: 0,
    title: '',
    description: '',
    message: '',
  );

  factory SampleItemModel.fromJson(Map<String, dynamic>? json) {
    final payload = _payloadMap(json);
    return SampleItemModel(
      id: (payload['id'] as num?)?.toInt() ?? 0,
      title: (payload['title'] ?? '').toString(),
      description: (payload['description'] ?? payload['body'] ?? '').toString(),
      message: (payload['message'] ?? '').toString(),
    );
  }

  static List<SampleItemModel> fromJsonList(dynamic json) {
    final data = json is Map ? json['data'] : json;
    final list = data is List ? data : const [];
    return list
        .whereType<Map>()
        .map(
          (item) => SampleItemModel.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList(growable: false);
  }

  static Map<String, dynamic> _payloadMap(Map<String, dynamic>? json) {
    json ??= {};
    final data = json['data'];
    if (data is Map) {
      return {
        ...Map<String, dynamic>.from(data),
        'message': json['message'],
      };
    }
    return json;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
  };

  SampleItemModel copyWith({
    int? id,
    String? title,
    String? description,
    String? message,
  }) {
    return SampleItemModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      message: message ?? this.message,
    );
  }
}
''',
  'lib/data/remote-apis/abst_remote/sample_remote_data_source.dart':
      r'''import '../../../domain/models/sample_item_model.dart';

abstract interface class SampleRemoteDataSource {
  Future<List<SampleItemModel>> fetchItems();
}
''',
  'lib/data/remote-apis/remote/sample_remote_data_source_impl.dart':
      r'''import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constant/endpoints.dart';
import '../../../core/services/services.dart';
import '../../../domain/models/sample_item_model.dart';
import '../abst_remote/sample_remote_data_source.dart';

class SampleRemoteDataSourceImpl implements SampleRemoteDataSource {
  const SampleRemoteDataSourceImpl(this._services);

  final Services _services;

  @override
  Future<List<SampleItemModel>> fetchItems() async {
    final response = await _services.get<dynamic>(Endpoints.sampleItems);
    return SampleItemModel.fromJsonList(response.data);
  }
}

final sampleRemoteDataSourceProvider = Provider<SampleRemoteDataSource>((ref) {
  return SampleRemoteDataSourceImpl(ref.watch(servicesProvider));
});
''',
  'lib/data/repository_impl/abst_repository/sample_repository.dart':
      r'''import 'package:dartz/dartz.dart';

import '../../../core/exceptions/exception_message.dart';
import '../../../core/exceptions/failure.dart';
import '../../../domain/models/sample_item_model.dart';

abstract interface class SampleRepository {
  Future<Either<Failure<ExceptionMessage>, List<SampleItemModel>>> fetchItems();
}
''',
  'lib/data/repository_impl/repository/sample_repository_impl.dart':
      r'''import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/exceptions/api_exception.dart';
import '../../../core/exceptions/exception_message.dart';
import '../../../core/exceptions/failure.dart';
import '../../../core/network/network_info.dart';
import '../../../domain/models/sample_item_model.dart';
import '../../remote-apis/abst_remote/sample_remote_data_source.dart';
import '../../remote-apis/remote/sample_remote_data_source_impl.dart';
import '../abst_repository/sample_repository.dart';

class SampleRepositoryImpl implements SampleRepository {
  const SampleRepositoryImpl({
    required NetworkInfo networkInfo,
    required SampleRemoteDataSource remoteDataSource,
  }) : _networkInfo = networkInfo,
       _remoteDataSource = remoteDataSource;

  final NetworkInfo _networkInfo;
  final SampleRemoteDataSource _remoteDataSource;

  @override
  Future<Either<Failure<ExceptionMessage>, List<SampleItemModel>>>
  fetchItems() async {
    if (!await _networkInfo.isConnected) {
      return const Left(Failure(exception: ExceptionMessage.noInternet));
    }
    try {
      return Right(await _remoteDataSource.fetchItems());
    } on ApiException catch (error) {
      return Left(Failure(exception: error.exception));
    }
  }
}

final sampleRepositoryProvider = Provider<SampleRepository>((ref) {
  return SampleRepositoryImpl(
    networkInfo: ref.watch(networkInfoProvider),
    remoteDataSource: ref.watch(sampleRemoteDataSourceProvider),
  );
});
''',
  'lib/business/sample/sample_items_viewmodel.dart':
      r'''import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repository_impl/repository/sample_repository_impl.dart';
import '../../domain/models/sample_item_model.dart';

final sampleItemsViewModelProvider =
    NotifierProvider<SampleItemsViewModel, AsyncValue<List<SampleItemModel>>>(
      SampleItemsViewModel.new,
    );

class SampleItemsViewModel
    extends Notifier<AsyncValue<List<SampleItemModel>>> {
  bool _hasLoadedOnce = false;
  bool _isFetching = false;

  @override
  AsyncValue<List<SampleItemModel>> build() => const AsyncValue.data([]);

  Future<List<SampleItemModel>?> fetch({bool showLoader = true}) async {
    if (_isFetching) return null;
    _isFetching = true;
    if (showLoader && !_hasLoadedOnce) {
      state = const AsyncValue.loading();
    }
    final result = await ref.read(sampleRepositoryProvider).fetchItems();
    _isFetching = false;
    return result.fold(
      (failure) {
        if (!_hasLoadedOnce) {
          state = AsyncValue.error(
            failure.exception.message,
            StackTrace.current,
          );
        }
        return null;
      },
      (items) {
        state = AsyncValue.data(items);
        _hasLoadedOnce = true;
        return items;
      },
    );
  }
}
''',
  'lib/presentation/screens/sample_items_screen.dart':
      r'''import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../business/sample/sample_items_viewmodel.dart';
import '../../domain/models/sample_item_model.dart';

@RoutePage()
class SampleItemsScreen extends ConsumerStatefulWidget {
  const SampleItemsScreen({super.key});

  @override
  ConsumerState<SampleItemsScreen> createState() => _SampleItemsScreenState();
}

class _SampleItemsScreenState extends ConsumerState<SampleItemsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sampleItemsViewModelProvider.notifier).fetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sampleItemsViewModelProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Sample API items')),
      body: SafeArea(
        child: state.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _buildError(error),
          data: _buildItems,
        ),
      ),
    );
  }

  Widget _buildItems(List<SampleItemModel> items) {
    return RefreshIndicator(
      onRefresh: _handleRefresh,
      child: items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 180),
                Icon(Icons.inbox_outlined, size: 48),
                SizedBox(height: 12),
                Center(child: Text('No sample items yet. Pull to refresh.')),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _buildItemCard(items[index]),
            ),
    );
  }

  Widget _buildItemCard(SampleItemModel item) {
    return Card(
      key: ValueKey(item.id),
      child: ListTile(
        contentPadding: const EdgeInsets.all(18),
        title: Text(item.title),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(item.description),
        ),
      ),
    );
  }

  Widget _buildError(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 16),
            Text(error.toString(), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton(onPressed: _handleRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }

  Future<void> _handleRefresh() async {
    await ref.read(sampleItemsViewModelProvider.notifier).fetch(showLoader: false);
  }

  void _handleRetry() {
    ref.read(sampleItemsViewModelProvider.notifier).fetch();
  }
}
''',
  'lib/core/route/app_router.dart':
      r'''import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../presentation/screens/home_screen.dart';
import '../../presentation/screens/sample_items_screen.dart';

part 'app_router.gr.dart';

final appRouterProvider = Provider<AppRouter>((ref) {
  final router = AppRouter();
  ref.onDispose(router.dispose);
  return router;
});

@AutoRouterConfig(replaceInRouteName: 'Screen,Route')
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: HomeRoute.page, initial: true),
    AutoRoute(page: SampleItemsRoute.page),
  ];
}
''',
  'test/domain/models/sample_item_model_test.dart':
      r'''import 'package:flutter_test/flutter_test.dart';
import 'package:{{project_name}}/domain/models/sample_item_model.dart';

void main() {
  test('defensively parses a standard response envelope', () {
    final model = SampleItemModel.fromJson({
      'message': 'Loaded',
      'data': {'id': 7, 'title': 'Example', 'body': 'Ready'},
    });

    expect(model.id, 7);
    expect(model.title, 'Example');
    expect(model.description, 'Ready');
    expect(model.message, 'Loaded');
  });
}
''',
};
