class ServerException implements Exception {
  const ServerException();
}

class DatabaseException implements Exception {
  final String message;
  const DatabaseException(this.message);
}

class CacheException implements Exception {
  final String message;
  const CacheException(this.message);
}
