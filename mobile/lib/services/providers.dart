import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_service.dart';
import 'auth_service.dart';

final authServiceProvider = Provider((ref) => AuthService());
final apiServiceProvider = Provider((ref) {
  final authService = ref.read(authServiceProvider);
  return ApiService(authService);
});
