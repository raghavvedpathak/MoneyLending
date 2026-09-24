import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/ui/ui_state.dart';

void main() {
  group('UiState tests [FIX-ARCH-STATE-1]', () {
    test('Loading state behaves correctly', () {
      const state = UiState<String>.loading();
      expect(state.isLoading, isTrue);
      expect(state.isSuccess, isFalse);
      expect(state.isError, isFalse);
      expect(state.dataOrNull, isNull);
      expect(state.errorOrNull, isNull);

      final result = state.when(
        loading: () => 'loading_handled',
        success: (data) => 'success_handled',
        error: (msg) => 'error_handled',
      );
      expect(result, 'loading_handled');
    });

    test('Success state carries payload and handles when', () {
      const state = UiState<int>.success(42);
      expect(state.isLoading, isFalse);
      expect(state.isSuccess, isTrue);
      expect(state.isError, isFalse);
      expect(state.dataOrNull, 42);

      final result = state.when(
        loading: () => -1,
        success: (data) => data * 2,
        error: (msg) => -2,
      );
      expect(result, 84);
    });

    test('Error state carries message and handles when', () {
      const state = UiState<int>.error('Failed to load');
      expect(state.isLoading, isFalse);
      expect(state.isSuccess, isFalse);
      expect(state.isError, isTrue);
      expect(state.errorOrNull, 'Failed to load');

      final result = state.when(
        loading: () => 'loading',
        success: (data) => 'success',
        error: (msg) => 'handled: $msg',
      );
      expect(result, 'handled: Failed to load');
    });

    test('Direct Loading, Success, UiError classes and switch pattern matching (§2.5)', () {
      const UiState<int> s1 = Loading();
      const UiState<int> s2 = Success(100);
      const UiState<int> s3 = UiError('Network timeout');

      String render(UiState<int> state) => switch (state) {
            Loading() => 'spinner',
            UiError(:final message) => 'error: $message',
            Success(:final data) => 'data: $data',
          };

      expect(render(s1), 'spinner');
      expect(render(s2), 'data: 100');
      expect(render(s3), 'error: Network timeout');
    });

    test('[FIX-UISTATE-NAME-1] Error case is named UiError and matches in switch expression without shadowing dart:core Error', () {
      const UiState<String> state = UiError('Failed to fetch data');

      expect(state.isError, isTrue);
      expect(state.errorOrNull, 'Failed to fetch data');

      final rendered = switch (state) {
        Loading() => 'spinner',
        UiError(:final message) => 'handled_error: $message',
        Success(:final data) => 'data: $data',
      };
      expect(rendered, 'handled_error: Failed to fetch data');

      // Verify that catching standard dart:core Error works as expected
      try {
        throw ArgumentError('Invalid argument');
      } on Error catch (e) {
        expect(e, isA<ArgumentError>());
      }
    });
  });
}
