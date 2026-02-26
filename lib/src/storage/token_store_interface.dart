/// Interface for custom secure token storage.
///
/// Implement this to use your own storage backend instead of the
/// default [flutter_secure_storage] implementation.
///
/// Keys are always pre-namespaced by the SDK
/// (e.g. `biometric_shield:userId:token`). Implementors do not
/// need to handle namespacing.
abstract interface class TokenStoreInterface {
  /// Store a value securely under the given key.
  Future<void> store(String key, String value);

  /// Retrieve a stored value, or null if not found.
  Future<String?> retrieve(String key);

  /// Delete a single stored value.
  Future<void> delete(String key);

  /// Delete all values managed by this store.
  Future<void> deleteAll();

  /// Check if a key exists in the store.
  Future<bool> containsKey(String key);
}
