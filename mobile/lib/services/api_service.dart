import 'package:dio/dio.dart';
import '../core/constants/api_constants.dart';
import 'auth_service.dart';

class ApiService {
  ApiService(this._authService) {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _authService.getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          // Try to re-register with device_id (anonymous user token expired)
          final deviceId = await _authService.getDeviceId();
          if (deviceId != null && !_isRetrying) {
            _isRetrying = true;
            try {
              final resp = await Dio(BaseOptions(
                baseUrl: ApiConstants.baseUrl,
                headers: {'Content-Type': 'application/json'},
              )).post('/auth/register-device', data: {
                'device_id': deviceId,
              });
              final newToken = resp.data['access_token'] as String;
              await _authService.setToken(newToken);

              // Retry the original request with new token
              error.requestOptions.headers['Authorization'] =
                  'Bearer $newToken';
              final retryResp = await _dio.fetch(error.requestOptions);
              _isRetrying = false;
              return handler.resolve(retryResp);
            } catch (_) {
              _isRetrying = false;
            }
          }
        }
        handler.next(error);
      },
    ));
  }

  final AuthService _authService;
  late final Dio _dio;
  bool _isRetrying = false;

  Future<Response> get(String path, {Map<String, dynamic>? queryParameters}) =>
      _dio.get(path, queryParameters: queryParameters);

  Future<Response> post(String path, {dynamic data}) =>
      _dio.post(path, data: data);

  Future<Response> put(String path, {dynamic data}) =>
      _dio.put(path, data: data);

  Future<Response> patch(String path, {dynamic data}) =>
      _dio.patch(path, data: data);

  Future<Response> delete(String path) => _dio.delete(path);
}
