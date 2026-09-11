import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/ui/state/ui_state.dart';

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
  });
}
