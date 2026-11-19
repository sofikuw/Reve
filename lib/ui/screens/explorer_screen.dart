import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../models/file_item.dart';
import '../../providers/reve_provider.dart';
import '../../services/updater.dart';
import 'accounts_screen.dart';
import 'preview_screen.dart';

class ExplorerScreen extends StatefulWidget {
  const ExplorerScreen({super.key});

  @override
  State<ExplorerScreen> createState() => _ExplorerScreenState();
}

class _ExplorerScreenState extends State<ExplorerScreen> {
  bool _grid = false;
  bool _announcedUpdate = false;

  /// Browsing aids: the folder listing is filtered and sorted in memory, so a
  /// big folder does not cost a request per keystroke.
  bool _searching = false;
  String _query = '';
  String _filter = 'all';
  String _sort = 'name';
  final TextEditingController _searchController = TextEditingController();

  /// Paths picked with a long press. Empty means the normal browsing mode.
  final Set<String> _selected = {};

  ReveProvider get _provider => context.read<ReveProvider>();

  @override
  void initState() {
    super.initState();
    // The provider checks on start-up; this only surfaces the result once.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _provider.addListener(_announceUpdate);
      _announceUpdate();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _provider.removeListener(_announceUpdate);
    super.dispose();
  }

  void _announceUpdate() {
    if (!mounted || _announcedUpdate) return;
    final update = _provider.update;
    if (update == null) return;
    _announcedUpdate = true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('reve ${update.label} is available'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(label: 'Get it', onPressed: _openUpdates),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReveProvider>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: _selected.isNotEmpty
          ? _selectionBar(provider, cs)
          : AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset('assets/icon-192.png', width: 32, height: 32, filterQuality: FilterQuality.medium),
            ),
            const SizedBox(width: 10),
            const Text('reve', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.3)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: provider.autoSortUploads
                ? 'Auto-sort uploads: on'
                : 'Auto-sort uploads: off',
            isSelected: provider.autoSortUploads,
            icon: const Icon(Icons.auto_awesome_outlined),
            selectedIcon: const Icon(Icons.auto_awesome),
            onPressed: () => provider.toggleAutoSort(!provider.autoSortUploads),
          ),
          IconButton(
            tooltip: _grid ? 'List view' : 'Grid view',
            icon: Icon(_grid ? Icons.view_list_outlined : Icons.grid_view_outlined),
            onPressed: () => setState(() => _grid = !_grid),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) {
              if (value == 'repo') _createRepository();
              if (value == 'accounts') _openAccounts();
              if (value == 'updates') _openUpdates();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'repo',
                child: ListTile(
                  leading: Icon(Icons.create_new_folder_outlined),
                  title: Text('New repository'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'accounts',
                child: ListTile(
                  leading: Icon(Icons.manage_accounts_outlined),
                  title: Text('Accounts'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'updates',
                child: ListTile(
                  leading: Icon(
                    provider.update == null ? Icons.system_update_alt : Icons.new_releases,
                    color: provider.update == null ? null : cs.primary,
                  ),
                  title: Text(provider.update == null
                      ? 'Check for updates'
                      : 'Update ${provider.update!.label}'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
        bottom: provider.accounts.isEmpty || provider.repositories.isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(62),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: _LabeledDropdown<int>(
                          label: 'Repository',
                          value: provider.selectedRepo?['id'] as int?,
                          items: provider.repositories
                              .map((repo) => MapEntry<int, String>(
                                    repo['id'] as int,
                                    (repo['full_name'] ?? '').toString(),
                                  ))
                              .toList(),
                          onChanged: (id) {
                            for (final repo in provider.repositories) {
                              if (repo['id'] == id) {
                                provider.selectRepository(repo);
                                return;
                              }
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 132,
                        child: _LabeledDropdown<String>(
                          label: 'Branch',
                          value: provider.selectedBranch,
                          items: provider.branches
                              .map((b) => MapEntry<String, String>(b, b))
                              .toList(),
                          onChanged: (b) {
                            if (b != null) provider.selectBranch(b);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
      body: provider.accounts.isEmpty
          ? _Welcome(onConnect: _openAccounts)
          : Column(
              children: [
                _breadcrumbs(provider, cs),
                if (_searching) _searchRow(provider, cs),
                _transferBar(provider, cs),
                Expanded(child: _fileArea(provider, cs)),
              ],
            ),
      floatingActionButton: provider.accounts.isEmpty || _selected.isNotEmpty
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'folder',
                  tooltip: 'New folder',
                  onPressed: () => _createFolder(provider),
                  child: const Icon(Icons.create_new_folder_outlined),
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  heroTag: 'upload',
                  tooltip: 'Upload files',
                  onPressed: provider.isUploading ? null : () => _upload(provider),
                  child: provider.isUploading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : const Icon(Icons.upload_file),
                ),
              ],
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // Chrome
  // ---------------------------------------------------------------------------

  /// Replaces the app bar while files are selected, the way a gallery does.
  PreferredSizeWidget _selectionBar(ReveProvider provider, ColorScheme cs) {
    final picked =
        provider.files.where((f) => _selected.contains(f.path)).toList();
    final hasFiles = picked.any((f) => !f.isDirectory);
    return AppBar(
      leading: IconButton(
        tooltip: 'Cancel selection',
        icon: const Icon(Icons.close),
        onPressed: _clearSelection,
      ),
      title: Text('${_selected.length} selected'),
      actions: [
        IconButton(
          tooltip: 'Select all',
          icon: const Icon(Icons.select_all),
          onPressed: () => setState(() {
            _selected
              ..clear()
              ..addAll(_visibleFiles(provider).map((f) => f.path));
          }),
        ),
        IconButton(
          tooltip: 'Download selected',
          icon: const Icon(Icons.download_outlined),
          onPressed: hasFiles ? () => _downloadSelected(provider, picked) : null,
        ),
        IconButton(
          tooltip: 'Delete selected',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _deleteSelected(provider, picked),
        ),
      ],
    );
  }

  static const List<(String, String)> _filters = [
    ('all', 'All'),
    ('image', 'Photos'),
    ('video', 'Video'),
    ('audio', 'Audio'),
    ('doc', 'Docs'),
    ('archive', 'Archives'),
    ('code', 'Code'),
    ('folder', 'Folders'),
  ];

  Widget _searchRow(ReveProvider provider, ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search this folder',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.backspace_outlined, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                tooltip: 'Sort',
                icon: const Icon(Icons.sort),
                onSelected: (value) => setState(() => _sort = value),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'name', child: Text('Name')),
                  PopupMenuItem(value: 'size', child: Text('Size, largest first')),
                  PopupMenuItem(value: 'type', child: Text('Type')),
                ],
              ),
            ],
          ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _filters.length,
              separatorBuilder: (context, index) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final (value, label) = _filters[index];
                return ChoiceChip(
                  label: Text(label, style: const TextStyle(fontSize: 12)),
                  selected: _filter == value,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _filter = value),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// The listing after the search box, the type chips and the sort order.
  List<GithubFileItem> _visibleFiles(ReveProvider provider) {
    final query = _query.trim().toLowerCase();
    final list = provider.files.where((item) {
      if (_filter == 'folder') {
        if (!item.isDirectory) return false;
      } else if (_filter != 'all') {
        if (item.isDirectory || _kindOf(item) != _filter) return false;
      }
      if (query.isEmpty) return true;
      return item.name.toLowerCase().contains(query) ||
          item.path.toLowerCase().contains(query);
    }).toList();

    if (_sort == 'size') {
      list.sort((a, b) => b.size.compareTo(a.size));
    } else if (_sort == 'type') {
      list.sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        final byKind = _kindOf(a).compareTo(_kindOf(b));
        if (byKind != 0) return byKind;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    }
    return list;
  }

  void _clearSelection() {
    if (_selected.isEmpty) return;
    setState(_selected.clear);
  }

  void _toggleSelection(GithubFileItem item) {
    setState(() {
      if (!_selected.remove(item.path)) _selected.add(item.path);
    });
  }

  Future<void> _downloadSelected(
    ReveProvider provider,
    List<GithubFileItem> picked,
  ) async {
    final files = picked.where((f) => !f.isDirectory).toList();
    if (files.isEmpty) {
      _snack('Nothing to download');
      return;
    }
    var saved = 0;
    for (final item in files) {
      if (!mounted) return;
      try {
        final bytes = await provider.readBytes(item, label: 'Downloading ${item.name}');
        if (!mounted) return;
        final path = await FilePicker.saveFile(
          dialogTitle: 'Save ${item.name}',
          fileName: item.name,
          bytes: bytes,
        );
        if (path != null) saved++;
      } catch (e) {
        _snack('Could not download ${item.name}: $e');
        break;
      }
    }
    _clearSelection();
    _snack(saved == 1 ? 'Saved 1 file' : 'Saved $saved files');
  }

  Future<void> _deleteSelected(
    ReveProvider provider,
    List<GithubFileItem> picked,
  ) async {
    if (picked.isEmpty) return;
    final folders = picked.where((f) => f.isDirectory).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${picked.length} item${picked.length == 1 ? '' : 's'}?'),
        content: Text(
          folders > 0
              ? 'Folders are deleted with everything inside them. This is one commit, '
                  'and each deleted file can be restored from GitHub history.'
              : 'This is one commit. The files stay in GitHub history, so the delete is reversible.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;

    var deleted = 0;
    for (final item in picked) {
      final ok = await provider.deleteItem(item);
      if (ok) deleted++;
    }
    _clearSelection();
    _snack(deleted == picked.length
        ? 'Deleted ${picked.length} item${picked.length == 1 ? '' : 's'}'
        : 'Deleted $deleted of ${picked.length}');
  }

  Widget _breadcrumbs(ReveProvider provider, ColorScheme cs) {
    final path = provider.currentPath;
    return Container(
      color: cs.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Repository root',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.home_outlined, size: 20),
            onPressed: () {
              _clearSelection();
              provider.navigateToFolder('');
            },
          ),
          if (path.isNotEmpty)
            IconButton(
              tooltip: 'Up one level',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_upward, size: 20),
              onPressed: () {
                _clearSelection();
                provider.navigateUp();
              },
            ),
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search this folder',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.search, size: 20),
            onPressed: () {
              setState(() => _searching = !_searching);
              if (_searching) _searchController.clear();
              else {
                _query = '';
                _filter = 'all';
                _searchController.clear();
                _clearSelection();
              }
            },
          ),
          const SizedBox(width: 2),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                path.isEmpty ? '/ (root)' : '/$path',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          if (provider.files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                '${_visibleFiles(provider).length}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
          if (provider.selectedRepo != null)
            Tooltip(
              message: provider.assetBytes > 0
                  ? '${formatBytes(provider.repoSizeBytes)} used · '
                      '${formatBytes(provider.assetBytes)} in ${provider.assetCount} release assets'
                  : '${formatBytes(provider.repoSizeBytes)} used',
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  formatBytes(provider.repoSizeBytes),
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Refresh',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () {
              provider.fetchContents();
              provider.checkForUpdates();
            },
          ),
        ],
      ),
    );
  }

  /// The same thin bar the web client puts under the breadcrumbs: uploads,
  /// downloads and preview loads all report through it.
  Widget _transferBar(ReveProvider provider, ColorScheme cs) {
    if (!provider.isBusy) return const SizedBox.shrink();
    final label = provider.progressLabel;
    return Container(
      color: cs.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: provider.progress,
              minHeight: 3,
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }

  Widget _fileArea(ReveProvider provider, ColorScheme cs) {
    if (provider.isLoading && provider.files.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.selectedRepo == null) {
      return _Prompt(
        icon: Icons.folder_outlined,
        title: 'Pick a repository',
        body: 'Choose a storage repository from the dropdown above, or create a new one.',
        action: FilledButton.tonalIcon(
          onPressed: _createRepository,
          icon: const Icon(Icons.add),
          label: const Text('Create repository'),
        ),
      );
    }
    if (provider.offlineItems.isNotEmpty && provider.files.isEmpty) {
      return _Prompt(
        icon: Icons.cloud_off_outlined,
        title: 'Offline view',
        body: 'No connection right now. This is the last saved list of '
            '${provider.currentPath.isEmpty ? 'the root folder' : '/${provider.currentPath}'}'
            '${provider.offlineSince.isEmpty ? '' : ' · ${provider.offlineSince}'}.',
        action: FilledButton(
          onPressed: () => provider.fetchContents(),
          child: const Text('Try again'),
        ),
      );
    }
    if (provider.files.isEmpty) {
      return _Prompt(
        icon: Icons.folder_open_outlined,
        title: 'This folder is empty',
        body: 'Upload files or create a folder. With auto-sort on, uploads are filed '
            'into images/, documents/, media/ and friends.',
        action: FilledButton.icon(
          onPressed: () => _upload(provider),
          icon: const Icon(Icons.upload_file),
          label: const Text('Upload files'),
        ),
      );
    }

    final files = _visibleFiles(provider);
    if (files.isEmpty &&
        (provider.files.isNotEmpty ||
            _query.isNotEmpty ||
            _filter != 'all')) {
      return _Prompt(
        icon: Icons.search_off,
        title: 'No matches',
        body: 'Nothing in this folder matches the search or filter.',
        action: FilledButton(
          onPressed: () => setState(() {
            _query = '';
            _filter = 'all';
            _searchController.clear();
            _searching = false;
          }),
          child: const Text('Clear and show all'),
        ),
      );
    }

    if (_grid) {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 168,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.92,
        ),
        itemCount: files.length,
        itemBuilder: (context, index) {
          final item = files[index];
          return _GridCard(
            item: item,
            url: provider.downloadUrlFor(item),
            selected: _selected.contains(item.path),
            onTap: () => _activate(provider, item),
            onLongPress: () => _onLongPress(item),
          );
        },
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final item = files[index];
        return ListTile(
          leading: _leading(item),
          title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            item.isDirectory
                ? 'Folder'
                : '${formatBytes(item.size)}${item.isAsset ? ' · release asset' : ''}',
            style: const TextStyle(fontSize: 11.5),
          ),
          onTap: () => _activate(provider, item),
          onLongPress: () => _onLongPress(item),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_selected.contains(item.path))
                Icon(Icons.check_circle, size: 20, color: Theme.of(context).colorScheme.primary)
              else if (!item.isDirectory)
                IconButton(
                  tooltip: 'Download',
                  icon: const Icon(Icons.download_outlined, size: 20),
                  onPressed: () => _download(provider, item),
                ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (value) => _onAction(provider, item, value),
                itemBuilder: (context) => [
                  if (!item.isDirectory) ...[
                    const PopupMenuItem(value: 'preview', child: Text('Preview')),
                    const PopupMenuItem(value: 'download', child: Text('Download')),
                    const PopupMenuItem(value: 'open', child: Text('Open on GitHub')),
                  ],
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _leading(GithubFileItem item) {
    if (_selected.contains(item.path)) {
      return Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.check_circle, size: 21),
      );
    }
    final kind = _kindOf(item);
    final (icon, color) = switch (kind) {
      'dir' => (Icons.folder, const Color(0xFFF2B429)),
      'image' => (Icons.image_outlined, const Color(0xFF4F9CF9)),
      'video' => (Icons.movie_outlined, const Color(0xFFFF6B9D)),
      'audio' => (Icons.audiotrack_outlined, const Color(0xFF8B5CF6)),
      'doc' => (Icons.description_outlined, const Color(0xFF38BDF8)),
      'archive' => (Icons.folder_zip_outlined, const Color(0xFFF59E0B)),
      'code' => (Icons.code, const Color(0xFF34D399)),
      _ => (Icons.insert_drive_file_outlined, Colors.blueGrey),
    };
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 21),
    );
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _activate(ReveProvider provider, GithubFileItem item) async {
    if (_selected.isNotEmpty) {
      _toggleSelection(item);
      return;
    }
    if (item.isDirectory) {
      await provider.navigateToFolder(item.path);
    } else {
      await _showItemSheet(provider, item);
    }
  }

  void _onLongPress(GithubFileItem item) {
    setState(() => _selected.add(item.path));
  }

  Future<void> _onAction(ReveProvider provider, GithubFileItem item, String value) async {
    if (value == 'preview') return _preview(item);
    if (value == 'download') return _download(provider, item);
    if (value == 'open') return _openOnGithub(provider, item);
    if (value == 'delete') return _delete(provider, item);
  }

  /// Reads the bytes through the API (so private repositories work) and hands
  /// them to the system save sheet; the bar under the breadcrumbs follows.
  Future<void> _download(ReveProvider provider, GithubFileItem item) async {
    if (provider.selectedRepo == null) {
      _snack('Pick a repository first');
      return;
    }
    try {
      final bytes = await provider.readBytes(item, label: 'Downloading ${item.name}');
      if (!mounted) return;
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save ${item.name}',
        fileName: item.name,
        bytes: bytes,
      );
      _snack(saved == null ? 'Download cancelled' : 'Saved ${item.name}');
    } catch (e) {
      _snack('Could not download ${item.name}: $e');
    }
  }

  Future<void> _openOnGithub(ReveProvider provider, GithubFileItem item) async {
    final url = item.htmlUrl ?? provider.downloadUrlFor(item);
    if (url == null) {
      _snack('No URL for ${item.name}');
      return;
    }
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _showItemSheet(ReveProvider provider, GithubFileItem item) async {
    final cs = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: _leading(item),
                title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${item.path} · ${item.isDirectory ? 'folder' : formatBytes(item.size)}'),
              ),
              const Divider(height: 1),
              if (!item.isDirectory)
                ListTile(
                  leading: const Icon(Icons.visibility_outlined),
                  title: const Text('Preview'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _preview(item);
                  },
                ),
              if (!item.isDirectory)
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('Download'),
                  subtitle: const Text('Saves to your device, private repositories included'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _download(provider, item);
                  },
                ),
              if (!item.isDirectory)
                ListTile(
                  leading: const Icon(Icons.open_in_new),
                  title: const Text('Open on GitHub'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openOnGithub(provider, item);
                  },
                ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: cs.error),
                title: Text('Delete', style: TextStyle(color: cs.error)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _delete(provider, item);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _preview(GithubFileItem item) async {
    final provider = _provider;
    final siblings = provider.files.where((f) => !f.isDirectory).toList();
    final index = siblings.indexWhere((f) => f.path == item.path);
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PreviewScreen(
          provider: provider,
          items: siblings.isEmpty ? [item] : siblings,
          initialIndex: index < 0 ? 0 : index,
        ),
      ),
    );
  }

  Future<void> _delete(ReveProvider provider, GithubFileItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${item.name}?'),
        content: Text(
          item.isDirectory
              ? 'Everything inside the folder is deleted in a single commit. You can revert it on GitHub.'
              : 'This creates a commit on GitHub, so the file can be restored from history.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await provider.deleteItem(item);
    _snack('${item.name} deleted');
    if (ok && provider.lastDeleted != null) {
      _offerUndo(provider);
    } else if (!ok) {
      _snack(provider.errorMessage ?? 'Delete failed');
    }
  }

  /// A short-lived "Undo" toast for a restorable delete.
  void _offerUndo(ReveProvider provider) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 12),
        content: const Text('Deleted — Undo restores it from Git history'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            final restored = await provider.undoDelete();
            if (mounted) _snack(restored ? 'Restored' : 'Could not restore');
          },
        ),
      ),
    );
  }

  Future<void> _upload(ReveProvider provider) async {
    if (provider.selectedRepo == null) {
      _snack('Pick a repository first');
      return;
    }
    var work = (await FilePicker.pickFiles()).whereType<PlatformFile>().toList();
    if (work.isEmpty) return;
    await _confirmReplacements(provider, work);
    if (work.isEmpty) return;
    await _uploadFiles(provider, work);
  }

  /// The picker answer can flip [work] to a shorter list; empty means "nothing
  /// to upload".
  Future<void> _confirmReplacements(ReveProvider provider, List<PlatformFile> work) async {
    // If something already sits at the destination, ask once before uploading.
    final existing = await provider.existingPaths();
    var conflicts = work
        .map((f) => provider.targetPathFor(f.name))
        .where(existing.contains)
        .length;
    if (conflicts == 0) return;
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Replace ${conflicts} existing file${conflicts == 1 ? '' : 's'}?'),
        content: Text(
          '${provider.repoName} already has $conflicts file(s) at these paths. '
          '"Skip" uploads only the new names.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Skip existing')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Replace')),
        ],
      ),
    );
    if (answer != true) {
      work.removeWhere((f) => existing.contains(provider.targetPathFor(f.name)));
      if (work.isEmpty) _snack('Nothing uploaded');
    }
  }

  /// file_picker reports sizes lazily; some Android picks (videos) report
  /// nothing, so we prefer the cached value and only then the stream fallback.
  Future<int> _fileLength(PlatformFile file) async {
    final known = file.lengthSync();
    if (known != null) return known;
    final fromFile = await file.length();
    return fromFile ?? 0;
  }

  /// Streams a big file straight from disk into a release asset; buffers when
  /// the pick cannot stream (the phone's picker returns a plain file path).
  Future<UploadResult> _uploadLarge(
    ReveProvider provider,
    PlatformFile file, {
    required int length,
  }) async {
    Stream<List<int>>? stream;
    Uint8List? bytes;
    try {
      stream = file.readAsByteStream();
    } catch (_) {
      bytes = await file.readAsBytes();
    }
    return provider.uploadLargeFile(
      fileName: file.name,
      length: length,
      source: stream,
      bytes: bytes,
    );
  }

  Future<void> _uploadFiles(ReveProvider provider, List<PlatformFile> work) async {
    final failed = <PlatformFile>[];
    final batch = <BatchedFile>[];
    var large = 0;
    for (final file in work) {
      final length = await _fileLength(file);
      if (length > ReveProvider.maxUploadBytes) {
        // Big, and the picker told us the size: stream from disk.
        final outcome = await _uploadLarge(provider, file, length: length);
        if (!outcome.ok) failed.add(file);
        large++;
        continue;
      }
      // Read it now. Some Android picks (videos) report no size at all, so
      // the small/large decision has to be made on the real byte count.
      final Uint8List bytes;
      try {
        bytes = await file.readAsBytes();
      } catch (e) {
        failed.add(file);
        continue;
      }
      if (bytes.lengthInBytes > ReveProvider.maxUploadBytes) {
        final outcome = await provider.uploadLargeFile(
          fileName: file.name,
          length: bytes.lengthInBytes,
          bytes: bytes,
        );
        if (!outcome.ok) failed.add(file);
        large++;
        continue;
      }
      batch.add(BatchedFile(name: file.name, bytes: bytes));
    }
    if (batch.isNotEmpty) {
      final outcome = await provider.commitBatch(batch);
      if (outcome.failed.isNotEmpty) {
        _snack('${outcome.failed.join(', ')}: ${outcome.error ?? 'Upload failed'}');
      }
      large += outcome.uploaded.length;
    }
    if (large > 0) {
      _snack(large == 1 ? 'Uploaded 1 file' : 'Uploaded $large files');
    }
    if (failed.isNotEmpty) {
      _snack(
        '${failed.length} file${failed.length == 1 ? '' : 's'} not uploaded',
        action: SnackBarAction(label: 'Retry', onPressed: () => _uploadFiles(provider, failed)),
      );
    }
  }

  Future<void> _createFolder(ReveProvider provider) async {
    if (provider.selectedRepo == null) {
      _snack('Pick a repository first');
      return;
    }
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Folder name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final ok = await provider.createFolder(name);
    _snack(ok ? 'Folder “$name” created' : (provider.errorMessage ?? 'Could not create folder'));
  }

  Future<void> _createRepository() async {
    final provider = _provider;
    if (!provider.isConnected) {
      _snack('Connect an account first');
      return;
    }
    final nameController = TextEditingController();
    final descriptionController = TextEditingController(text: 'Storage bucket managed by reve');
    var isPrivate = true;

    await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New repository'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 4),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isPrivate,
                  onChanged: (v) => setDialogState(() => isPrivate = v ?? true),
                  title: const Text('Private repository'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(context, true);
                final ok = await provider.createRepository(
                  name,
                  description: descriptionController.text.trim(),
                  isPrivate: isPrivate,
                );
                _snack(ok ? 'Repository $name created' : (provider.errorMessage ?? 'Failed'));
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _openAccounts() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountsScreen()));
  }

  /// One place for "what am I running", the beta switch and the download.
  Future<void> _openUpdates() async {
    final provider = context.read<ReveProvider>();
    final opening = provider.checkForUpdates(manual: true);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => ListenableBuilder(
        listenable: provider,
        builder: (context, _) {
          final update = provider.update;
          final cs = Theme.of(context).colorScheme;
          return AlertDialog(
            title: const Text('Updates'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppConfig.build > 0
                          ? 'Installed: reve ${AppConfig.version} · build ${AppConfig.build}'
                          : 'Installed: reve ${AppConfig.version}',
                      style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Beta and alpha builds'),
                      subtitle: const Text('Off: stable releases only'),
                      value: provider.offersPrereleases,
                      onChanged: (value) => provider.setUpdateChannel(
                        value ? UpdateChannel.beta : UpdateChannel.stable,
                      ),
                    ),
                    if (provider.checkingUpdate)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: LinearProgressIndicator(minHeight: 3),
                      ),
                    if (provider.updateError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Could not check: ${provider.updateError}',
                          style: TextStyle(fontSize: 12, color: cs.error),
                        ),
                      ),
                    if (!provider.checkingUpdate && update == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          provider.updateError == null
                              ? 'Up to date.'
                              : 'Try again when you are online.',
                          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                        ),
                      ),
                    if (update != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('reve ${update.label}',
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            Text(
                              update.notes.trim().isEmpty
                                  ? 'New build published.'
                                  : update.notes.trim(),
                              maxLines: 6,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, height: 1.5, color: cs.onSurfaceVariant),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Pick the APK for your phone\'s CPU on the release page; '
                              'it installs over this build without losing accounts.',
                              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
              if (update != null)
                FilledButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(update.pageUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Download'),
                ),
            ],
          );
        },
      ),
    );
    await opening;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String _kindOf(GithubFileItem item) {
    if (item.isDirectory) return 'dir';
    final dot = item.name.lastIndexOf('.');
    final ext = dot > 0 ? item.name.substring(dot + 1).toLowerCase() : '';
    if (const {
      'png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'bmp', 'ico', 'avif',
      'heic', 'heif', 'tif', 'tiff',
    }.contains(ext)) {
      return 'image';
    }
    if (const {
      'mp4', 'webm', 'mkv', 'avi', 'mov', 'ogv', 'm4v', '3gp', 'ts', 'm2ts', 'mpd', 'wmv', 'flv',
    }.contains(ext)) {
      return 'video';
    }
    if (const {
      'mp3', 'wav', 'ogg', 'oga', 'flac', 'm4a', 'm4b', 'aac', 'opus', 'amr', 'wma', 'mid',
    }.contains(ext)) {
      return 'audio';
    }
    if (const {'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz'}.contains(ext)) return 'archive';
    if (const {'pdf', 'doc', 'docx', 'txt', 'md', 'markdown', 'xls', 'xlsx', 'csv', 'json', 'xml', 'yaml', 'yml', 'log'}.contains(ext)) {
      return 'doc';
    }
    if (const {'js', 'mjs', 'ts', 'tsx', 'jsx', 'dart', 'py', 'rb', 'go', 'rs', 'java', 'kt', 'c', 'h', 'cpp', 'hpp', 'cs', 'php', 'sh', 'html', 'css', 'scss', 'sql', 'toml', 'ini', 'conf'}.contains(ext)) {
      return 'code';
    }
    return 'file';
  }

  void _snack(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }
}

