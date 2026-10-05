abstract class AppException implements Exception {
  AppException(this.message, {this.code, this.details});

  final String message;
  final String? code;
  final dynamic details;

  @override
  String toString() => '$runtimeType: $message${code != null ? ' (code: $code)' : ''}';
}

class ExportException extends AppException {
  ExportException(super.message, {super.code, super.details});
}

class PermissionException extends AppException {
  PermissionException(super.message, {super.code, super.details});
}

class StorageException extends AppException {
  StorageException(super.message, {super.code, super.details});
}

class ProjectException extends AppException {
  ProjectException(super.message, {super.code, super.details});
}

class MediaProcessingException extends AppException {
  MediaProcessingException(super.message, {super.code, super.details});
}
