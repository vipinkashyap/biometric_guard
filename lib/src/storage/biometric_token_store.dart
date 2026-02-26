import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'token_store_interface.dart';

/// Default [TokenStoreInterface] implementation backed by
/// [flutter_secure_storage].
///
/// Uses the platform keychain (iOS) or RSA OAEP + AES-GCM (Android)
/// for secure at-rest storage of tokens and session data.
class BiometricTokenStore implements TokenStoreInterface {
  BiometricTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  static const _storagePrefix = 'biometric_shield';

  final FlutterSecureStorage _storage;

  String _prefixedKey(String key) => '$_storagePrefix:$key';

  @override
  Future<void> store(String key, String value) async {
    await _storage.write(key: _prefixedKey(key), value: value);
  }

  @override
  Future<String?> retrieve(String key) async {
    return _storage.read(key: _prefixedKey(key));
  }

  @override
  Future<void> delete(String key) async {
    await _storage.delete(key: _prefixedKey(key));
  }

  @override
  Future<void> deleteAll() async {
    // Read all keys and delete only those with our prefix
    final allEntries = await _storage.readAll();
    for (final key in allEntries.keys) {
      if (key.startsWith(_storagePrefix)) {
        await _storage.delete(key: key);
      }
    }
  }

  @override
  Future<bool> containsKey(String key) async {
    return _storage.containsKey(key: _prefixedKey(key));
  }
}
