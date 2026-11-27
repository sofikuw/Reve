import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/reve_provider.dart';

/// Live view of the current upload/preview transfer, with a cancel control.
class TransfersScreen extends StatelessWidget {
  const TransfersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReveProvider>();
    final cs = Theme.of(context).colorScheme;
    final busy = provider.isBusy;
    return Scaffold(
      appBar: AppBar(title: const Text('Transfers')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: busy
            ? Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.cloud_upload_rounded),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              provider.progressLabel ?? 'Transferring…',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        value: provider.progress,
                        minHeight: 6,
                        backgroundColor: cs.surfaceContainerHighest,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        provider.progress == null
                            ? 'Working…'
                            : '${(provider.progress! * 100).round()}%',
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 18),
                      OutlinedButton.icon(
                        onPressed: provider.cancelTransfer,
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Cancel transfer'),
                      ),
                    ],
                  ),
                ),
              )
            : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_outline, size: 48, color: cs.primary),
                    const SizedBox(height: 12),
                    const Text('No active transfers'),
                  ],
                ),
              ),
      ),
    );
  }
}
