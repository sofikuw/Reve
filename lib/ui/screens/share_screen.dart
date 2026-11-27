import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/file_item.dart';
import '../../providers/reve_provider.dart';

/// Link sharing with copy, system share and browser open. GitHub release links
/// are read-only, which is the only permission level it can enforce.
class ShareScreen extends StatefulWidget {
  const ShareScreen({super.key, required this.item});

  final GithubFileItem item;

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  String? _link;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final link = await context.read<ReveProvider>().linkFor(widget.item);
      if (!mounted) return;
      setState(() {
        _link = link;
        _error = link == null ? 'No link is available for this item' : null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Share')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.item.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(widget.item.path, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(height: 20),
            if (_error != null)
              Text(_error!, style: TextStyle(color: cs.error))
            else if (_link == null)
              const Center(child: CircularProgressIndicator())
            else ...[
              SelectableText(_link!, style: const TextStyle(fontSize: 12.5)),
              const SizedBox(height: 6),
              Text(
                'Anyone with this link can view/download the file. '
                'Signed links expire automatically; GitHub links stay live until revoked.',
                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _link!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Link copied')),
                  );
                },
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Copy link'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => SharePlus.instance.share(
                  ShareParams(uri: Uri.parse(_link!), text: widget.item.name),
                ),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share with another app'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
