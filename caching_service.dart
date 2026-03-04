import 'package:get_storage/get_storage.dart';

class CachingService {
  CachingService._internal();

  static final CachingService instance = CachingService._internal();

  factory CachingService() {
    return instance;
  }

  final GetStorage _storage = GetStorage();

  Future<CachingService> init() async {
    await GetStorage.init();
    return this;
  }

  Future<void> saveData(String key, dynamic value) async {
    await _storage.write(key, value);
  }

  dynamic getData(String key) {
    return _storage.read(key);
  }

  Set<String> getKeys() {
    return _storage.getKeys();
  }

  bool hasData(String key) {
    return _storage.hasData(key);
  }

  Future<void> removeData(String key) async {
    await _storage.remove(key);
  }

  Future<void> clearAll() async {
    await _storage.erase();
  }
}