class _GridCard extends StatelessWidget {
  final GithubFileItem item;
  final String? url;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _GridCard({
    required this.item,
    this.url,
    this.selected = false,
    required this.onTap,
    required this.onLongPress,
  });

  /// Images get a real thumbnail; everything else keeps a glyph so a folder
  /// full of videos does not pull hundreds of megabytes.
  Widget _thumb(BuildContext context, ColorScheme cs, bool isDir) {
    final isImage = !isDir && _isImage(item.name);
    if (!isImage || url == null) {
      return Icon(
        isDir ? Icons.folder : Icons.insert_drive_file_outlined,
        size: 38,
        color: isDir ? const Color(0xFFF2B429) : cs.primary,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 64,
        height: 64,
        child: Image.network(
          url!,
          fit: BoxFit.cover,
          cacheWidth: 256,
          filterQuality: FilterQuality.low,
          errorBuilder: (context, error, stack) => Icon(Icons.image_outlined, size: 38, color: cs.primary),
        ),
      ),
    );
  }

  static bool _isImage(String name) {
    final dot = name.lastIndexOf('.');
    final ext = dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
    return const {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'avif'}.contains(ext);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDir = item.isDirectory;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Stack(
            alignment: Alignment.topRight,
            children: [
              _thumb(context, cs, isDir),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 10),
                  Text(
                    item.name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, height: 1.3),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isDir ? 'folder' : formatBytes(item.size),
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              if (selected)
                Icon(Icons.check_circle, size: 18, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  final VoidCallback onConnect;
  const _Welcome({required this.onConnect});

  static const List<(IconData, String)> _steps = [
    (Icons.link, 'Pick a repository from the dropdown'),
    (Icons.upload_file, 'Upload files — up to 38 MB, or any size as release assets'),
    (Icons.preview, 'Browse and preview photos, video, PDF and documents'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/icon-512.png', width: 96, height: 96),
            const SizedBox(height: 20),
            const Text(
              'Turn GitHub into your drive',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, letterSpacing: -0.3),
            ),
            const SizedBox(height: 8),
            Text(
              'Connect one or more GitHub accounts with a personal access token or OAuth, '
              'pick a repository, and start uploading. Nothing passes through a third-party server.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.6, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            Container(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                children: [
                  for (var i = 0; i < _steps.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(_steps[i].$1, size: 18, color: cs.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _steps[i].$2,
                            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: onConnect,
              icon: const Icon(Icons.login),
              label: const Text('Connect GitHub account'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Prompt extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  const _Prompt({required this.icon, required this.title, required this.body, this.action});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Icon(icon, size: 36, color: cs.primary),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.6, color: cs.onSurfaceVariant),
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class _LabeledDropdown<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<MapEntry<T, String>> items;
  final ValueChanged<T?> onChanged;

  const _LabeledDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final known = items.any((entry) => entry.key == value);
    return InputDecorator(
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        labelText: label,
        contentPadding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          isDense: true,
          value: known ? value : null,
          hint: Text(label, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          icon: Icon(Icons.arrow_drop_down, size: 20, color: cs.onSurfaceVariant),
          style: TextStyle(fontSize: 13, color: cs.onSurface),
          items: items
              .map((entry) => DropdownMenuItem<T>(
                    value: entry.key,
                    child: Text(entry.value, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
