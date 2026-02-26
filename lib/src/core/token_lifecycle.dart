/// Interface for backend-agnostic token lifecycle management.
///
/// Implement this to integrate BiometricShield with any backend service.
/// The SDK calls these methods at the appropriate moments in the auth flow,
/// so your backend adapter handles the actual network calls.
///
/// ## Usage with different backends:
///
/// **Firebase:**
/// ```dart
/// class FirebaseTokenLifecycle implements TokenLifecycle {
///   @override
///   Future<TokenStatus> validate(String token) async {
///     try {
///       final user = FirebaseAuth.instance.currentUser;
///       final result = await user?.getIdTokenResult();
///       if (result == null) return TokenStatus.missing;
///       if (result.expirationTime!.isBefore(DateTime.now())) {
///         return TokenStatus.expired;
///       }
///       return TokenStatus.valid;
///     } catch (_) {
///       return TokenStatus.invalid;
///     }
///   }
///
///   @override
///   Future<TokenRefreshResult> refresh(String expiredToken) async {
///     final user = FirebaseAuth.instance.currentUser;
///     final newToken = await user?.getIdToken(true);
///     if (newToken == null) return TokenRefreshResult.failed();
///     return TokenRefreshResult.success(newToken: newToken);
///   }
/// }
/// ```
///
/// **REST API with JWT + refresh token:**
/// ```dart
/// class JwtTokenLifecycle implements TokenLifecycle {
///   final ApiClient api;
///   JwtTokenLifecycle(this.api);
///
///   @override
///   Future<TokenStatus> validate(String token) async {
///     final payload = Jwt.decode(token);
///     if (payload.isExpired) return TokenStatus.expired;
///     return TokenStatus.valid;
///   }
///
///   @override
///   Future<TokenRefreshResult> refresh(String expiredToken) async {
///     final response = await api.post('/auth/refresh', body: {
///       'refresh_token': expiredToken,
///     });
///     if (response.ok) {
///       return TokenRefreshResult.success(
///         newToken: response.body['access_token'],
///         metadata: {'refresh_token': response.body['refresh_token']},
///       );
///     }
///     return response.status == 401
///         ? TokenRefreshResult.reauthRequired()
///         : TokenRefreshResult.failed(reason: response.body['error']);
///   }
/// }
/// ```
///
/// **Supabase:**
/// ```dart
/// class SupabaseTokenLifecycle implements TokenLifecycle {
///   final SupabaseClient client;
///   SupabaseTokenLifecycle(this.client);
///
///   @override
///   Future<TokenStatus> validate(String token) async {
///     final session = client.auth.currentSession;
///     if (session == null) return TokenStatus.missing;
///     if (session.isExpired) return TokenStatus.expired;
///     return TokenStatus.valid;
///   }
///
///   @override
///   Future<TokenRefreshResult> refresh(String expiredToken) async {
///     final response = await client.auth.refreshSession();
///     final session = response.session;
///     if (session == null) return TokenRefreshResult.reauthRequired();
///     return TokenRefreshResult.success(
///       newToken: session.accessToken,
///       metadata: {'refresh_token': session.refreshToken},
///     );
///   }
/// }
/// ```
abstract class TokenLifecycle {
  /// Validate a stored token without making a network call if possible.
  ///
  /// Called by the SDK when a stored token is retrieved after successful
  /// biometric auth. If [TokenStatus.expired], the SDK will automatically
  /// call [refresh]. If [TokenStatus.invalid] or [TokenStatus.missing],
  /// the SDK emits [BiometricResult.tokenExpired].
  ///
  /// For JWTs, decode and check the `exp` claim locally.
  /// For opaque tokens, you may need a network call.
  Future<TokenStatus> validate(String token);

  /// Attempt to refresh an expired token.
  ///
  /// Called automatically when [validate] returns [TokenStatus.expired].
  /// The implementation should exchange the expired credential for a new one
  /// using whatever mechanism the backend supports (refresh token, Firebase
  /// token refresh, Supabase session refresh, etc).
  ///
  /// Return [TokenRefreshResult.success] with the new token to continue.
  /// Return [TokenRefreshResult.reauthRequired] if the refresh token is also
  /// expired and the user must re-authenticate from scratch (OAuth, login, etc).
  /// Return [TokenRefreshResult.failed] for transient errors (network, etc).
  Future<TokenRefreshResult> refresh(String expiredToken);
}

/// Status of a stored token after validation.
enum TokenStatus {
  /// Token is valid and can be used as-is.
  valid,

  /// Token has expired but may be refreshable.
  expired,

  /// Token is invalid (tampered, revoked, wrong format, etc).
  invalid,

  /// No token was found in storage.
  missing,
}

/// Result of a token refresh attempt.
sealed class TokenRefreshResult {
  const TokenRefreshResult();

  /// Refresh succeeded. [newToken] replaces the old one in secure storage.
  /// [metadata] can carry additional data (e.g., a new refresh token)
  /// which is emitted via [BiometricEvent] for the caller to handle.
  const factory TokenRefreshResult.success({
    required String newToken,
    Map<String, dynamic> metadata,
  }) = TokenRefreshSuccess;

  /// Refresh failed due to a transient error (network, server 500, etc).
  /// The SDK will emit [BiometricResult.error] and the caller can retry.
  const factory TokenRefreshResult.failed({
    String? reason,
  }) = TokenRefreshFailed;

  /// The refresh token itself is expired or revoked.
  /// The user must re-authenticate from scratch (OAuth flow, login screen, etc).
  /// The SDK will emit [BiometricResult.reauthenticationRequired].
  const factory TokenRefreshResult.reauthRequired() = TokenRefreshReauthRequired;
}

/// Refresh succeeded.
class TokenRefreshSuccess extends TokenRefreshResult {
  const TokenRefreshSuccess({
    required this.newToken,
    this.metadata = const {},
  });

  /// The new token to store.
  final String newToken;

  /// Additional metadata (e.g., new refresh token, expiry hint).
  /// Emitted as event properties for the caller to handle.
  final Map<String, dynamic> metadata;
}

/// Refresh failed due to a transient error.
class TokenRefreshFailed extends TokenRefreshResult {
  const TokenRefreshFailed({this.reason});

  /// Optional human-readable reason for the failure.
  final String? reason;
}

/// The refresh token itself is expired; full re-auth needed.
class TokenRefreshReauthRequired extends TokenRefreshResult {
  const TokenRefreshReauthRequired();
}
