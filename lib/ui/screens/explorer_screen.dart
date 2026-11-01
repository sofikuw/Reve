import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/file_item.dart';
import '../../providers/reve_provider.dart';
import 'accounts_screen.dart';

class ExplorerScreen extends StatefulWidget {
  const ExplorerScreen({super.key});

  @override
  State<ExplorerScreen> createState() => _ExplorerScreenState();
}

class _ExplorerScreenState extends State<ExplorerScreen> {
  bool _grid = false;

  ReveProvider get _provider => context.read<ReveProvider>();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReveProvider>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(Icons.cloud_outlined, size: 20, color: cs.onPrimaryContainer),
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
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'repo',
                child: ListTile(
                  leading: Icon(Icons.create_new_folder_outlined),
                  title: Text('New repository'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'accounts',
                child: ListTile(
                  leading: Icon(Icons.manage_accounts_outlined),
                  title: Text('Accounts'),
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
                Expanded(child: _fileArea(provider, cs)),
              ],
            ),
      floatingActionButton: provider.accounts.isEmpty
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
            onPressed: () => provider.navigateToFolder(''),
          ),
          if (path.isNotEmpty)
            IconButton(
              tooltip: 'Up one level',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_upward, size: 20),
              onPressed: provider.navigateUp,
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
                '${provider.files.length}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
          IconButton(
            tooltip: 'Refresh',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: provider.fetchContents,
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
        icon: Icons.folder_git_outlined,
        title: 'Pick a repository',
        body: 'Choose a storage repository from the dropdown above, or create a new one.',
        action: FilledButton.tonalIcon(
          onPressed: _createRepository,
          icon: const Icon(Icons.add),
          label: const Text('Create repository'),
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

    if (_grid) {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 168,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.92,
        ),
        itemCount: provider.files.length,
        itemBuilder: (context, index) => _GridCard(
          item: provider.files[index],
          onTap: () => _activate(provider, provider.files[index]),
          onLongPress: () => _showItemSheet(provider, provider.files[index]),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: provider.files.length,
      itemBuilder: (context, index) {
        final item = provider.files[index];
        return ListTile(
          leading: _leading(item),
          title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            item.isDirectory ? 'Folder' : _formatSize(item.size),
            style: const TextStyle(fontSize: 11.5),
          ),
          onTap: () => _activate(provider, item),
          onLongPress: () => _showItemSheet(provider, item),
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (value) => _onAction(provider, item, value),
            itemBuilder: (context) => [
              if (!item.isDirectory) ...[
                const PopupMenuItem(value: 'preview', child: Text('Preview')),
                const PopupMenuItem(value: 'download', child: Text('Open download URL')),
              ],
              PopupMenuItem(
                value: 'delete',
                child: Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _leading(GithubFileItem item) {
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
    if (item.isDirectory) {
      await provider.navigateToFolder(item.path);
    } else {
      await _showItemSheet(provider, item);
    }
  }

  Future<void> _onAction(ReveProvider provider, GithubFileItem item, String value) async {
    if (value == 'preview') return _preview(item);
    if (value == 'download') {
      final url = provider.downloadUrlFor(item);
      if (url != null) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
      return;
    }
    if (value == 'delete') return _delete(provider, item);
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
                subtitle: Text('${item.path} · ${item.isDirectory ? 'folder' : _formatSize(item.size)}'),
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
                  leading: const Icon(Icons.open_in_new),
                  title: const Text('Open raw download URL'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    final url = provider.downloadUrlFor(item);
                    if (url != null) {
                      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                    }
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
    final kind = _kindOf(item);
    final url = provider.downloadUrlFor(item);

    if (kind == 'image' && url != null) {
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: InteractiveViewer(
            maxScale: 5,
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stack) => const Padding(
                padding: EdgeInsets.all(28),
                child: Text('Could not load this image.'),
              ),
            ),
          ),
        ),
      );
      return;
    }

    if (kind == 'doc' || kind == 'code' || kind == 'file') {
      try {
        final text = await provider.readText(item);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => Dialog(
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760, maxHeight: 620),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        child: SelectableText(
                          text.length > 200000 ? text.substring(0, 200000) : text,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.55),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } catch (e) {
        _snack(e.toString());
      }
      return;
    }

    if (url != null) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
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
    _snack(ok ? '${item.name} deleted' : (provider.errorMessage ?? 'Delete failed'));
  }

  Future<void> _upload(ReveProvider provider) async {
    if (provider.selectedRepo == null) {
      _snack('Pick a repository first');
      return;
    }
    final result = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
    if (result == null) return;

    var ok = 0;
    final failures = <String>[];
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) {
        failures.add('${file.name}: could not read file');
        continue;
      }
      final outcome = await provider.uploadFile(
        fileName: file.name,
        bytes: Uint8List.fromList(bytes),
      );
      if (outcome.ok) {
        ok++;
      } else {
        failures.add(outcome.message);
      }
    }
    if (!mounted) return;
    if (failures.isEmpty) {
      _snack(ok == 1 ? '${result.files.first.name} uploaded' : '$ok files uploaded');
    } else {
      _snack(failures.first);
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

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String _kindOf(GithubFileItem item) {
    if (item.isDirectory) return 'dir';
    final dot = item.name.lastIndexOf('.');
    final ext = dot > 0 ? item.name.substring(dot + 1).toLowerCase() : '';
    if (const {'png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'bmp', 'ico', 'avif'}.contains(ext)) {
      return 'image';
    }
    if (const {'mp4', 'webm', 'mkv', 'avi', 'mov', 'ogv'}.contains(ext)) return 'video';
    if (const {'mp3', 'wav', 'ogg', 'flac', 'm4a', 'aac'}.contains(ext)) return 'audio';
    if (const {'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz'}.contains(ext)) return 'archive';
    if (const {'pdf', 'doc', 'docx', 'txt', 'md', 'markdown', 'xls', 'xlsx', 'csv', 'json', 'xml', 'yaml', 'yml', 'log'}.contains(ext)) {
      return 'doc';
    }
    if (const {'js', 'mjs', 'ts', 'tsx', 'jsx', 'dart', 'py', 'rb', 'go', 'rs', 'java', 'kt', 'c', 'h', 'cpp', 'hpp', 'cs', 'php', 'sh', 'html', 'css', 'scss', 'sql', 'toml', 'ini', 'conf'}.contains(ext)) {
      return 'code';
    }
    return 'file';
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

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _GridCard extends StatelessWidget {
  final GithubFileItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _GridCard({required this.item, required this.onTap, required this.onLongPress});

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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isDir ? Icons.folder : Icons.insert_drive_file_outlined,
                size: 38,
                color: isDir ? const Color(0xFFF2B429) : cs.primary,
              ),
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
                isDir ? 'folder' : _ExplorerScreenState._formatSize(item.size),
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              ),
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
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Icon(Icons.cloud_outlined, size: 42, color: cs.onPrimaryContainer),
            ),
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
