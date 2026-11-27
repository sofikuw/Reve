import 'package:flutter/material.dart';

import '../../providers/reve_provider.dart';
import '../../services/github_service.dart';

/// Restores a whole folder to an earlier commit.
class RewindScreen extends StatefulWidget {
  const RewindScreen({super.key, required this.provider, required this.folder});

  final ReveProvider provider;
  final String folder;

  @override
  State<RewindScreen> createState() => _RewindScreenState();
}

class _RewindScreenState extends State<RewindScreen> {
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = widget.provider;
    final account = p.activeAccount;
    if (account == null) {
      setState(() {
        _loading = false;
        _error = 'Connect an account first';
      });
      return;
    }
    try {
      final list = await GithubService.fileHistory(
        token: account.token,
        owner: p.selectedRepo?['owner']?['login'] as String? ?? '',
        repo: p.repoName,
        path: widget.folder,
        branch: p.selectedBranch,
      );
      if (!mounted) return;
      setState(() {
        _history = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rewind folder')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : _history.isEmpty
                  ? const Center(child: Text('No commits for this folder'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 30),
                      itemCount: _history.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final entry = _history[index];
                        return Card(
                          child: ListTile(
                            title: Text(
                              (entry['message'] as String).split('\n').first,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(entry['date'] as String? ?? ''),
                            trailing: TextButton(
                              onPressed: () async {
                                final ok = await widget.provider.rewindFolder(
                                  widget.folder,
                                  entry['sha'] as String,
                                );
                                if (context.mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(ok ? 'Folder restored' : 'Restore failed')),
                                  );
                                }
                              },
                              child: const Text('Restore'),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
