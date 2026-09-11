import 'package:flutter/material.dart';
import '../state/ui_state.dart';

/// Reusable widget builder that enforces complete UiState handling.
///
/// Mandated by Architecture Spec §2.5:
/// Every screen must handle Loading, Error, and Success states.
/// Prevents blank white screens on first load or on errors.
class UiStateBuilder<T> extends StatelessWidget {
  final UiState<T> state;
  final Widget Function(BuildContext context, T data) onSuccess;
  final Widget Function(BuildContext context)? onLoading;
  final Widget Function(BuildContext context, String message)? onError;
  final VoidCallback? onRetry;

  const UiStateBuilder({
    super.key,
    required this.state,
    required this.onSuccess,
    this.onLoading,
    this.onError,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      UiLoading<T>() => onLoading != null
          ? onLoading!(context)
          : const Center(
              child: CircularProgressIndicator(),
            ),
      UiError<T>(:final message) => onError != null
          ? onError!(context, message)
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 48,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                    if (onRetry != null) ...[
                      const SizedBox(height: 16),
                      FilledButton.tonalIcon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
      UiSuccess<T>(:final data) => onSuccess(context, data),
    };
  }
}
