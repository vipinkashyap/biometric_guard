import '../storage/token_store_interface.dart';

/// In-memory [TokenStoreInterface] implementation for testing.
///
/// All data is stored in a simple map and is not persisted
/// across test runs.
class FakeTokenStore implements TokenStoreInterface {
  final Map<String, String> _data = {};

  /// Access the internal data map for test assertions.
  Map<String, String> get data => Map.unmodifiable(_data);

  @override
  Future<void> store(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<String?> retrieve(String key) async {
    return _data[key];
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    _data.clear();
  }

  @override
  Future<bool> containsKey(String key) async {
    return _data.containsKey(key);
  }

  /// Clear all stored data.
  void reset() => _data.clear();
}
