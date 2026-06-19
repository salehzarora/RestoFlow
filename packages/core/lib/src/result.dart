/// A neutral functional result type: either a [Success] value or a [Failure].
///
/// Foundation utility only - it encodes no domain or business rules. Domain and
/// data code in later tickets return `Result<T, F>` instead of throwing across
/// layer boundaries (see docs/ARCHITECTURE.md section 9.2).
sealed class Result<S, F> {
  const Result();

  /// Whether this result is a [Success].
  bool get isSuccess => this is Success<S, F>;

  /// Whether this result is a [Failure].
  bool get isFailure => this is Failure<S, F>;

  /// Collapses this result to a single value of type [T].
  T fold<T>(T Function(S value) onSuccess, T Function(F failure) onFailure) {
    final self = this;
    return switch (self) {
      Success<S, F>(:final value) => onSuccess(value),
      Failure<S, F>(:final failure) => onFailure(failure),
    };
  }
}

/// A successful [Result] carrying a [value].
final class Success<S, F> extends Result<S, F> {
  const Success(this.value);

  /// The success payload.
  final S value;
}

/// A failed [Result] carrying a [failure].
final class Failure<S, F> extends Result<S, F> {
  const Failure(this.failure);

  /// The failure payload.
  final F failure;
}
