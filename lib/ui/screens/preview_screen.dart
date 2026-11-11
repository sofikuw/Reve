import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/file_item.dart';
import '../../providers/reve_provider.dart';

/// Full-screen gallery: swipe/click through the files of a folder, pinch to
/// zoom images, read text in place, and hand anything else to the OS.
class PreviewScreen extends StatefulWidget {
  final ReveProvider provider;
  final List<GithubFileItem> items;
  final int initialIndex;

  const PreviewScreen({
    super.key,
    required this.provider,
    required this.items,
    required this.initialIndex,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  late final PageController _pages = PageController(initialPage: widget.initialIndex);
  final Map<String, Future<String>> _texts = {};
  late int _index = widget.initialIndex;
  bool _info = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  GithubFileItem get _item => widget.items[_index];

  static String kindOf(String name) {
    final dot = name.lastIndexOf('.');
    final ext = dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
    if (const {'png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'bmp', 'ico', 'avif'}.contains(ext)) return 'image';
    if (const {'mp4', 'webm', 'mkv', 'avi', 'mov', 'ogv', 'mp3', 'wav', 'ogg', 'flac', 'm4a', 'aac', 'pdf'}.contains(ext)) {
      return 'external';
    }
    return 'text';
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final kind = kindOf(item.name);
    final url = widget.provider.downloadUrlFor(item);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            Text(
              '${_index + 1} of ${widget.items.length} · ${_formatSize(item.size)}',
              style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Copy path',
            icon: const Icon(Icons.link_outlined),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: item.path));
              _toast('Path copied');
            },
          ),
          if (url != null)
            IconButton(
              tooltip: 'Open externally',
              icon: const Icon(Icons.open_in_new),
              onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
            ),
          IconButton(
            tooltip: 'Details',
            isSelected: _info,
            icon: const Icon(Icons.info_outline),
            onPressed: () => setState(() => _info = !_info),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_info) _details(context, item),
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: widget.items.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => _page(widget.items[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _page(GithubFileItem item) {
    final url = widget.provider.downloadUrlFor(item);
    switch (kindOf(item.name)) {
      case 'image':
        return url == null
            ? const Center(child: Text('No download URL'))
            : InteractiveViewer(
                maxScale: 6,
                child: Center(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) => progress == null
                        ? child
                        : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    errorBuilder: (context, error, stack) => const Center(child: Text('Could not load this image.')),
                  ),
                ),
              );
      case 'external':
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_circle_outline, size: 64, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                Text(item.name, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                const Text('This format opens in your system viewer.', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: url == null ? null : () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open'),
                ),
              ],
            ),
          ),
        );
      default:
        return FutureBuilder<String>(
          future: _texts.putIfAbsent(item.path, () => widget.provider.readText(item)),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator(strokeWidth: 2));
            }
            if (snapshot.hasError) {
              return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('${snapshot.error}')));
            }
            final text = snapshot.data ?? '';
            return Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: SelectableText(
                    text.length > 300000 ? '${text.substring(0, 300000)}\n\n… truncated' : text,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.55),
                  ),
                ),
              ),
            );
          },
        );
    }
  }

  Widget _details(BuildContext context, GithubFileItem item) {
    final cs = Theme.of(context).colorScheme;
    final rows = {
      'Path': item.path,
      'Size': _formatSize(item.size),
      'SHA': item.sha.isEmpty ? '—' : item.sha.substring(0, item.sha.length >= 7 ? 7 : item.sha.length),
      'Type': item.type,
    };
    return Container(
      width: double.infinity,
      color: cs.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows.entries
            .map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(width: 56, child: Text(e.key, style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant))),
                      Expanded(child: Text(e.value, style: const TextStyle(fontSize: 11.5), overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  static String _formatSize(int size) {
    if (size < 1024) return '$size B';
    const units = ['KB', 'MB', 'GB'];
    var value = size / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value >= 10 ? value.round() : value.toStringAsFixed(1)} ${units[unit]}';
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
