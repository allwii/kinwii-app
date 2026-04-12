import 'package:google_sign_in/google_sign_in.dart';

import 'api_service.dart';
import 'auth_service.dart';

class GoogleAuthService {
  GoogleAuthService(this._api, this._auth);

  final ApiService _api;
  final AuthService _auth;

  /// Sign in with Google. Returns true if successful.
  Future<bool> signIn() async {
    final googleSignIn = GoogleSignIn.instance;

    // Trigger the Google sign-in flow
    final account = await googleSignIn.authenticate();

    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw Exception('Google sign-in failed: no ID token received.');
    }

    // Send ID token to our backend for verification
    final response = await _api.post('/auth/google', data: {
      'id_token': idToken,
    });

    final token = response.data['access_token'] as String;
    await _auth.setToken(token);
    return true;
  }

  /// Sign out of Google (clears cached Google session).
  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.disconnect();
    } catch (_) {
      // Silent
    }
  }
}
