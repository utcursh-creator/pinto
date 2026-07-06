import 'package:flutter/material.dart';

/// PROF-3: the one error state for async screens - a friendly line (never a
/// raw exception dump), the technical detail tucked underneath, and a Retry
/// button that re-fires the load.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({
    required this.message,
    required this.onRetry,
    this.detail,
    super.key,
  });

  final String message;
  final Object? detail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 40, color: Colors.black38),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(
                '$detail',
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.black45),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
