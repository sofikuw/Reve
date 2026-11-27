import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/reve_provider.dart';

/// Sets the passphrase used to encrypt files placed in the Vault folder.
class VaultSettingsScreen extends StatefulWidget {
  const VaultSettingsScreen({super.key});

  @override
  State<VaultSettingsScreen> createState() => _VaultSettingsScreenState();
}

class _VaultSettingsScreenState extends State<VaultSettingsScreen> {
  final _controller = TextEditingController();
  bool _enabled = false;
  String? _recovery;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = context.read<ReveProvider>();
    final enabled = await provider.hasVaultKey();
    final recovery = enabled ? await provider.recoveryKey() : null;
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _recovery = recovery;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Encrypted vault')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Files uploaded into the Vault folder are encrypted on this device '
            'before they reach GitHub. Only a device with this passphrase can '
            'read them back.',
            style: TextStyle(fontSize: 13, height: 1.5, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _controller,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Vault passphrase',
              hintText: 'At least 8 characters',
              prefixIcon: Icon(Icons.key_outlined),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () async {
              if (_controller.text.trim().length < 8) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Use at least 8 characters')),
                );
                return;
              }
              await context.read<ReveProvider>().setVaultPassphrase(_controller.text);
              _controller.clear();
              await _load();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Vault passphrase saved')),
                );
              }
            },
            icon: const Icon(Icons.lock_outline),
            label: Text(_enabled ? 'Change passphrase' : 'Enable vault'),
          ),
          if (_recovery != null) ...[
            const SizedBox(height: 24),
            Text('Recovery key', style: TextStyle(fontWeight: FontWeight.w700, color: cs.error)),
            const SizedBox(height: 6),
            SelectableText(_recovery!, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _recovery!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Recovery key copied')),
                );
              },
              icon: const Icon(Icons.copy_all_outlined),
              label: const Text('Copy recovery key'),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            'Note: 2FA for your GitHub account is managed at github.com/settings/security.',
            style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
