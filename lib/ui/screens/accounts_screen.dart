import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../providers/reve_provider.dart';
import '../../services/github_service.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  final _tokenController = TextEditingController();
  final _clientIdController = TextEditingController();
  final _backendController = TextEditingController();
  bool _obscure = true;
  String _mode = 'pat';

  @override
  void initState() {
    super.initState();
    final provider = context.read<ReveProvider>();
    _clientIdController.text = provider.oauthClientId;
    _backendController.text = provider.oauthBackend;
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _clientIdController.dispose();
    _backendController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReveProvider>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('GitHub accounts')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          if (provider.accounts.isEmpty)
            _EmptyAccounts(cs: cs)
          else
            ...provider.accounts.map((account) {
              final isActive = provider.activeAccount?.id == account.id;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                elevation: isActive ? 2 : 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(
                    color: isActive ? cs.primary : cs.outlineVariant,
                    width: isActive ? 1.5 : 1,
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  leading: CircleAvatar(
                    backgroundImage:
                        account.avatarUrl != null ? NetworkImage(account.avatarUrl!) : null,
                    child: account.avatarUrl == null
                        ? Text(account.username.isEmpty
                            ? '?'
                            : account.username.substring(0, 1).toUpperCase())
                        : null,
                  ),
                  title: Text(
                    account.name?.isNotEmpty == true ? account.name! : account.username,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '@${account.username} · ${account.type.toUpperCase()} · '
                    '${account.token.substring(0, 4)}…${account.token.substring(account.token.length - 4)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isActive)
                        Chip(
                          label: const Text('Active'),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: cs.primaryContainer,
                          labelStyle: TextStyle(color: cs.onPrimaryContainer, fontSize: 11),
                        )
                      else
                        TextButton(
                          onPressed: () => provider.switchAccount(account.id),
                          child: const Text('Use'),
                        ),
                      IconButton(
                        tooltip: 'Remove',
                        icon: Icon(Icons.delete_outline, color: cs.error),
                        onPressed: () => _confirmRemove(provider, account.id, account.username),
                      ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 18),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'pat', label: Text('Personal token'), icon: Icon(Icons.key)),
              ButtonSegment(value: 'oauth', label: Text('OAuth'), icon: Icon(Icons.login)),
            ],
            selected: {_mode},
            onSelectionChanged: (v) => setState(() => _mode = v.first),
          ),
          const SizedBox(height: 16),
          if (_mode == 'pat') _buildPat(cs) else _buildOAuth(cs),
        ],
      ),
    );
  }

  Widget _buildPat(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _tokenController,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Personal access token',
            hintText: 'ghp_… or github_pat_…',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Needs the repo scope (classic) or Contents: read & write (fine-grained).',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Create a token on GitHub'),
            onPressed: () => launchUrl(
              Uri.parse('https://github.com/settings/tokens/new?scopes=repo&description=reve'),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ),
        const SizedBox(height: 6),
        FilledButton.icon(
          onPressed: () => _submitToken(_tokenController.text.trim(), 'pat'),
          icon: const Icon(Icons.key),
          label: const Text('Connect with token'),
        ),
      ],
    );
  }

  Widget _buildOAuth(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _clientIdController,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'OAuth App client ID',
            hintText: 'Iv1.…',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Device flow only needs the public client ID — enable "Device flow" '
          'on the OAuth App. The client secret never ships in the app.',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        if (kIsWeb) ...[
          TextField(
            controller: _backendController,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'OAuth broker URL',
              hintText: 'https://reve-oauth.you.workers.dev',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Browsers cannot call the device endpoint directly (CORS), so the '
            'GitHub calls are proxied through your broker. Same broker as the '
            'popup flow — no secret needed for device codes.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
        ],
        FilledButton.icon(
          onPressed: _startDeviceFlow,
          icon: const Icon(Icons.login),
          label: const Text('Sign in with GitHub'),
        ),
        const SizedBox(height: 8),
        Text(
          'Opens github.com/login/device, copies the code to your clipboard and '
          'waits for you to approve it.',
          style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  Future<void> _submitToken(String token, String type) async {
    if (token.isEmpty) {
      _snack('Enter a token first');
      return;
    }
    final provider = context.read<ReveProvider>();
    final ok = await provider.addAccount(token, type);
    if (!mounted) return;
    if (ok) {
      _tokenController.clear();
      _snack('Connected as @${provider.activeAccount?.username ?? ''}');
      Navigator.of(context).maybePop();
    } else {
      _snack(provider.errorMessage ?? 'Could not connect');
    }
  }

  Future<void> _startDeviceFlow() async {
    final clientId = _clientIdController.text.trim();
    final backend = _backendController.text.trim();
    if (clientId.isEmpty) {
      _snack('Add your OAuth App client ID first');
      return;
    }
    if (kIsWeb && backend.isEmpty) {
      _snack('Add your OAuth broker URL — browsers need it for device codes');
      return;
    }

    final provider = context.read<ReveProvider>();
    await provider.setOAuthSettings(clientId: clientId, backend: backend);

    DeviceAuthorization auth;
    try {
      auth = await GithubService.startDeviceFlow(
        clientId,
        scope: AppConfig.oauthScope,
        backend: backend.isEmpty ? null : backend,
      );
    } catch (e) {
      _snack(_friendlyError(e));
      return;
    }
    if (!mounted) return;

    // Hand the code over the way people expect: clipboard + browser.
    await Clipboard.setData(ClipboardData(text: auth.userCode));
    final opened = await launchUrl(
      Uri.parse(auth.verificationUri),
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (!mounted) return;

    var cancelled = false;
    var busy = false;
    Timer? timer;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> poll() async {
              if (busy || cancelled) return;
              busy = true;
              try {
                final token = await GithubService.pollDeviceFlow(
                  clientId,
                  auth.deviceCode,
                  backend: backend.isEmpty ? null : backend,
                );
                if (token != null && dialogContext.mounted) {
                  timer?.cancel();
                  Navigator.of(dialogContext).pop();
                  final ok = await provider.addAccount(token, 'oauth');
                  if (!mounted) return;
                  _snack(ok
                      ? 'Connected as @${provider.activeAccount?.username ?? ''}'
                      : (provider.errorMessage ?? 'Could not connect'));
                  if (ok && mounted) Navigator.of(this.context).maybePop();
                }
              } catch (e) {
                timer?.cancel();
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                if (mounted) _snack(e.toString());
              } finally {
                busy = false;
              }
            }

            if (timer == null) {
              timer = Timer.periodic(
                Duration(seconds: auth.intervalSeconds < 5 ? 5 : auth.intervalSeconds),
                (_) => poll(),
              );
            }

            return AlertDialog(
              title: const Text('Authorize reve'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    opened
                        ? 'Code copied — paste it in the GitHub tab.'
                        : 'Code copied. Open GitHub and paste this code:',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    auth.userCode,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Open github.com/login/device'),
                    onPressed: () => launchUrl(
                      Uri.parse(auth.verificationUri),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy code'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: auth.userCode));
                      _snack('Code copied');
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Waiting for authorization… this closes automatically.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    cancelled = true;
                    timer?.cancel();
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );

    cancelled = true;
    timer?.cancel();
  }

  Future<void> _confirmRemove(ReveProvider provider, String id, String username) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove @$username?'),
        content: const Text('The token is deleted from this device. Nothing on GitHub changes.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) await provider.removeAccount(id);
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    final lower = text.toLowerCase();
    final networkish = lower.contains('clientexception') ||
        lower.contains('socketexception') ||
        lower.contains('timeoutexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection abort');

    if (networkish) {
      if (kIsWeb && _backendController.text.trim().isEmpty) {
        return 'Browser sign-in needs the OAuth broker: deploy api/oauth.js to '
            'Vercel or the Cloudflare Worker, then paste its URL under Settings.';
      }
      return GithubService.networkErrorMessage(error);
    }
    return text;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _EmptyAccounts extends StatelessWidget {
  final ColorScheme cs;
  const _EmptyAccounts({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(Icons.cloud_off_outlined, size: 38, color: cs.onPrimaryContainer),
          ),
          const SizedBox(height: 16),
          const Text('No accounts connected',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            'Use a personal access token — it is the fastest route and '
            'needs no backend.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
