import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../config.dart';
import '../models/account.dart';
import '../models/file_item.dart';
import '../services/github_service.dart';

class ReveProvider with ChangeNotifier {
  static T? _firstOrNull<T>(Iterable<T> items, bool Function(T) test) {
    for (final item in items) {
      if (test(item)) return item;
    }
    return null;
  }

  static const String _boxName = 'reve_accounts_box';
  static const String _activeIdKey = 'active_account_id';
  static const String _autoSortKey = 'auto_sort_uploads';
  static const String _clientIdKey = 'oauth_client_id';
  static const String _backendKey = 'oauth_backend';

  /// GitHub's Contents API rejects anything above 100 MB. Base64 + JSON adds
  /// overhead, so stay comfortably below it.
  static const int maxUploadBytes = 95 * 1024 * 1024;

  final List<GithubAccount> _accounts = [];
  GithubAccount? _activeAccount;

  List<Map<String, dynamic>> _repositories = [];
  Map<String, dynamic>? _selectedRepo;
  List<String> _branches = [];
  String? _selectedBranch;

  String _currentPath = '';
  List<GithubFileItem> _files = [];
  bool _isLoading = false;
  bool _isUploading = false;
  String? _errorMessage;
  bool _autoSortUploads = true;
  int _lastRateLimit = -1;
  String _oauthClientId = AppConfig.oauthClientId;
  String _oauthBackend = AppConfig.deviceFlowBackend ?? '';

  List<GithubAccount> get accounts => List.unmodifiable(_accounts);
  GithubAccount? get activeAccount => _activeAccount;
  List<Map<String, dynamic>> get repositories => _repositories;
  Map<String, dynamic>? get selectedRepo => _selectedRepo;
  List<String> get branches => _branches;
  String? get selectedBranch => _selectedBranch;
  String get currentPath => _currentPath;
  List<GithubFileItem> get files => _files;
  bool get isLoading => _isLoading;
  bool get isUploading => _isUploading;
  String? get errorMessage => _errorMessage;
  bool get autoSortUploads => _autoSortUploads;
  int get lastRateLimit => _lastRateLimit;
  bool get isConnected => _activeAccount != null;
  String get oauthClientId => _oauthClientId;
  String get oauthBackend => _oauthBackend;

  String get owner =>
      (_selectedRepo?['owner']?['login'] as String?) ?? '';

  String get repoName => (_selectedRepo?['name'] as String?) ?? '';

  ReveProvider() {
    init();
  }

