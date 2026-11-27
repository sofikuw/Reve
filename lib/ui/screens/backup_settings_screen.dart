import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/reve_provider.dart';
import '../theme.dart';

/// Advanced controls for camera backup: where it goes, how much it takes and
/// whether it runs on its own.
class BackupSettingsScreen extends StatefulWidget {
  const BackupSettingsScreen({super.key});

  @override
  State<BackupSettingsScreen> createState() => _BackupSettingsScreenState();
}

class _BackupSettingsScreenState extends State<BackupSettingsScreen> {
  late final TextEditingController _folder;

  @override
  void initState() {
    super.initState();
    _folder = TextEditingController(
      text: context.read<ReveProvider>().backupFolder,
    );
  }

  @override
  void dispose() {
    _folder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReveProvider>();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Auto backup')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 40),
        children: [
          Card(
            child: SwitchListTile(
              secondary: Icon(Icons.backup_rounded, color: cs.primary),
              title: const Text('Automatic upload'),
              subtitle: const Text(
                'Backs up new camera photos and videos on launch and every 15 minutes.',
              ),
              value: provider.autoBackup,
              onChanged: (value) => provider.setAutoBackup(value),
            ),
          ),
          const SizedBox(height: 12),
          _section(cs, 'Destination'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Repository',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  DropdownButton<int?>(
                    value: provider.repositories.any(
                            (r) => r['id'] == provider.backupRepoId)
                        ? provider.backupRepoId
                        : null,
                    isExpanded: true,
                    hint: const Text('Choose a repository'),
                    items: [
                      for (final repo in provider.repositories)
                        DropdownMenuItem<int?>(
                          value: repo['id'] as int?,
                          child: Text(
                            (repo['full_name'] ?? repo['name'] ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (id) => provider.setBackupRepo(id),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _folder,
                    decoration: const InputDecoration(
                      labelText: 'Destination folder',
                      hintText: 'Camera',
                      prefixIcon: Icon(Icons.folder_rounded),
                    ),
                    onEditingComplete: () =>
                        provider.setBackupFolder(_folder.text),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Files keep your auto-sort subfolder inside it '
                    '(e.g. Camera/videos/…).',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _section(cs, 'Limits'),
          Card(
            child: Column(
              children: [
                _choice<int>(
                  context,
                  icon: Icons.numbers_rounded,
                  title: 'Items per run',
                  value: provider.backupLimit,
                  options: const [3, 6, 12, 24],
                  label: (n) => '$n files',
                  onChanged: (v) => provider.setBackupLimit(v),
                ),
                const Divider(height: 1),
                _choice<int>(
                  context,
                  icon: Icons.sd_storage_rounded,
                  title: 'Skip files larger than',
                  value: provider.backupMaxBytes,
                  options: const [
                    38 * 1024 * 1024,
                    100 * 1024 * 1024,
                    500 * 1024 * 1024,
                    2 * 1024 * 1024 * 1024,
                  ],
                  label: (n) => n >= 1024 * 1024 * 1024
                      ? '${n ~/ (1024 * 1024 * 1024)} GB'
                      : '${n ~/ (1024 * 1024)} MB',
                  onChanged: (v) => provider.setBackupMaxBytes(v),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.video_file_rounded),
                  title: const Text('Include videos'),
                  subtitle: const Text('Videos can be much larger than photos'),
                  value: provider.backupVideos,
                  onChanged: (v) => provider.setBackupVideos(v),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.wifi_rounded),
                  title: const Text('Wi-Fi only'),
                  subtitle: const Text('Skip backups when on mobile data'),
                  value: provider.wifiOnly,
                  onChanged: (v) => provider.setWifiOnly(v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Last run ${provider.backupSince}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    provider.errorMessage ?? 'No problems reported.',
                    style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: provider.backingUp
                        ? null
                        : () => provider.runAutoBackup(),
                    icon: provider.backingUp
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.backup_rounded),
                    label: Text(provider.backingUp ? 'Backing up…' : 'Back up now'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(ColorScheme cs, String title) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: cs.onSurfaceVariant,
          ),
        ),
      );

  Widget _choice<T>(
    BuildContext context, {
    required IconData icon,
    required String title,
    required T value,
    required List<T> options,
    required String Function(T) label,
    required ValueChanged<T> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: cs.primary),
      title: Text(title, style: const TextStyle(fontSize: 13.5)),
      trailing: DropdownButton<T>(
        value: options.contains(value) ? value : options.first,
        items: [
          for (final option in options)
            DropdownMenuItem<T>(value: option, child: Text(label(option))),
        ],
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      ),
    );
  }
}
