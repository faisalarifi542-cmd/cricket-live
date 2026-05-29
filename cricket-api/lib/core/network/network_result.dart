import 'api_exception.dart';

sealed class NetworkResult<T> {
  const NetworkResult();
}

class NetworkSuccess<T> extends NetworkResult<T> {
  final T data;
  const NetworkSuccess(this.data);
}

class NetworkError<T> extends NetworkResult<T> {
  final ApiException exception;
  const NetworkError(this.exception);
}
