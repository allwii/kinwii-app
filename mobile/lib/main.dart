import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'router/app_router.dart';
import 'services/cache_service.dart';

final cacheServiceProvider = Provider<CacheService>((ref) => CacheService());

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cache = CacheService();
  await cache.init();
  runApp(ProviderScope(
    overrides: [
      cacheServiceProvider.overrideWithValue(cache),
    ],
    child: const KinwiiApp(),
  ));
}

class KinwiiApp extends ConsumerWidget {
  const KinwiiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Kinwii',
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
