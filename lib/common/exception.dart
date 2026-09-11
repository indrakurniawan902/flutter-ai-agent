class ServerException implements Exception {
  final String message;
  final int? statusCode;
  const ServerException([this.message = 'Server error occurred', this.statusCode]);
}

class CacheException implements Exception {
  final String message;
  const CacheException([this.message = 'Cache error occurred']);
}