  Future<void> init() async {
    try {
      final box = await Hive.openBox(_boxName);
      final rawAccounts = box.get('accounts', defaultValue: <dynamic>[]);
      _accounts
        ..clear()
        ..addAll((rawAccounts as List)
            .map((e) => GithubAccount.fromJson(Map<String, dynamic>.from(e as Map))));
      _autoSortUploads = box.get(_autoSortKey, defaultValue: true) as bool;
      _oauthClientId = (box.get(_clientIdKey, defaultValue: _oauthClientId) as String?) ?? _oauthClientId;
      _oauthBackend = (box.get(_backendKey, defaultValue: _oauthBackend) as String?) ?? _oauthBackend;

      final activeId = box.get(_activeIdKey);
      if (_accounts.isNotEmpty) {
        _activeAccount = _firstOrNull(_accounts, (a) => a.id == activeId) ?? _accounts.first;
      }
      notifyListeners();
      if (_activeAccount != null) await fetchRepositories();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> _saveToBox() async {
    final box = await Hive.openBox(_boxName);
    await box.put('accounts', _accounts.map((a) => a.toJson()).toList());
    if (_activeAccount != null) {
      await box.put(_activeIdKey, _activeAccount!.id);
    } else {
      await box.delete(_activeIdKey);
    }
    await box.put(_autoSortKey, _autoSortUploads);
    await box.put(_clientIdKey, _oauthClientId);
    await box.put(_backendKey, _oauthBackend);
  }

  Future<void> setOAuthSettings({String? clientId, String? backend}) async {
    if (clientId != null) {
      _oauthClientId = clientId.trim();
    }
    if (backend != null) {
      _oauthBackend = backend.trim().replaceAll(RegExp(r'/+$'), '');
    }
    await _saveToBox();
    notifyListeners();
  }

  void toggleAutoSort(bool value) {
    _autoSortUploads = value;
    _saveToBox();
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Accounts
  // ---------------------------------------------------------------------------

  Future<bool> addAccount(String token, String type) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final account = await GithubService.verifyAndGetUser(token, type);
      _accounts.removeWhere((a) => a.id == account.id);
      _accounts.insert(0, account);
      _activeAccount = account;
      await _saveToBox();
      notifyListeners();
      await fetchRepositories();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> switchAccount(String id) async {
    final account = _firstOrNull(_accounts, (a) => a.id == id);
    if (account == null) return;
    _activeAccount = account;
    _resetBrowseState();
    await _saveToBox();
    notifyListeners();
    await fetchRepositories();
  }

  Future<void> removeAccount(String id) async {
    _accounts.removeWhere((a) => a.id == id);
    if (_activeAccount?.id == id) {
      _activeAccount = _accounts.isEmpty ? null : _accounts.first;
      _resetBrowseState();
    }
    await _saveToBox();
    notifyListeners();
    if (_activeAccount != null) await fetchRepositories();
  }

  void _resetBrowseState() {
    _currentPath = '';
    _selectedRepo = null;
    _selectedBranch = null;
    _repositories = [];
    _branches = [];
    _files = [];
  }

  // ---------------------------------------------------------------------------
  // Repositories
  // ---------------------------------------------------------------------------

  Future<void> fetchRepositories() async {
    if (_activeAccount == null) return;
    _isLoading = true;
    notifyListeners();
    try {
      final repos = await GithubService.getRepositories(_activeAccount!.token);
      _repositories = repos;
      _errorMessage = null;

      final previousId = _selectedRepo?['id'];
      final keep = previousId != null
          ? _firstOrNull(repos, (r) => r['id'] == previousId)
          : null;

      if (keep != null) {
        _selectedRepo = keep;
      } else if (repos.isNotEmpty) {
        _selectedRepo = repos.first;
        _currentPath = '';
      }
      notifyListeners();
      if (_selectedRepo != null) await fetchBranches();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createRepository(
    String name, {
    String? description,
    bool isPrivate = true,
  }) async {
    if (_activeAccount == null) return false;
    _isLoading = true;
    notifyListeners();
    try {
      final repo = await GithubService.createRepository(
        _activeAccount!.token,
        name: name,
        description: description,
        private: isPrivate,
      );
      await fetchRepositories();
      final created = _firstOrNull(_repositories, (r) => r['id'] == repo['id']);
      if (created != null) {
        _selectedRepo = created;
        await fetchBranches();
      }
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> selectRepository(Map<String, dynamic> repo) async {
    if (_selectedRepo?['id'] == repo['id']) return;
    _selectedRepo = repo;
    _currentPath = '';
    _selectedBranch = null;
    _branches = [];
    _files = [];
    notifyListeners();
    await fetchBranches();
  }

  Future<void> fetchBranches() async {
    if (_activeAccount == null || _selectedRepo == null) return;
    try {
      _branches = await GithubService.getBranches(
        _activeAccount!.token,
        owner,
        repoName,
      );
      final fallback = _selectedRepo!['default_branch'] as String?;
      if (_branches.contains(fallback)) {
        _selectedBranch = fallback;
      } else if (_branches.isNotEmpty) {
        _selectedBranch = _branches.first;
      } else {
        _selectedBranch = null;
      }
      notifyListeners();
      await fetchContents();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> selectBranch(String branch) async {
    _selectedBranch = branch;
    _currentPath = '';
    notifyListeners();
    await fetchContents();
  }

  // ---------------------------------------------------------------------------
  // Browsing
  // ---------------------------------------------------------------------------

  Future<void> fetchContents() async {
    if (_activeAccount == null || _selectedRepo == null) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final items = await GithubService.getContents(
        _activeAccount!.token,
        owner,
        repoName,
        _currentPath,
        branch: _selectedBranch,
      );
      items.sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      _files = items;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> navigateToFolder(String path) async {
    _currentPath = path;
    await fetchContents();
  }

  Future<void> navigateUp() async {
    if (_currentPath.isEmpty) return;
    final parts = _currentPath.split('/');
    parts.removeLast();
    _currentPath = parts.join('/');
    await fetchContents();
  }

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  static String categoryFor(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final ext = dot > 0 ? fileName.substring(dot + 1).toLowerCase() : '';
    const images = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'bmp', 'ico', 'avif'};
    const media = {'mp4', 'webm', 'mkv', 'avi', 'mov', 'mp3', 'wav', 'ogg', 'flac', 'm4a', 'aac'};
    const documents = {'pdf', 'doc', 'docx', 'txt', 'md', 'markdown', 'xls', 'xlsx', 'csv', 'json', 'xml', 'yaml', 'yml'};
    const archives = {'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz'};
    const code = {'js', 'mjs', 'ts', 'tsx', 'jsx', 'dart', 'py', 'rb', 'go', 'rs', 'java', 'kt', 'c', 'h', 'cpp', 'cs', 'php', 'sh', 'html', 'css', 'scss', 'sql'};
    if (images.contains(ext)) return 'images';
    if (media.contains(ext)) return 'media';
    if (documents.contains(ext)) return 'documents';
    if (archives.contains(ext)) return 'archives';
    if (code.contains(ext)) return 'code';
    return 'others';
  }

  String _targetPathFor(String fileName) {
    final base = _currentPath.isEmpty ? '' : '${_currentPath.replaceAll(RegExp(r'/+$'), '')}/';
    if (!_autoSortUploads) return '$base$fileName';
    return '$base${categoryFor(fileName)}/$fileName';
  }

  Future<UploadResult> uploadFile({
    required String fileName,
    required Uint8List bytes,
    String? message,
  }) async {
    if (_activeAccount == null || _selectedRepo == null) {
      return const UploadResult(false, 'Connect an account and pick a repository first.');
    }
    if (bytes.lengthInBytes > maxUploadBytes) {
      return UploadResult(
        false,
        '$fileName is larger than the 95 MB Contents API limit. Use the Git LFS route or split the file.',
      );
    }

    _isUploading = true;
    notifyListeners();
    final path = _targetPathFor(fileName);
    try {
      try {
        await GithubService.uploadFile(
          token: _activeAccount!.token,
          owner: owner,
          repo: repoName,
          path: path,
          bytes: bytes,
          message: message ?? 'Upload $fileName via reve',
          branch: _selectedBranch,
        );
      } on Exception {
        // The path may already exist: fetch its blob sha and overwrite.
        final existing = await GithubService.getContents(
          _activeAccount!.token,
          owner,
          repoName,
          _currentPath,
          branch: _selectedBranch,
        );
        final match = _firstOrNull(existing, (f) => f.path == path);
        if (match == null) rethrow;
        await GithubService.uploadFile(
          token: _activeAccount!.token,
          owner: owner,
          repo: repoName,
          path: path,
          bytes: bytes,
          message: message ?? 'Update $fileName via reve',
          branch: _selectedBranch,
          sha: match.sha,
        );
      }
      await fetchContents();
      return UploadResult(true, '$fileName uploaded to $path', path: path);
    } catch (e) {
      _errorMessage = e.toString();
      return UploadResult(false, e.toString());
    } finally {
      _isUploading = false;
      notifyListeners();
    }
  }

  Future<bool> deleteItem(GithubFileItem item, {String? message}) async {
    if (_activeAccount == null || _selectedRepo == null) return false;
    _isLoading = true;
    notifyListeners();
    try {
      final msg = message ?? 'Delete ${item.path} via reve';
      if (item.isDirectory) {
        await GithubService.deleteDirectory(
          token: _activeAccount!.token,
          owner: owner,
          repo: repoName,
          path: item.path,
          message: msg,
          branch: _selectedBranch,
        );
      } else {
        await GithubService.deleteFile(
          token: _activeAccount!.token,
          owner: owner,
          repo: repoName,
          path: item.path,
          sha: item.sha,
          message: msg,
          branch: _selectedBranch,
        );
      }
      await fetchContents();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createFolder(String folderName, {String? message}) async {
    if (_activeAccount == null || _selectedRepo == null) return false;
    final clean = folderName.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    if (clean.isEmpty) return false;

    _isLoading = true;
    notifyListeners();
    try {
      final folderPath = _currentPath.isEmpty ? clean : '$_currentPath/$clean';
      await GithubService.createFolder(
        token: _activeAccount!.token,
        owner: owner,
        repo: repoName,
        folderPath: folderPath,
        message: message ?? 'Create folder $clean via reve',
        branch: _selectedBranch,
      );
      await fetchContents();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  String? downloadUrlFor(GithubFileItem item) {
    if (_selectedRepo == null) return item.downloadUrl;
    return GithubService.rawUrl(owner, repoName, _selectedBranch ?? '', item.path);
  }

  Future<String> readText(GithubFileItem item) async {
    if (_activeAccount == null || _selectedRepo == null) {
      throw Exception('No repository selected');
    }
    return GithubService.getTextFile(
      _activeAccount!.token,
      owner,
      repoName,
      item.path,
      branch: _selectedBranch,
    );
  }
}

class UploadResult {
  final bool ok;
  final String message;
  final String? path;

  const UploadResult(this.ok, this.message, {this.path});
}
