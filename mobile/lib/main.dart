import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'core/theme/app_theme.dart';
import 'router/app_router.dart';
import 'services/cache_service.dart';
import 'services/local_notification_service.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final cacheServiceProvider = Provider<CacheService>((ref) => CacheService());
final localNotificationProvider =
    Provider<LocalNotificationService>((ref) => LocalNotificationService());

// RevenueCat API keys — pass via --dart-define
const _rcIosKey = String.fromEnvironment('REVENUECAT_IOS_KEY');
const _rcAndroidKey = String.fromEnvironment('REVENUECAT_ANDROID_KEY');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize RevenueCat
  final rcKey = Platform.isIOS ? _rcIosKey : _rcAndroidKey;
  if (rcKey.isNotEmpty) {
    await Purchases.setLogLevel(LogLevel.info);
    await Purchases.configure(PurchasesConfiguration(rcKey));
  }

  final cache = CacheService();
  await cache.init();
  final notifications = LocalNotificationService();
  LocalNotificationService.navigatorKey = rootNavigatorKey;
  await notifications.init();
  await notifications.requestPermissions();
  await notifications.scheduleDefaults();
  runApp(ProviderScope(
    overrides: [
      cacheServiceProvider.overrideWithValue(cache),
      localNotificationProvider.overrideWithValue(notifications),
    ],
    child: const KinwiiApp(),
  ));
}

class KinwiiApp extends ConsumerWidget {
  const KinwiiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    // Handle cold-start notification tap after router is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LocalNotificationService.handlePendingNotification();
    });

    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: MaterialApp.router(
        title: 'Kinwii',
        theme: AppTheme.light,
        routerConfig: router,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
