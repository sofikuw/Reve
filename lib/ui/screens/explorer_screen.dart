import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../models/file_item.dart';
import '../../providers/reve_provider.dart';
import '../../services/device_abi.dart';
import '../../services/update_installer.dart';
import '../../services/updater.dart';
import '../kit.dart';
import '../theme.dart';
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
        titleSpacing: 14,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Image.asset('assets/icon-192.png', width: 34, height: 34, filterQuality: FilterQuality.medium),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('reve', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.4, fontSize: 18)),
                Text(
                  provider.activeAccount == null
                      ? 'GitHub as cloud storage'
                      : '@${provider.activeAccount!.username}',
                  style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant, letterSpacing: 0.1),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search this folder',
            isSelected: _searching,
            icon: const Icon(Icons.search_rounded),
            selectedIcon: const Icon(Icons.search_off_rounded),
            onPressed: _toggleSearch,
          ),
          IconButton(
            tooltip: _grid ? 'List view' : 'Grid view',
            icon: Icon(_grid ? Icons.view_agenda_rounded : Icons.grid_view_rounded),
            onPressed: () => setState(() => _grid = !_grid),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (value) {
              if (value == 'repo') _createRepository();
              if (value == 'accounts') _openAccounts();
              if (value == 'updates') _openUpdates();
              if (value == 'sort') {
                provider.toggleAutoSort(!provider.autoSortUploads);
                _snack(provider.autoSortUploads ? 'Auto-sort on' : 'Auto-sort off');
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'repo',
                child: ListTile(
                  leading: Icon(Icons.add_box_outlined),
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
                value: 'sort',
                child: ListTile(
                  leading: Icon(
                    provider.autoSortUploads ? Icons.auto_awesome : Icons.auto_awesome_outlined,
                  ),
                  title: Text(provider.autoSortUploads ? 'Auto-sort: on' : 'Auto-sort: off'),
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
          const SizedBox(width: 4),
        ],
      ),
      body: provider.accounts.isEmpty
          ? _Welcome(onConnect: _openAccounts)
          : Column(
              children: [
                if (provider.selectedRepo != null)
                  DriveHeader(
                    title: provider.repoName,
                    branch: provider.selectedBranch ?? '',
                    files: provider.files.length,
                    committedBytes: provider.repoSizeBytes > provider.assetBytes
                        ? provider.repoSizeBytes - provider.assetBytes
                        : 0,
                    assetBytes: provider.assetBytes,
                    onTap: () => _showDriveSheet(provider),
                  ),
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
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.small(
                  heroTag: 'folder',
                  tooltip: 'New folder',
                  onPressed: () => _createFolder(provider),
                  child: const Icon(Icons.create_new_folder_outlined),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.extended(
                  heroTag: 'upload',
                  tooltip: 'Upload files',
                  icon: provider.isUploading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : const Icon(Icons.upload_file_rounded),
                  label: Text(provider.isUploading ? 'Uploading…' : 'Upload'),
                  onPressed: provider.isUploading ? null : () => _upload(provider),
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

  /// Pill breadcrumbs: each segment is a tap target, so jumping two levels up
  /// costs one tap instead of a walk through the tree.
  Widget _breadcrumbs(ReveProvider provider, ColorScheme cs) {
    final path = provider.currentPath;
    final parts = path.isEmpty ? <String>[] : path.split('/');
    final crumbs = <Widget>[
      _Crumb(
        label: provider.repoName.isEmpty ? 'Repository' : provider.repoName,
        current: parts.isEmpty,
        onTap: () {
          _clearSelection();
          provider.navigateToFolder('');
        },
      ),
    ];
    for (var i = 0; i < parts.length; i++) {
      final upTo = parts.take(i + 1).join('/');
      crumbs.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Icon(Icons.chevron_right_rounded, size: 16, color: cs.outline),
      ));
      crumbs.add(_Crumb(
        label: parts[i],
        current: i == parts.length - 1,
        onTap: () {
          _clearSelection();
          provider.navigateToFolder(upTo);
        },
      ));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Row(
        children: [
          if (parts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: IconButton(
                tooltip: 'Up one level',
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  backgroundColor: cs.surfaceContainerHigh,
                  minimumSize: const Size(34, 34),
                  padding: EdgeInsets.zero,
                ),
                icon: const Icon(Icons.arrow_upward_rounded, size: 17),
                onPressed: () {
                  _clearSelection();
                  provider.navigateUp();
                },
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(children: crumbs),
            ),
          ),
          if (provider.selectedRepo != null)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                '${_visibleFiles(provider).length}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (_searching) {
        _searchController.clear();
      } else {
        _query = '';
        _filter = 'all';
        _searchController.clear();
      }
    });
  }

  /// The repo/branch/storage sheet behind [DriveHeader].
  Future<void> _showDriveSheet(ReveProvider provider) async {
    final cs = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.repoName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${formatBytes(provider.repoSizeBytes)} used · '
                        '${formatBytes(provider.assetBytes)} in '
                        '${provider.assetCount} release asset'
                        '${provider.assetCount == 1 ? '' : 's'}',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: provider.repoSizeBytes <= 0
                              ? 0
                              : (provider.assetBytes / provider.repoSizeBytes)
                                  .clamp(0.0, 1.0),
                          minHeight: 5,
                          backgroundColor: cs.surfaceContainerHighest,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Anything over 38 MB is stored as a release asset instead '
                        'of a commit — it still shows here.',
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, height: 1.35),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
                        child: Text(
                          'Repositories',
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6),
                        ),
                      ),
                      for (final repo in provider.repositories)
                        ListTile(
                          leading: Icon(
                            (repo['private'] as bool? ?? false)
                                ? Icons.lock_outline_rounded
                                : Icons.folder_shared_outlined,
                            size: 20,
                            color: repo['id'] == provider.selectedRepo?['id']
                                ? cs.primary
                                : cs.onSurfaceVariant,
                          ),
                          title: Text(
                            (repo['name'] ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: repo['id'] == provider.selectedRepo?['id']
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            (repo['full_name'] ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            provider.selectRepository(repo);
                          },
                        ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
                        child: Text(
                          'Branch',
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6),
                        ),
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final branch in provider.branches)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              child: ChoiceChip(
                                label: Text(branch),
                                selected: branch == provider.selectedBranch,
                                onSelected: (_) {
                                  Navigator.pop(sheetContext);
                                  provider.selectBranch(branch);
                                },
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _searchRow(ReveProvider provider, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(fontSize: 13.5),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search this folder',
                    prefixIcon: const Icon(Icons.search_rounded, size: 19),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.close_rounded, size: 17),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                tooltip: 'Sort',
                icon: const Icon(Icons.sort_rounded, size: 20),
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
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _filters.length,
              separatorBuilder: (context, index) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final (value, label) = _filters[index];
                return ChoiceChip(
                  label: Text(label),
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

  /// The transfer bar: one thin, rounded card that says what is moving and how
  /// far along it is.
  Widget _transferBar(ReveProvider provider, ColorScheme cs) {
    if (!provider.isBusy) return const SizedBox.shrink();
    final label = provider.progressLabel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(ReveTokens.rM),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_upload_rounded, size: 15, color: cs.primary),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    label ?? 'Working…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                if (provider.progress != null)
                  Text(
                    '${((provider.progress ?? 0) * 100).round()}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: provider.progress,
                minHeight: 4,
                backgroundColor: cs.surfaceContainerHighest,
              ),
            ),
          ],
        ),
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

    Future<void> refresh() async {
      await provider.fetchContents();
      provider.checkForUpdates();
    }

    if (_grid) {
      return RefreshIndicator(
        onRefresh: refresh,
        child: GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 130),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 170,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.86,
          ),
          itemCount: files.length,
          itemBuilder: (context, index) {
            final item = files[index];
            return FileCard(
              item: item,
              imageUrl: provider.downloadUrlFor(item),
              selected: _selected.contains(item.path),
              selecting: _selected.isNotEmpty,
              onTap: () => _activate(provider, item),
              onLongPress: () => _onLongPress(item),
              onMore: () => _showItemSheet(provider, item),
            );
          },
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 130),
        itemCount: files.length,
        itemBuilder: (context, index) {
          final item = files[index];
          return FileRow(
            item: item,
            selected: _selected.contains(item.path),
            selecting: _selected.isNotEmpty,
            onTap: () => _activate(provider, item),
            onLongPress: () => _onLongPress(item),
            onMore: () => _showItemSheet(provider, item),
          );
        },
      ),
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
      await _preview(item);
    }
  }

  void _onLongPress(GithubFileItem item) {
    setState(() => _selected.add(item.path));
  }

  /// A link that actually serves the bytes: public assets use the stable
  /// release URL, private ones get a short-lived signed URL.
  Future<String?> _resolveLink(ReveProvider provider, GithubFileItem item) async {
    if (item.isDirectory) return null;
    if (item.isAsset) return provider.streamUrlFor(item);
    return provider.downloadUrlFor(item);
  }

  /// Reads the bytes through the API (so private repositories work) and hands
  /// them to the system save sheet; the bar under the breadcrumbs follows.
  Future<void> _download(ReveProvider provider, GithubFileItem item) async {
    if (provider.selectedRepo == null) {
      _snack('Pick a repository first');
      return;
    }
    try {
      // Release assets can be gigabytes: let the browser's download manager
      // stream them instead of buffering the whole file in the app's memory.
      if (item.isAsset) {
        final url = await _resolveLink(provider, item);
        if (url != null) {
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          _snack('Opening download link for ${item.name}');
          return;
        }
      }
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
    final link = item.isDirectory ? null : provider.downloadUrlFor(item);
    Future<String?> resolveLink() => _resolveLink(provider, item);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: KindTile(kind: fileKind(item.name, directory: item.isDirectory)),
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
              if (link != null) ...[
                ListTile(
                  leading: const Icon(Icons.link_rounded),
                  title: const Text('Copy download link'),
                  subtitle: const Text('Works for the system download manager'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final url = await resolveLink() ?? link;
                    if (url == null) return;
                    await Clipboard.setData(ClipboardData(text: url));
                    _snack('Download link copied');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.open_in_browser_rounded),
                  title: const Text('Open download link'),
                  subtitle: const Text('Best for files too large to hold in memory'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final url = await resolveLink() ?? link;
                    if (url == null) return;
                    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                  },
                ),
              ],
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

  /// file_picker reports sizes lazily, and some Android picks (large videos
  /// from the document picker) report nothing at all. 0 means "unknown" — the
  /// caller then reads at most the small-file ceiling and streams the rest.
  Future<int> _fileLength(PlatformFile file) async {
    try {
      final known = file.lengthSync();
      if (known != null && known > 0) return known;
      final measured = await file.length();
      if (measured != null && measured > 0) return measured;
    } catch (_) {
      // Fall through: an unreadable length just means "unknown".
    }
    return 0;
  }

  /// Uploads a file whose size we already know is over the Contents ceiling.
  /// Streaming is tried first; if that fails, the pick is read once and posted
  /// in one request, which is what saves a picker that cannot stream.
  Future<UploadResult> _uploadLarge(
    ReveProvider provider,
    PlatformFile file,
    int length,
  ) async {
    Stream<List<int>>? stream;
    Uint8List? bytes;
    try {
      stream = file.readAsByteStream();
    } catch (_) {
      // A document-picker URI cannot always be streamed; read it in one go.
      bytes = await file.readAsBytes();
    }
    final first = await provider.uploadLargeFile(
      fileName: file.name,
      length: bytes != null ? bytes.lengthInBytes : length,
      source: stream,
      bytes: bytes,
    );
    if (first.ok) return first;
    try {
      final retryBytes = await file.readAsBytes();
      return await provider.uploadLargeFile(
        fileName: file.name,
        length: retryBytes.lengthInBytes,
        bytes: retryBytes,
      );
    } catch (e) {
      return UploadResult(false, '${first.message} · retry failed: ${_explain(e)}');
    }
  }

  /// A pick whose size the platform could not report is read into memory once;
  /// GitHub needs a Content-Length, so an unknown-size stream cannot be sent.
  Future<Uint8List> _prepare(PlatformFile file) => file.readAsBytes();

  Future<void> _uploadFiles(ReveProvider provider, List<PlatformFile> work) async {
    final failed = <PlatformFile>[];
    final reasons = <String>[];
    final batch = <BatchedFile>[];
    var large = 0;

    for (final file in work) {
      try {
        final length = await _fileLength(file);
        if (length > ReveProvider.maxUploadBytes) {
          final outcome = await _uploadLarge(provider, file, length);
          if (outcome.ok) {
            large++;
          } else {
            failed.add(file);
            reasons.add('${file.name} — ${_explain(outcome.message)}');
          }
          continue;
        }
        // Unknown size: read it once, then route by the real byte count.
        final bytes = await _prepare(file);
        if (bytes.lengthInBytes > ReveProvider.maxUploadBytes) {
          final outcome = await provider.uploadLargeFile(
            fileName: file.name,
            length: bytes.lengthInBytes,
            bytes: bytes,
          );
          if (outcome.ok) {
            large++;
          } else {
            failed.add(file);
            reasons.add('${file.name} — ${_explain(outcome.message)}');
          }
          continue;
        }
        batch.add(BatchedFile(name: file.name, bytes: bytes));
      } catch (e) {
        failed.add(file);
        reasons.add('${file.name} — ${_explain(e)}');
      }
    }

    if (batch.isNotEmpty) {
      final outcome = await provider.commitBatch(batch);
      large += outcome.uploaded.length;
      if (outcome.failed.isNotEmpty) {
        reasons.addAll(outcome.failed.map(
          (name) => '$name — ${outcome.error ?? 'the commit was refused'}',
        ));
      }
    }
    if (large > 0) {
      _snack(large == 1 ? 'Uploaded 1 file' : 'Uploaded $large files');
    }
    if (reasons.isNotEmpty) {
      await _showUploadFailures(
        reasons,
        onRetry: failed.isEmpty ? null : () => _uploadFiles(provider, failed),
      );
    }
  }

  /// Says *why* an upload failed. The old flow only said "not uploaded", which
  /// left a too-large file, an expired token and a dropped socket identical.
  Future<void> _showUploadFailures(
    List<String> reasons, {
    VoidCallback? onRetry,
  }) async {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(Icons.cloud_off_outlined, color: cs.error),
        title: Text(reasons.length == 1
            ? 'One file did not upload'
            : '${reasons.length} files did not upload'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 320),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final reason in reasons)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SelectableText(
                      reason,
                      style: TextStyle(fontSize: 12.5, height: 1.4, color: cs.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          if (onRetry != null)
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                onRetry();
              },
              child: const Text('Retry'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _explain(Object error) {
    final text = error.toString();
    return text.startsWith('Exception: ') ? text.substring(11) : text;
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
    final apkUrl = ValueNotifier<String?>(null);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => ListenableBuilder(
        listenable: provider,
        builder: (context, _) {
          final update = provider.update;
          final cs = Theme.of(context).colorScheme;
          return StatefulBuilder(
            builder: (dialogContext, setState) {
              String? error;
              double? progress;
              var busy = false;

              Future<void> install() async {
                setState(() {
                  busy = true;
                  error = null;
                  progress = 0;
                });
                try {
                  var asset = update?.apkFor(await deviceAbi());
                  if (asset == null && (update?.assets.length ?? 0) > 1) {
                    asset = await showDialog<UpdateAsset>(
                      context: dialogContext,
                      builder: (chooserContext) => AlertDialog(
                        title: const Text('Choose APK'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final option in update!.assets)
                              ListTile(
                                title: Text(option.name),
                                subtitle: Text(option.label),
                                onTap: () => Navigator.pop(chooserContext, option),
                              ),
                          ],
                        ),
                      ),
                    );
                  }
                  if (asset == null) {
                    throw Exception('This release has no APK attached.');
                  }
                  apkUrl.value = asset.url;
                  final path = await downloadApk(
                    asset,
                    onProgress: (fraction) {
                      if (dialogContext.mounted) {
                        setState(() => progress = fraction);
                      }
                    },
                  );
                  await installApk(path);
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                } catch (e) {
                  if (dialogContext.mounted) setState(() => error = e.toString());
                } finally {
                  if (dialogContext.mounted) setState(() => busy = false);
                }
              }

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
                              ],
                            ),
                          ),
                        ],
                        if (busy) ...[
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 4,
                              backgroundColor: cs.surfaceContainerHighest,
                            ),
                          ),
                        ],
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(error!, style: TextStyle(fontSize: 12, color: cs.error)),
                          ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Close'),
                  ),
                  if (error != null && apkUrl.value != null)
                    TextButton(
                      onPressed: () => launchUrl(
                        Uri.parse(apkUrl.value!),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: const Text('Open APK link'),
                    )
                  else if (update != null && !busy)
                    TextButton(
                      onPressed: () => launchUrl(
                        Uri.parse(update.pageUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: const Text('Release page'),
                    ),
                  if (update != null)
                    FilledButton.icon(
                      onPressed: busy ? null : install,
                      icon: busy
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_rounded),
                      label: Text(busy
                          ? 'Downloading${progress == null ? '' : ' ${(progress! * 100).round()}%'}'
                          : 'Download & install'),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
    apkUrl.dispose();
    await opening;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String _kindOf(GithubFileItem item) =>
      fileKind(item.name, directory: item.isDirectory);

  void _snack(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }
}

class _Welcome extends StatelessWidget {
  final VoidCallback onConnect;
  const _Welcome({required this.onConnect});

  static const List<(IconData, String, String)> _steps = [
    (
      Icons.link_rounded,
      'Connect a repo',
      'Sign in with GitHub and pick where your files live.',
    ),
    (
      Icons.upload_file_rounded,
      'Upload anything',
      'Up to 38 MB per commit, or any size as a release asset.',
    ),
    (
      Icons.play_circle_outline_rounded,
      'Preview in place',
      'Photos, video, PDFs and code open right in the app.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: ReveTokens.brandGradient,
                ),
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: ReveTokens.brandA.withValues(alpha: 0.28),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(9),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.asset(
                  'assets/icon-192.png',
                  fit: BoxFit.cover,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Your GitHub repo, as a drive',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(
                'A file manager for the files you already trust GitHub with. '
                'No middle server, no size ceiling, no lock-in.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.2, height: 1.55, color: cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 26),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                children: [
                  for (var i = 0; i < _steps.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(ReveTokens.rM),
                        border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.6),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: cs.secondaryContainer,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Icon(_steps[i].$1, size: 19, color: cs.onSecondaryContainer),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _steps[i].$2,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _steps[i].$3,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    height: 1.35,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 28),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 220),
              child: FilledButton.icon(
                onPressed: onConnect,
                icon: const Icon(Icons.login_rounded, size: 18),
                label: const Text('Connect GitHub account'),
              ),
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
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 80),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    cs.secondaryContainer,
                    cs.tertiaryContainer,
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(icon, size: 32, color: cs.onSecondaryContainer),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.8, height: 1.6, color: cs.onSurfaceVariant),
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 22),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class _Crumb extends StatelessWidget {
  final String label;
  final bool current;
  final VoidCallback onTap;

  const _Crumb({
    required this.label,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: current ? cs.secondaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: current ? FontWeight.w700 : FontWeight.w600,
              color: current ? cs.onSecondaryContainer : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
