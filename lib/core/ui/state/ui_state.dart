/// Generic UI state representation.
///
/// Mandated by Architecture Spec §2.5 and [FIX-ARCH-STATE-1]:
/// Every ViewModel/StateNotifier exposes a sealed UiState.
/// Every screen must handle Loading, Success, and Error states.
sealed class UiState<T> {
  const UiState();

  const factory UiState.loading() = Loading<T>;
  const factory UiState.success(T data) = Success<T>;
  const factory UiState.error(String message) = UiError<T>;

  bool get isLoading => this is Loading<T>;
  bool get isSuccess => this is Success<T>;
  bool get isError => this is UiError<T>;

  T? get dataOrNull => switch (this) {
        Success<T>(:final data) => data,
        _ => null,
      };

  String? get errorOrNull => switch (this) {
        UiError<T>(:final message) => message,
        _ => null,
      };

  R when<R>({
    required R Function() loading,
    required R Function(T data) success,
    required R Function(String message) error,
  }) {
    return switch (this) {
      Loading<T>() => loading(),
      Success<T>(:final data) => success(data),
      UiError<T>(:final message) => error(message),
    };
  }

  R maybeWhen<R>({
    R Function()? loading,
    R Function(T data)? success,
    R Function(String message)? error,
    required R Function() orElse,
  }) {
    return switch (this) {
      Loading<T>() => loading != null ? loading() : orElse(),
      Success<T>(:final data) => success != null ? success(data) : orElse(),
      UiError<T>(:final message) => error != null ? error(message) : orElse(),
    };
  }
}

/// Loading state (§2.5)
final class Loading<T> extends UiState<T> {
  const Loading();

  @override
  String toString() => 'UiState<$T>.loading()';

  @override
  bool operator ==(Object other) => identical(this, other) || other is Loading<T>;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// Success state with payload data (§2.5)
final class Success<T> extends UiState<T> {
  final T data;
  const Success(this.data);

  @override
  String toString() => 'UiState<$T>.success($data)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Success<T> && runtimeType == other.runtimeType && data == other.data;

  @override
  int get hashCode => Object.hash(runtimeType, data);
}

/// Error state with failure message (§2.5 & [FIX-UISTATE-NAME-1])
/// Named UiError, NOT Error, to avoid shadowing dart:core's Error type.
final class UiError<T> extends UiState<T> {
  final String message;
  const UiError(this.message);

  @override
  String toString() => 'UiState<$T>.error($message)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UiError<T> && runtimeType == other.runtimeType && message == other.message;

  @override
  int get hashCode => Object.hash(runtimeType, message);
}

// Aliases for compatibility
typedef UiLoading<T> = Loading<T>;
typedef UiSuccess<T> = Success<T>;
