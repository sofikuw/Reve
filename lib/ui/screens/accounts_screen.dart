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
  bool _showToken = false;

  @override
  void dispose() {
    _tokenController.dispose();
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
          _buildSignIn(cs),
          _buildAppLock(provider, cs),
        ],
      ),
    );
  }

  Widget _buildAppLock(ReveProvider provider, ColorScheme cs) {
    final locked = provider.isLocked;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: ListTile(
        leading: Icon(
          locked ? Icons.lock : Icons.lock_open_outlined,
          color: locked ? cs.error : cs.primary,
        ),
        title: Text(locked ? 'App lock: on' : 'App lock'),
        subtitle: const Text('Ask for a PIN when the app resumes'),
        onTap: () => _setAppLock(provider),
      ),
    );
  }

  Future<void> _setAppLock(ReveProvider provider) async {
    final controller = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(provider.isLocked ? 'App lock' : 'Enable app lock'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: '4–8 digit PIN',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (pin == null) return;
    final trimmed = pin.trim();
    if (trimmed.isEmpty) {
      await provider.clearPin();
      _snack('App lock off');
      return;
    }
    await provider.setPin(trimmed);
    if (mounted) {
      final error = provider.errorMessage;
      _snack(error ?? 'App lock: on');
    }
  }

  Widget _buildSignIn(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _tokenController,
          autocorrect: false,
          enableSuggestions: false,
          obscureText: !_showToken,
          onSubmitted: (_) => _useToken(),
          decoration: InputDecoration(
            labelText: 'Personal access token',
            hintText: 'ghp_… or github_pat_…',
            border: const OutlineInputBorder(),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: _showToken ? 'Hide' : 'Show',
                  icon: Icon(_showToken ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _showToken = !_showToken),
                ),
                IconButton(
                  tooltip: 'Paste',
                  icon: const Icon(Icons.content_paste),
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    final text = data?.text?.trim();
                    if (text == null || text.isEmpty) return;
                    setState(() => _tokenController.text = text);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'A classic token with the repo scope, or a fine-grained token with '
          'Contents: read and write. It is stored on this device only.',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _useToken,
                icon: const Icon(Icons.key_outlined),
                label: const Text('Use token'),
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () => launchUrl(
                Uri.parse('https://github.com/settings/tokens/new?scopes=repo&description=reve'),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Create'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: Divider(color: cs.outlineVariant)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('or', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ),
            Expanded(child: Divider(color: cs.outlineVariant)),
          ],
        ),
        const SizedBox(height: 14),
        FilledButton.tonalIcon(
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

  Future<void> _useToken() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      _snack('Paste a personal access token first');
      return;
    }
    final provider = context.read<ReveProvider>();
    final ok = await provider.addAccount(token, 'pat');
    if (!mounted) return;
    if (!ok) {
      _snack(provider.errorMessage ?? 'Could not connect');
      return;
    }
    _tokenController.clear();
    _snack('Connected as @${provider.activeAccount?.username ?? ''}');
    Navigator.of(context).maybePop();
  }

  Future<void> _startDeviceFlow() async {
    final provider = context.read<ReveProvider>();
    final clientId = provider.oauthClientId;
    final backend = provider.oauthBackend;
    if (clientId.isEmpty) {
      _snack('This build has no OAuth client ID baked in');
      return;
    }
    if (kIsWeb && backend.isEmpty) {
      _snack('This build has no OAuth broker baked in');
      return;
    }

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
      if (kIsWeb && AppConfig.oauthBackend.isEmpty) {
        return 'Browser sign-in needs an OAuth broker: deploy api/oauth.js to '
            'Vercel or the Cloudflare Worker and pass it as OAUTH_BACKEND.';
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
            'Paste a personal access token, or sign in with GitHub and let the '
            'device code do the handshake for you.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
