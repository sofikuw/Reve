import 'package:flutter/material.dart';
import '../../models/file_item.dart';
import '../../providers/reve_provider.dart';
import '../../services/github_service.dart';

/// Commits that touched one file, with one-tap restore.
class VersionHistoryScreen extends StatefulWidget {
  const VersionHistoryScreen({
    super.key,
    required this.provider,
    required this.item,
  });

  final ReveProvider provider;
  final GithubFileItem item;

  @override
  State<VersionHistoryScreen> createState() => _VersionHistoryScreenState();
}

class _VersionHistoryScreenState extends State<VersionHistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  String? _error;
  bool _loading = true;

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
        path: widget.item.path,
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
      appBar: AppBar(title: const Text('Version history')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : _history.isEmpty
                  ? const Center(child: Text('No commits for this file yet'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 30),
                      itemCount: _history.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final entry = _history[index];
                        final date = DateTime.tryParse(entry['date'] as String? ?? '');
                        return Card(
                          child: ListTile(
                            title: Text(
                              (entry['message'] as String).split('\n').first,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${entry['author']} · ${date != null ? date.toLocal().toString().split('.').first : 'unknown date'}',
                            ),
                            trailing: TextButton(
                              onPressed: () async {
                                final ok = await widget.provider.restoreVersion(
                                  widget.item.path,
                                  entry['sha'] as String,
                                );
                                if (context.mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(ok
                                          ? 'Version restored'
                                          : widget.provider.errorMessage ??
                                              'Could not restore'),
                                    ),
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
