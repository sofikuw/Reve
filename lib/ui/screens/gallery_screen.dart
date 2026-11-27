import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/file_item.dart';
import '../../providers/reve_provider.dart';
import '../kit.dart';
import 'preview_screen.dart';

/// A media-only view of every cached folder in the active repository.
class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReveProvider>();
    final cs = Theme.of(context).colorScheme;
    final media = provider
        .allCachedItems()
        .where((item) {
          final kind = fileKind(item.name);
          return kind == 'image' || kind == 'video';
        })
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gallery'),
        bottom: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '${media.length} photo${media.length == 1 ? '' : 's'} and video${media.length == 1 ? '' : 's'}',
            style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
          ),
        ),
      ),
      body: media.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.photo_library_outlined, size: 48, color: cs.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Text('No media cached yet', style: TextStyle(color: cs.onSurfaceVariant)),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(10),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 140,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.9,
              ),
              itemCount: media.length,
              itemBuilder: (context, index) {
                final item = media[index];
                return FileCard(
                  item: item,
                  imageUrl: provider.selectedRepo?['private'] == true
                      ? null
                      : provider.downloadUrlFor(item),
                  selected: false,
                  selecting: false,
                  onTap: () {
                    final siblings = media.where((m) => !m.isDirectory).toList();
                    final at = siblings.indexWhere((m) => m.path == item.path);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        fullscreenDialog: true,
                        builder: (_) => PreviewScreen(
                          provider: provider,
                          items: siblings,
                          initialIndex: at < 0 ? 0 : at,
                        ),
                      ),
                    );
                  },
                  onLongPress: () => provider.toggleStar(item.path),
                );
              },
            ),
    );
  }
}
