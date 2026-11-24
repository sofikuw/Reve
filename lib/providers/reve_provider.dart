import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../config.dart';
import '../models/account.dart';
import '../models/file_item.dart';
import '../services/github_service.dart';
import '../services/updater.dart';

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
  static const String _updateChannelKey = 'update_channel';
  static const String _reposKey = 'cached_repositories';
  static const String _repoIdKey = 'cached_repo_id';
  static const String _branchKey = 'cached_branch';
  static const String _pathKey = 'cached_path';

  /// GitHub caps a Contents API request body at about 52 MB, and base64 makes a
  /// file 4/3 its size, so the real per-file ceiling is 39 MiB — measured: a
  /// 39 MiB file lands, 40 MiB comes back 422 "the file is too large to be
  /// processed". Stay one MiB below that.
  static const int maxUploadBytes = 38 * 1024 * 1024;
  /// Older files are still undoable after a delete.
  static const int maxUndoBytes = 8 * 1024 * 1024;

  final List<GithubAccount> _accounts = [];
  GithubAccount? _activeAccount;

  List<Map<String, dynamic>> _repositories = [];
  Map<String, dynamic>? _selectedRepo;
  List<String> _branches = [];
  String? _selectedBranch;

  String _currentPath = '';
  List<GithubFileItem> _files = [];
  final Map<String, List<GithubFileItem>> _listingCache = {};

  /// Logical path → release-asset metadata, read from `.reve/assets.json`.
  Map<String, Map<String, dynamic>> _assets = {};
  /// Everything the release itself holds, including assets the index does not
  /// mention (a failed index write, or an upload from another device).
  List<Map<String, dynamic>> _releaseAssets = [];
  String? _assetsKey;
  String? _assetsSha;
  bool _assetsLoaded = false;
  DateTime? _assetsAt;

  /// Last listing per branch+path, kept in Hive so a failed refresh still
  /// shows the folder offline.
  Map<String, Map<String, dynamic>> _diskCache = {};
  List<GithubFileItem> _offlineItems = [];
  DateTime? _offlineAt;

  bool _isLoading = false;
  bool _isUploading = false;
  String? _errorMessage;

  /// `null` while idle; 0…1 while a transfer knows its size. When the size is
  /// unknown the bar is indeterminate and [progress] stays `null`.
  double? _progress;
  bool _progressIndeterminate = false;
  String? _progressLabel;
  int _progressStep = -1;
  bool _autoSortUploads = true;
  int _lastRateLimit = -1;
  UpdateChannel _updateChannel = UpdateChannel.stable;
  UpdateInfo? _update;
  bool _checkingUpdate = false;
  String? _updateError;
  int _updateRequest = 0;

  List<GithubAccount> get accounts => List.unmodifiable(_accounts);
  GithubAccount? get activeAccount => _activeAccount;
  List<Map<String, dynamic>> get repositories => _repositories;
  Map<String, dynamic>? get selectedRepo => _selectedRepo;
  List<String> get branches => _branches;
  String? get selectedBranch => _selectedBranch;
  String get currentPath => _currentPath;
  List<GithubFileItem> get files => _files;
  /// Snapshot of the last successful listing when the network failed, so the
  /// folder can still be viewed offline.
  List<GithubFileItem> get offlineItems => _offlineItems;
  DateTime? get offlineAt => _offlineAt;
  /// "just now" / "5 min ago" style age of [offlineAt], empty when none.
  String get offlineSince {
    if (_offlineAt == null) return '';
    final minutes = DateTime.now().difference(_offlineAt!).inMinutes;
    return minutes < 1 ? 'just now' : '$minutes min ago';
  }
  /// Bytes held as release assets, for the storage meter.
  int get assetBytes => _assets.values.fold(
        0,
        (sum, file) => sum + ((file['size'] as num?)?.toInt() ?? 0),
      );
  int get assetCount => _assets.length;
  /// The repository's committed size (GitHub reports kilobytes) plus assets.
  int get repoSizeBytes =>
      (((_selectedRepo?['size'] as num?)?.toInt() ?? 0) * 1024) + assetBytes;
  bool get isLoading => _isLoading;
  bool get isUploading => _isUploading;
  String? get errorMessage => _errorMessage;
  double? get progress => _progress;
  bool get progressIndeterminate => _progressIndeterminate;
  String? get progressLabel => _progressLabel;
  bool get isBusy => _progress != null || _progressIndeterminate;
  bool get autoSortUploads => _autoSortUploads;
  int get lastRateLimit => _lastRateLimit;
  bool get isConnected => _activeAccount != null;
  String get oauthClientId => AppConfig.oauthClientId;
  String get oauthBackend => AppConfig.oauthBackend;
  UpdateChannel get updateChannel => _updateChannel;
  bool get offersPrereleases => _updateChannel == UpdateChannel.beta;
  UpdateInfo? get update => _update;
  bool get checkingUpdate => _checkingUpdate;
  String? get updateError => _updateError;

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
      final savedChannel = box.get(_updateChannelKey) as String?;
      _updateChannel = savedChannel == 'beta'
          ? UpdateChannel.beta
          : savedChannel == 'stable'
              ? UpdateChannel.stable
              // A beta build should look for beta updates on first launch.
              : AppConfig.channel == 'beta'
                  ? UpdateChannel.beta
                  : UpdateChannel.stable;
      // Drop leftovers from the removed app-lock feature.
      await box.delete('pin_hash');
      await box.delete('pin_length');

      // Paint from disk before touching the network. Cold starts used to wait
      // for repos → branches → listing → assets → updates in sequence.
      final disk = await Hive.openBox('reve_disk_cache');
      _diskCache = {
        for (final key in disk.keys)
          if (disk.get(key) is Map)
            key.toString(): Map<String, dynamic>.from(disk.get(key) as Map),
      };
      final cachedRepos = box.get(_reposKey);
      if (cachedRepos is List) {
        _repositories = cachedRepos
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      final cachedId = box.get(_repoIdKey);
      if (cachedId != null) {
        _selectedRepo = _firstOrNull(_repositories, (r) => r['id'] == cachedId);
      }
      _selectedBranch = box.get(_branchKey) as String?;
      _currentPath = box.get(_pathKey) as String? ?? '';
      final cachedListing = _diskItems(_listingKey);
      if (cachedListing.isNotEmpty) {
        _files = cachedListing;
        _listingCache[_listingKey] = cachedListing;
      }

      final activeId = box.get(_activeIdKey);
      if (_accounts.isNotEmpty) {
        _activeAccount = _firstOrNull(_accounts, (a) => a.id == activeId) ?? _accounts.first;
      }
      notifyListeners();
      // Revalidate in the background; neither call blocks the first paint.
      if (_activeAccount != null) fetchRepositories();
      checkForUpdates();
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
    await box.put(_updateChannelKey, _updateChannel == UpdateChannel.beta ? 'beta' : 'stable');
    await box.put(_reposKey, _repositories);
    if (_selectedRepo != null) await box.put(_repoIdKey, _selectedRepo!['id']);
    if (_selectedBranch != null) await box.put(_branchKey, _selectedBranch);
    await box.put(_pathKey, _currentPath);
  }

  // ---------------------------------------------------------------------------
  // Updates
  // ---------------------------------------------------------------------------

  /// Runs on start-up and on every refresh; a failure is only reported when the
  /// user asked for the check explicitly.
  Future<void> checkForUpdates({bool manual = false}) async {
    // A manual check wins over one that is already running: the newest request
    // owns the result, and the older one is simply dropped when it returns.
    final request = ++_updateRequest;
    _checkingUpdate = true;
    if (manual) _updateError = null;
    notifyListeners();
    try {
      final latest = await Updater.latest(
        channel: _updateChannel,
        token: _activeAccount?.token,
      );
      if (request != _updateRequest) return;
      final installed = UpdateInfo.installed(
        channel: AppConfig.channel.isEmpty ? null : AppConfig.channel,
      );
      _update = latest != null && latest.isNewerThan(installed) ? latest : null;
      _updateError = null;
    } catch (e) {
      if (request != _updateRequest) return;
      _updateError = e.toString();
      if (!manual) _updateError = null;
    } finally {
      if (request == _updateRequest) {
        _checkingUpdate = false;
        notifyListeners();
      }
    }
  }

  Future<void> setUpdateChannel(UpdateChannel channel) async {
    if (_updateChannel == channel) return;
    _updateChannel = channel;
    _update = null;
    await _saveToBox();
    notifyListeners();
    await checkForUpdates(manual: true);
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
  // Transfer progress (one bar for uploads, downloads and preview loads)
  // ---------------------------------------------------------------------------

  void _startProgress(String label) {
    _progress = 0;
    _progressIndeterminate = false;
    _progressLabel = label;
    _progressStep = 0;
    notifyListeners();
  }

  /// Streams call this for every chunk, so only whole percent steps notify.
  void _reportProgress(double? fraction) {
    if (fraction == null) {
      if (_progressIndeterminate) return;
      _progress = null;
      _progressIndeterminate = true;
      notifyListeners();
      return;
    }
    final value = fraction.isFinite ? fraction.clamp(0.0, 1.0).toDouble() : 0.0;
    final step = (value * 100).round();
    if (!_progressIndeterminate && step == _progressStep) return;
    _progress = value;
    _progressIndeterminate = false;
    _progressStep = step;
    notifyListeners();
  }

  void _endProgress() {
    _progress = null;
    _progressIndeterminate = false;
    _progressLabel = null;
    _progressStep = -1;
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
    _listingCache.clear();
    _offlineItems = [];
    _resetAssets();
  }

  void _resetAssets() {
    _assets = {};
    _releaseAssets = [];
    _assetsKey = null;
    _assetsSha = null;
    _assetsLoaded = false;
    _assetsAt = null;
  }

  // ---------------------------------------------------------------------------
  // Repositories
  // ---------------------------------------------------------------------------

  Future<void> fetchRepositories() async {
    if (_activeAccount == null) return;
    final hadCache = _repositories.isNotEmpty;
    _isLoading = !hadCache;
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
    _listingCache.clear();
    _offlineItems = [];
    _resetAssets();
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
    _listingCache.clear();
    _offlineItems = [];
    _resetAssets();
    notifyListeners();
    await fetchContents();
  }

  // ---------------------------------------------------------------------------
  // Browsing
  // ---------------------------------------------------------------------------

  /// Folder listings are cached per branch+path: reopening a folder paints from
  /// memory and revalidates in the background, which is what makes back/forward
  /// feel instant on a phone.
  String get _listingKey => '${owner}/${repoName}/${_selectedBranch ?? ''}/$_currentPath';

  Future<void> fetchContents() async {
    if (_activeAccount == null || _selectedRepo == null) return;
    final key = _listingKey;
    final cached = _listingCache[key];

    _isLoading = cached == null;
    _errorMessage = null;
    if (cached != null) _files = cached;
    notifyListeners();

    try {
      final items = await GithubService.getContents(
        _activeAccount!.token,
        owner,
        repoName,
        _currentPath,
        branch: _selectedBranch,
      );
      // `.reve` only holds the asset index; it is not user content.
      if (_currentPath.isEmpty) items.removeWhere((f) => f.name == '.reve');
      await _loadAssets();
      final visible = items.map((f) => f.path).toSet();
      for (final entry in _assets.entries) {
        final path = entry.key;
        final parent =
            path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';
        if (parent != _currentPath || visible.contains(path)) continue;
        items.add(GithubFileItem.fromAsset(
          path,
          entry.value,
          htmlUrl: GithubService.assetReleaseUrl(owner, repoName),
        ));
      }
      // Anything the release holds but the index lost is still the user's file:
      // show it at the root under its original name so it is never invisible.
      if (_currentPath.isEmpty) {
        final indexed = _assets.values
            .map((entry) => (entry['id'] as num?)?.toInt())
            .whereType<int>()
            .toSet();
        for (final asset in _releaseAssets) {
          final id = (asset['id'] as num?)?.toInt();
          if (id == null || indexed.contains(id)) continue;
          final name = (asset['name'] as String?) ?? 'asset-$id';
          final display = GithubService.assetDisplayName(name);
          if (visible.contains(display)) continue;
          items.add(GithubFileItem.fromAsset(
            display,
            {
              'id': id,
              'name': name,
              'size': (asset['size'] as num?)?.toInt() ?? 0,
            },
            htmlUrl: GithubService.assetReleaseUrl(owner, repoName),
          ));
          visible.add(display);
        }
      }
      // Auto-sort files into images/, videos/ etc. without committing a tree
      // entry for the folder: GitHub's contents API cannot navigate a folder
      // that only exists as an asset path, so make it here instead.
      final prefix = _currentPath.isEmpty ? '' : '$_currentPath/';
      final folders = <String>{};
      for (final path in _assets.keys) {
        if (prefix.isNotEmpty && !path.startsWith(prefix)) continue;
        final rest = prefix.isEmpty ? path : path.substring(prefix.length);
        final slash = rest.indexOf('/');
        if (slash <= 0) continue;
        final name = rest.substring(0, slash);
        final dir = prefix.isEmpty ? name : '$_currentPath/$name';
        if (visible.contains(dir)) continue;
        folders.add(dir);
      }
      for (final dir in folders) {
        items.add(GithubFileItem(
          name: dir.split('/').last,
          path: dir,
          sha: '',
          size: 0,
          type: 'dir',
        ));
        visible.add(dir);
      }
      items.sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      final changed = cached == null ||
          cached.length != items.length ||
          !List.generate(items.length, (i) => cached[i].sha == items[i].sha).every((same) => same);
      _listingCache[key] = items;
      _saveDiskCache(key, items);
      if (changed) _files = items;
      _offlineItems = [];
      _offlineAt = null;
    } catch (e) {
      _errorMessage = e.toString();
      // Live data is gone, but show the last saved listing rather than an
      // empty folder.
      _offlineItems = _diskItems(key);
      _offlineAt = DateTime.now();
      notifyListeners();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// `_listingCache` partner: the disk cache that survives process restarts.
  Future<void> _saveDiskCache(String key, List<GithubFileItem> items) async {
    try {
      final box = await Hive.openBox('reve_disk_cache');
      _diskCache[key] = {
        'at': DateTime.now().toIso8601String(),
        'items': items.map((i) => i.toJson()).toList(),
      };
      await box.put(key, _diskCache[key]!);
    } catch (_) {
      // Caching is a nicety; never fail a refresh over it.
    }
  }

  List<GithubFileItem> _diskItems(String key) {
    final entry = _diskCache[key];
    if (entry == null) return const [];
    _offlineAt = _tryParseDate(entry['at']);
    final items = entry['items'];
    if (items is! List) return const [];
    try {
      return [
        for (final e in items) GithubFileItem.fromJson(Map.from(e as Map))
      ];
    } catch (_) {
      return const [];
    }
  }

  static DateTime? _tryParseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }

  /// A commit can change any ancestor listing, so drop them all. They refill
  /// on the next visit and the fetch that follows a mutation repopulates the
  /// folder you are looking at.
  void invalidateListings() => _listingCache.clear();

  /// Loads the asset index once per repo+branch; folder listings then merge
  /// their slice of it without an extra request each time.
  String get _assetKey => '$owner/$repoName/${_selectedBranch ?? ''}';

  Future<void> _loadAssets({bool force = false}) async {
    final fresh = _assetsAt != null &&
        DateTime.now().difference(_assetsAt!) < const Duration(seconds: 15);
    if (!force && _assetsLoaded && _assetsKey == _assetKey && fresh) return;
    if (_activeAccount == null || _selectedRepo == null) return;
    AssetManifest? manifest;
    var releaseAssets = <Map<String, dynamic>>[];
    // The index and the release are independent: either one alone is enough to
    // show a large file, so a failure in one must not blank the other.
    await Future.wait([
      () async {
        try {
          manifest = await GithubService.readAssetManifest(
            token: _activeAccount!.token,
            owner: owner,
            repo: repoName,
            branch: _selectedBranch,
          );
        } catch (_) {
          // The index is an enhancement: a broken or huge one must not hide
          // the repository's real files.
        }
      }(),
      () async {
        try {
          releaseAssets = await GithubService.listReleaseAssets(
            token: _activeAccount!.token,
            owner: owner,
            repo: repoName,
          );
        } catch (_) {
          // No large-file release yet, or no permission to read it.
        }
      }(),
    ]);
    _assets = manifest?.files ?? {};
    _assetsSha = manifest?.sha;
    _releaseAssets = releaseAssets;
    _assetsKey = _assetKey;
    _assetsLoaded = true;
    _assetsAt = DateTime.now();
  }

  /// Read-modify-write of the index with one retry when another device wins.
  Future<void> _mutateManifest(
    void Function(Map<String, Map<String, dynamic>> files) change,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final manifest = await GithubService.readAssetManifest(
        token: _activeAccount!.token,
        owner: owner,
        repo: repoName,
        branch: _selectedBranch,
      );
      change(manifest.files);
      try {
        _assetsSha = await GithubService.putAssetManifest(
          token: _activeAccount!.token,
          owner: owner,
          repo: repoName,
          files: manifest.files,
          sha: manifest.sha,
          branch: _selectedBranch,
        );
        _assets = manifest.files;
        _assetsKey = _assetKey;
        _assetsLoaded = true;
        _assetsAt = DateTime.now();
        return;
      } on ManifestConflict {
        if (attempt == 1) rethrow;
      }
    }
  }

  Future<void> navigateToFolder(String path) async {
    _currentPath = path;
    _saveToBox();
    await fetchContents();
  }

  Future<void> navigateUp() async {
    if (_currentPath.isEmpty) return;
    final parts = _currentPath.split('/');
    parts.removeLast();
    _currentPath = parts.join('/');
    _saveToBox();
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
    if (bytes.lengthInBytes > maxUploadBytes) {
      return uploadLargeFile(
        fileName: fileName,
        length: bytes.lengthInBytes,
        bytes: bytes,
        message: message,
      );
    }
    return _uploadSmall(fileName: fileName, bytes: bytes, message: message);
  }

  Future<UploadResult> _uploadSmall({
    required String fileName,
    required Uint8List bytes,
    String? message,
  }) async {
    if (_activeAccount == null || _selectedRepo == null) {
      return const UploadResult(false, 'Connect an account and pick a repository first.');
    }

    _isUploading = true;
    _startProgress('Uploading $fileName…');
    final path = _targetPathFor(fileName);
    final report = _progressReporter(fileName);

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
          onProgress: report,
        );
      } on Exception {
        // The path may already exist: fetch its blob sha and overwrite. Look in
        // the file's own folder — auto-sort puts uploads under images/ etc., so
        // the folder on screen is not where the file lands.
        final parent =
            path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';
        final existing = await GithubService.getContents(
          _activeAccount!.token,
          owner,
          repoName,
          parent,
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
          onProgress: report,
        );
      }
      await _dropAssetAt(path);
      invalidateListings();
      await fetchContents();
      return UploadResult(true, '$fileName uploaded to $path', path: path);
    } catch (e) {
      _errorMessage = e.toString();
      return UploadResult(false, e.toString());
    } finally {
      _isUploading = false;
      _endProgress();
    }
  }

  /// A committed file replaced an older asset with the same name: drop the
  /// asset so the index cannot shadow it or leak storage.
  Future<void> _dropAssetAt(String path) async {
    if (!_assets.containsKey(path)) return;
    try {
      Map<String, dynamic>? removed;
      await _mutateManifest((files) => removed = files.remove(path));
      final id = (removed?['id'] as num?)?.toInt();
      if (id == null) return;
      await GithubService.deleteAsset(
        token: _activeAccount!.token,
        owner: owner,
        repo: repoName,
        assetId: id,
      );
    } catch (_) {
      // The committed file is live either way; a stale asset is only space.
    }
  }

  /// The reverse: a large upload replaces a small committed file of the same
  /// name, which would otherwise stay visible and win the listing.
  Future<void> _dropCommittedFileAt(String path) async {
    final parent = path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';
    try {
      final existing = await GithubService.getContents(
        _activeAccount!.token,
        owner,
        repoName,
        parent,
        branch: _selectedBranch,
      );
      final match = _firstOrNull(existing, (f) => f.path == path);
      if (match == null) return;
      await GithubService.deleteFile(
        token: _activeAccount!.token,
        owner: owner,
        repo: repoName,
        path: path,
        sha: match.sha,
        message: 'Replace $path with a large file via reve',
        branch: _selectedBranch,
      );
    } catch (_) {
      // Best effort: the asset is uploaded and indexed either way.
    }
  }

  /// Anything over the Contents ceiling goes to the asset release, which takes
  /// files up to 2 GB and replays them with byte ranges — so video seeks.
  /// The path an upload lands on, so callers can spot collisions without
  /// asking the Contents API first.
  String targetPathFor(String fileName) => _targetPathFor(fileName);

  /// Existing committed paths in the branch — the conflict check for the
  /// batched upload path. Empty when offline or the tree cannot be read.
  Future<Set<String>> existingPaths() async {
    if (_activeAccount == null || _selectedRepo == null) return {};
    try {
      return await GithubService.committedPaths(
        token: _activeAccount!.token,
        owner: owner,
        repo: repoName,
        branch: _selectedBranch,
      );
    } catch (_) {
      return {};
    }
  }

  /// Uploads many small files in one git commit, no Contents API involved.
  Future<CommitBatchOutcome> commitBatch(List<BatchedFile> files) async {
    if (_activeAccount == null || _selectedRepo == null) {
      return CommitBatchOutcome(
        failed: files.map((f) => f.name).toList(),
        error: 'Connect an account and pick a repository first.',
      );
    }
    _isUploading = true;
    _startProgress('Uploading ${files.length} files…');
    try {
      final total = files.fold(0, (sum, f) => sum + f.bytes.lengthInBytes);
      final paths = files.map((f) => _targetPathFor(f.name)).toList();
      final treeEntries = <String, String>{};
      var sent = 0;
      for (var i = 0; i < files.length; i++) {
        treeEntries[paths[i]] = await GithubService.createBlob(
          token: _activeAccount!.token,
          owner: owner,
          repo: repoName,
          bytes: files[i].bytes,
        );
        sent += files[i].bytes.lengthInBytes;
        _reportProgress(total == 0 ? null : sent / total);
      }
      _progress = null;
      await GithubService.commitTree(
        token: _activeAccount!.token,
        owner: owner,
        repo: repoName,
        entries: treeEntries,
        message: 'Upload ${files.length} files via reve',
        branch: _selectedBranch,
      );
      invalidateListings();
      await fetchContents();
      return CommitBatchOutcome(uploaded: paths);
    } catch (e) {
      _errorMessage = e.toString();
      return CommitBatchOutcome(
        failed: files.map((f) => f.name).toList(),
        error: e.toString(),
      );
    } finally {
      _isUploading = false;
      _endProgress();
    }
  }

  DeletedCommit? _lastDeleted;

  DeletedCommit? get lastDeleted => _lastDeleted;
  /// Re-adds a just-deleted committed file as one tree commit, so history
  /// (where its blob usually survives) puts it back.
  Future<bool> undoDelete() async {
    if (_activeAccount == null || _selectedRepo == null) return false;
    final deleted = _lastDeleted;
    if (deleted == null) return false;
    try {
      await GithubService.commitTree(
        token: _activeAccount!.token,
        owner: owner,
        repo: repoName,
        entries: {deleted.path: deleted.blobSha},
        message: deleted.message,
        branch: _selectedBranch,
      );
      _lastDeleted = null;
      invalidateListings();
      await fetchContents();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    }
  }

  /// Anything over the Contents ceiling goes to the asset release, which takes
  /// files up to 2 GB and replays them with byte ranges — so video seeks.
  Future<UploadResult> uploadLargeFile({
    required String fileName,
    required int length,
    Uint8List? bytes,
    Stream<List<int>>? source,
    String? message,
  }) async {
    if (_activeAccount == null || _selectedRepo == null) {
      return const UploadResult(false, 'Connect an account and pick a repository first.');
    }

    _isUploading = true;
    _startProgress('Uploading $fileName…');
    final path = _targetPathFor(fileName);
    final report = _progressReporter(fileName);
    // GitHub needs a Content-Length. A buffered pick knows it from the byte
    // array; a streamed pick must have been measured before it got here.
    final size = bytes?.lengthInBytes ?? length;
    if (size <= 0) {
      _isUploading = false;
      _endProgress();
      return const UploadResult(
        false,
        'Could not determine this file\'s size, so it was not uploaded.',
      );
    }

    try {
      final releaseId = await GithubService.ensureAssetRelease(
        token: _activeAccount!.token,
        owner: owner,
        repo: repoName,
        branch: _selectedBranch,
      );
      final assetName = GithubService.assetFileName(path);
      final uploaded = await GithubService.uploadAsset(
        token: _activeAccount!.token,
        owner: owner,
        repo: repoName,
        releaseId: releaseId,
        name: assetName,
        mime: GithubService.mimeFor(fileName),
        length: size,
        bytes: bytes,
        source: source,
        onProgress: report,
      );
      final id = (uploaded['id'] as num).toInt();

      Map<String, dynamic>? previous;
      try {
        await _mutateManifest((files) {
          previous = files[path];
          files[path] = {
            'id': id,
            'name': assetName,
            'size': size,
            'mime': GithubService.mimeFor(fileName),
            'at': DateTime.now().toUtc().toIso8601String(),
          };
        });
      } catch (_) {
        // The asset is live either way, and the listing falls back to the
        // release's own asset list — losing the upload over a failed index
        // write would waste the bandwidth the user just spent.
      }

      final oldId = (previous?['id'] as num?)?.toInt();
      if (oldId != null && oldId != id) {
        try {
          await GithubService.deleteAsset(
            token: _activeAccount!.token,
            owner: owner,
            repo: repoName,
            assetId: oldId,
          );
        } catch (_) {
          // The new asset is live; a leftover old one is only wasted space.
        }
      }

      await _dropCommittedFileAt(path);
      invalidateListings();
      await fetchContents();
      return UploadResult(true, '$fileName uploaded to $path', path: path);
    } catch (e) {
      _errorMessage = e.toString();
      return UploadResult(false, e.toString());
    } finally {
      _isUploading = false;
      _endProgress();
    }
  }

  void Function(double) _progressReporter(String fileName) {
    return (fraction) {
      // Stop short of 100% until the upload returns: waiting for GitHub to
      // commit the file used to sit at "100%" and look hung.
      final shown = fraction < 0.995 ? fraction : 0.99;
      _progressLabel = 'Uploading $fileName · ${(shown * 100).round()}%';
      _reportProgress(shown);
    };
  }

  Future<bool> deleteItem(GithubFileItem item, {String? message}) async {
    if (_activeAccount == null || _selectedRepo == null) return false;
    _isLoading = true;
    notifyListeners();
    try {
      final msg = message ?? 'Delete ${item.path} via reve';
      if (item.isAsset) {
        Map<String, dynamic>? removed;
        await _mutateManifest((files) => removed = files.remove(item.path));
        final id = (removed?['id'] as num?)?.toInt();
        if (id != null) {
          try {
            await GithubService.deleteAsset(
              token: _activeAccount!.token,
              owner: owner,
              repo: repoName,
              assetId: id,
            );
          } catch (_) {
            // The index no longer points at it, so it is unreachable anyway.
          }
        }
      } else if (item.isDirectory) {
        await GithubService.deleteDirectory(
          token: _activeAccount!.token,
          owner: owner,
          repo: repoName,
          path: item.path,
          message: msg,
          branch: _selectedBranch,
        );
        await _removeAssetsUnder(item.path);
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
      // Restorable only while the blob may still exist in the history of a
      // committed file — assets are gone, folders are not inlined back.
      if (!item.isAsset && !item.isDirectory && item.size <= maxUndoBytes) {
        _lastDeleted = DeletedCommit(
          path: item.path,
          blobSha: item.sha,
          message: 'Restore ${item.path} via reve',
        );
      }
      invalidateListings();
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

  /// Removes every asset-backed file below [folder] after the folder itself
  /// was deleted. GitHub's Contents API cannot see them, so the index is the
  /// only place that knows they exist.
  Future<void> _removeAssetsUnder(String folder) async {
    final prefix = folder.endsWith('/') ? folder : '$folder/';
    if (!_assets.keys.any((path) => path.startsWith(prefix))) return;
    final doomed = <int>[];
    await _mutateManifest((files) {
      for (final path in files.keys.toList()) {
        if (!path.startsWith(prefix)) continue;
        final id = (files[path]?['id'] as num?)?.toInt();
        if (id != null) doomed.add(id);
        files.remove(path);
      }
    });
    for (final id in doomed) {
      try {
        await GithubService.deleteAsset(
          token: _activeAccount!.token,
          owner: owner,
          repo: repoName,
          assetId: id,
        );
      } catch (_) {
        // Nothing points at it anymore.
      }
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
      invalidateListings();
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

  /// Headers for streamed previews: raw.githubusercontent.com accepts the same
  /// bearer token as the API, so private repositories play too.
  Map<String, String> get authHeaders => _activeAccount == null
      ? const {}
      : {'Authorization': 'Bearer ${_activeAccount!.token}'};

  /// Public releases download straight from GitHub. Private repositories need
  /// a signed URL, which [streamUrlFor] resolves.
  String? downloadUrlFor(GithubFileItem item) {
    if (item.isAsset) {
      if (item.assetName != null) {
        return GithubService.publicAssetUrl(owner, repoName, item.assetName!);
      }
      return item.htmlUrl ?? GithubService.assetReleaseUrl(owner, repoName);
    }
    if (_selectedRepo == null) return item.downloadUrl;
    final branch = _selectedBranch ??
        (_selectedRepo!['default_branch'] as String?) ??
        '';
    if (branch.isEmpty) return item.downloadUrl;
    return GithubService.rawUrl(owner, repoName, branch, item.path);
  }

  /// URL a media player can stream. Asset files get a short-lived signed URL
  /// with no headers attached — players redirect better when they can keep
  /// auth out of the request.
  Future<String?> streamUrlFor(GithubFileItem item) async {
    if (!item.isAsset) return downloadUrlFor(item);
    if (_activeAccount == null || _selectedRepo == null) return null;
    // Public assets keep their filename in the URL, which lets the platform
    // player detect the container and pick the right codec.
    if (_selectedRepo?['private'] == false && item.assetName != null) {
      return GithubService.publicAssetUrl(owner, repoName, item.assetName!);
    }
    return GithubService.signedAssetUrl(
      token: _activeAccount!.token,
      owner: owner,
      repo: repoName,
      assetId: item.assetId!,
    );
  }

  Map<String, String> headersFor(GithubFileItem item) =>
      item.isAsset ? const {} : authHeaders;

  /// Bytes of [item] with the shared progress bar attached. Used by both the
  /// preview (render what was read) and Download (save what was read).
  Future<Uint8List> readBytes(
    GithubFileItem item, {
    String? label,
    bool report = true,
  }) async {
    if (_activeAccount == null || _selectedRepo == null) {
      throw Exception('Connect an account and pick a repository first.');
    }
    final verb = label ?? 'Loading ${item.name}';
    if (report) _startProgress('$verb…');
    try {
      if (item.isAsset) {
        final url = await GithubService.signedAssetUrl(
          token: _activeAccount!.token,
          owner: owner,
          repo: repoName,
          assetId: item.assetId!,
        );
        return await GithubService.fetchAssetBytes(
          url: url,
          onProgress: (fraction, loaded) {
            if (!report) return;
            _progressLabel = fraction == null
                ? '$verb · ${formatBytes(loaded)}'
                : '$verb · ${(fraction * 100).round()}%';
            _reportProgress(fraction);
          },
        );
      }
      return await GithubService.fetchBytes(
        token: _activeAccount!.token,
        owner: owner,
        repo: repoName,
        path: item.path,
        branch: _selectedBranch,
        sha: item.sha,
        onProgress: (fraction, loaded) {
          if (!report) return;
          _progressLabel = fraction == null
              ? '$verb · ${formatBytes(loaded)}'
              : '$verb · ${(fraction * 100).round()}%';
          _reportProgress(fraction);
        },
      );
    } finally {
      if (report) _endProgress();
    }
  }
}

class UploadResult {
  final bool ok;
  final String message;
  final String? path;

  const UploadResult(this.ok, this.message, {this.path});
}

/// One file picked for the batched upload path.
class BatchedFile {
  final String name;
  final Uint8List bytes;

  const BatchedFile({required this.name, required this.bytes});
}

/// The outcome of one [ReveProvider.commitBatch]: [uploaded] are the
/// committed paths, [failed] the names that did not land.
class CommitBatchOutcome {
  final List<String> uploaded;
  final List<String> failed;
  final String? error;

  const CommitBatchOutcome({
    this.uploaded = const [],
    this.failed = const [],
    this.error,
  });
}

/// What the user can undo: the path and blob sha of one file deleted through
/// the Contents API, plus the message GitHub reports in the commit history.
class DeletedCommit {
  final String path;
  final String blobSha;
  final String message;

  const DeletedCommit({
    required this.path,
    required this.blobSha,
    required this.message,
  });
}
