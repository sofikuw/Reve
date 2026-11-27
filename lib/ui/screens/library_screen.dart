import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/file_item.dart';
import '../../providers/reve_provider.dart';
import '../kit.dart';

/// Search across every cached folder plus the Starred and Recent lists.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
  final _query = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _tabs.dispose();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReveProvider>();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Search'),
            Tab(text: 'Starred'),
            Tab(text: 'Recent'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: TextField(
                  controller: _query,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Search every cached folder',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _query.clear();
                              setState(() => _search = '');
                            },
                          ),
                  ),
                  onChanged: (value) => setState(() => _search = value),
                ),
              ),
              Expanded(
                child: _list(
                  _search.isEmpty ? const [] : provider.searchFiles(_search),
                  empty: _search.isEmpty ? 'Type to search your files' : 'No matches',
                  cs: cs,
                ),
              ),
            ],
          ),
          _list(
            [
              for (final path in provider.starred)
                if (provider.findCached(path) != null) provider.findCached(path)!,
            ],
            empty: 'Star a file from its action menu to find it here',
            cs: cs,
          ),
          _list(
            [
              for (final path in provider.recent)
                if (provider.findCached(path) != null) provider.findCached(path)!,
            ],
            empty: 'Files you open will show up here',
            cs: cs,
          ),
        ],
      ),
    );
  }

  Widget _list(List<GithubFileItem> items, {required String empty, required ColorScheme cs}) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(empty, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 30),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          child: ListTile(
            leading: KindTile(
              kind: fileKind(item.name, directory: item.isDirectory),
              size: 38,
            ),
            title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(item.path, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              icon: Icon(
                context.read<ReveProvider>().isStarred(item.path)
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
              ),
              onPressed: () => context.read<ReveProvider>().toggleStar(item.path),
            ),
            onTap: () {
              final parent = item.path.contains('/')
                  ? item.path.substring(0, item.path.lastIndexOf('/'))
                  : '';
              Navigator.pop(context);
              context.read<ReveProvider>().navigateToFolder(parent);
              context.read<ReveProvider>().recordOpen(item.path);
            },
          ),
        );
      },
    );
  }
}
