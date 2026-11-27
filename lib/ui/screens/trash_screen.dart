import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/file_item.dart';
import '../../models/trash_entry.dart';
import '../../providers/reve_provider.dart';
import '../kit.dart';

/// Deleted files wait here until restored or permanently removed. Release
/// assets are kept intact in the store until they are purged from this list.
class TrashScreen extends StatelessWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReveProvider>();
    final cs = Theme.of(context).colorScheme;
    final items = provider.trash;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trash'),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Empty trash?'),
                    content: const Text(
                      'Release assets in the trash will be permanently deleted from GitHub.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('Empty'),
                      ),
                    ],
                  ),
                );
                if (ok == true) await provider.emptyTrash();
              },
              child: const Text('Empty'),
            ),
        ],
      ),
      body: items.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_sweep_outlined, size: 48, color: cs.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Text(
                    'Trash is empty',
                    style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 30),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final entry = items[index];
                return Card(
                  child: ListTile(
                    leading: KindTile(
                      kind: entry.isAsset
                          ? 'file'
                          : entry.isDirectory
                              ? 'dir'
                              : fileKind(entry.name),
                      size: 38,
                    ),
                    title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${entry.path} · ${formatBytes(entry.size)} · '
                      '${_when(entry.deletedAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Restore',
                          icon: const Icon(Icons.restore_rounded),
                          onPressed: () => provider.restoreTrash(entry),
                        ),
                        IconButton(
                          tooltip: 'Delete forever',
                          icon: Icon(Icons.delete_forever_outlined, color: cs.error),
                          onPressed: () => provider.purgeTrash(entry),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  String _when(DateTime at) {
    final minutes = DateTime.now().difference(at).inMinutes;
    if (minutes < 1) return 'just now';
    if (minutes < 60) return '$minutes min ago';
    final hours = minutes ~/ 60;
    if (hours < 24) return '${hours}h ago';
    return '${hours ~/ 24}d ago';
  }
}
