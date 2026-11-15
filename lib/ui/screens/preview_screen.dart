import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../models/file_item.dart';
import '../../providers/reve_provider.dart';

/// Everything gets a viewer. Bytes come through the API first (so private
/// repositories work), and formats Flutter cannot draw fall back to a card
/// that saves the file — downloading is the preview of last resort.
class PreviewScreen extends StatefulWidget {
  final ReveProvider provider;
  final List<GithubFileItem> items;
  final int initialIndex;

  const PreviewScreen({
    super.key,
    required this.provider,
    required this.items,
    required this.initialIndex,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  static const int _maxPreviewBytes = 40 * 1024 * 1024;

  late final PageController _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  bool _info = false;
  final Map<String, Future<Uint8List>> _loads = {};

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  GithubFileItem get _item => widget.items[_index];

  Future<Uint8List> _bytesOf(GithubFileItem item) =>
      _loads.putIfAbsent(item.path, () => widget.provider.readBytes(item));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.provider,
      builder: (context, _) {
        final item = _item;
        final cs = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 8,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                Text(
                  '${_index + 1} of ${widget.items.length} · ${formatBytes(item.size)}',
                  style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Download',
                icon: const Icon(Icons.download_outlined),
                onPressed: () => _save(item),
              ),
              IconButton(
                tooltip: 'Copy path',
                icon: const Icon(Icons.link_outlined),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: item.path));
                  _toast('Path copied');
                },
              ),
              IconButton(
                tooltip: 'Open on GitHub',
                icon: const Icon(Icons.open_in_new),
                onPressed: () => _open(item),
              ),
              IconButton(
                tooltip: 'Details',
                isSelected: _info,
                icon: const Icon(Icons.info_outline),
                onPressed: () => setState(() => _info = !_info),
              ),
            ],
            bottom: widget.provider.isBusy
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(3),
                    child: LinearProgressIndicator(
                      value: widget.provider.progress,
                      minHeight: 3,
                      backgroundColor: cs.surfaceContainerHighest,
                    ),
                  )
                : null,
          ),
          body: Column(
            children: [
              if (_info) _details(context, item),
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: widget.items.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => _page(widget.items[i]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Types
  // ---------------------------------------------------------------------------

  static String kindOf(String name) {
    final dot = name.lastIndexOf('.');
    final ext = dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
    const images = {
      'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico', 'avif', 'heic', 'heif',
      'tif', 'tiff',
    };
    // Everything the platform decoder can stream: ExoPlayer handles mp4/m4v/mov,
    // webm, mkv, 3gp and ts video, plus mp3, aac/m4a, flac, ogg/opus, wav, amr.
    const videos = {'mp4', 'm4v', 'mov', 'webm', 'mkv', 'ogv', '3gp', 'ts', 'm2ts', 'mpd', 'avi', 'wmv', 'flv'};
    const audios = {'mp3', 'wav', 'ogg', 'oga', 'opus', 'flac', 'm4a', 'aac', 'amr', 'wma', 'mid', 'm4b'};
    const markdown = {'md', 'markdown', 'mdx'};
    const json = {'json', 'jsonc', 'geojson'};
    const tables = {'csv', 'tsv'};
    const fonts = {'ttf', 'otf', 'woff', 'woff2'};
    const text = {
      'txt', 'log', 'yml', 'yaml', 'toml', 'ini', 'conf', 'env', 'xml', 'html', 'htm',
      'css', 'scss', 'less', 'js', 'mjs', 'cjs', 'ts', 'tsx', 'jsx', 'dart', 'py', 'rb',
      'go', 'rs', 'java', 'kt', 'kts', 'c', 'h', 'cc', 'cpp', 'hpp', 'cs', 'php', 'sh',
      'bash', 'zsh', 'ps1', 'sql', 'srt', 'vtt', 'ass', 'ssa', 'lrc', 'diff', 'patch',
      'gitignore', 'editorconfig', 'properties', 'gradle', 'lock', 'svg',
    };
    if (images.contains(ext)) return 'image';
    if (videos.contains(ext)) return 'video';
    if (audios.contains(ext)) return 'audio';
    if (markdown.contains(ext)) return 'markdown';
    if (json.contains(ext)) return 'json';
    if (tables.contains(ext)) return 'table';
    if (fonts.contains(ext)) return 'font';
    if (text.contains(ext)) return 'text';
    return 'binary';
  }

  static IconData iconFor(String kind) => switch (kind) {
        'image' => Icons.image_outlined,
        'video' => Icons.movie_outlined,
        'audio' => Icons.audiotrack,
        'markdown' => Icons.article_outlined,
        'json' => Icons.data_object,
        'table' => Icons.table_chart_outlined,
        'font' => Icons.font_download_outlined,
        'text' => Icons.code,
        _ => Icons.insert_drive_file_outlined,
      };

  // ---------------------------------------------------------------------------
  // Pages
  // ---------------------------------------------------------------------------

  Widget _page(GithubFileItem item) {
    final kind = kindOf(item.name);
    // Audio and video are streamed, never buffered: a 300 MB film would blow
    // through memory long before it played.
    if (kind == 'video' || kind == 'audio') {
      return _MediaPreview(
        item: item,
        audioOnly: kind == 'audio',
        url: widget.provider.downloadUrlFor(item),
        headers: widget.provider.authHeaders,
        onSave: () => _save(item),
      );
    }
    if (item.size > _maxPreviewBytes) {
      return _fileCard(
        item,
        icon: iconFor(kind),
        title: 'Too large to open here',
        body: '${formatBytes(item.size)} — save it and open it on your device.',
      );
    }

    return FutureBuilder<Uint8List>(
      future: _bytesOf(item),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        if (snapshot.hasError || snapshot.data == null) {
          return _fileCard(
            item,
            icon: Icons.cloud_off_outlined,
            title: 'Could not read this file',
            body: '${snapshot.error ?? 'Empty response'}',
          );
        }
        return _render(item, kind, snapshot.data!);
      },
    );
  }

  Widget _render(GithubFileItem item, String kind, Uint8List bytes) {
    if (kind == 'image') {
      return InteractiveViewer(
        maxScale: 6,
        child: Center(
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stack) => _fileCard(
              item,
              icon: Icons.broken_image_outlined,
              title: 'No decoder for this image',
              body: '${formatBytes(item.size)} — Flutter cannot decode this '
                  'format here. Save it and open it with your gallery.',
            ),
          ),
        ),
      );
    }
    if (kind == 'font') return _font(item, bytes);

    final text = _decode(bytes);
    if (text == null) return _binary(item, bytes);

    switch (kind) {
      case 'markdown':
        return _markdown(text);
      case 'json':
        return _code(_prettyJson(text), wrap: true);
      case 'table':
        return _table(text, item.name);
      case 'text':
        return _code(text, wrap: true);
      default:
        return _binary(item, bytes);
    }
  }

  Widget _code(String text, {bool wrap = false}) {
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          child: SelectableText(
            text.length > 400000 ? '${text.substring(0, 400000)}\n\n… truncated' : text,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.55),
          ),
        ),
      ),
    );
  }

  Widget _markdown(String source) {
    final blocks = <Widget>[];
    final paragraph = <String>[];
    final code = <String>[];
    var fenced = false;

    void flush() {
      if (paragraph.isEmpty) return;
      blocks.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SelectableText(
          paragraph.join(' '),
          style: const TextStyle(fontSize: 14, height: 1.65),
        ),
      ));
      paragraph.clear();
    }

    void flushCode() {
      if (code.isEmpty) return;
      blocks.add(Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0x11000000),
          borderRadius: BorderRadius.circular(10),
        ),
        child: SelectableText(
          code.join('\n'),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.5),
        ),
      ));
      code.clear();
    }

    for (final line in source.split('\n')) {
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('```')) {
        if (fenced) {
          flushCode();
        } else {
          flush();
        }
        fenced = !fenced;
        continue;
      }
      if (fenced) {
        code.add(line);
        continue;
      }
      if (trimmed.isEmpty) {
        flush();
        continue;
      }
      final heading = RegExp(r'^(#{1,4})\s+(.*)$').firstMatch(trimmed);
      if (heading != null) {
        flush();
        final level = heading.group(1)!.length;
        blocks.add(Padding(
          padding: EdgeInsets.only(top: level == 1 ? 4 : 10, bottom: 10),
          child: SelectableText(
            heading.group(2)!,
            style: TextStyle(
              fontSize: switch (level) { 1 => 24.0, 2 => 20.0, 3 => 17.0, _ => 15.0 },
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ));
        continue;
      }
      final bullet = RegExp(r'^[-*+]\s+(.*)$').firstMatch(trimmed);
      if (bullet != null) {
        flush();
        blocks.add(Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('•  ', style: TextStyle(fontSize: 14, height: 1.65)),
              Expanded(
                child: SelectableText(bullet.group(1)!,
                    style: const TextStyle(fontSize: 14, height: 1.65)),
              ),
            ],
          ),
        ));
        continue;
      }
      paragraph.add(trimmed);
    }
    flushCode();
    flush();

    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: blocks),
      ),
    );
  }

  Widget _table(String text, String name) {
    final rows = _parseRows(text, name.endsWith('.tsv') ? '\t' : ',');
    if (rows.isEmpty) {
      return const Center(child: Text('Empty table'));
    }
    final columns = rows.first;
    final body = rows.skip(1).take(200).toList();
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 42,
            dataRowMinHeight: 36,
            dataRowMaxHeight: 44,
            columns: [
              for (var i = 0; i < columns.length; i++)
                DataColumn(label: Text(columns[i], style: const TextStyle(fontSize: 12))),
            ],
            rows: [
              for (final row in body)
                DataRow(
                  cells: [
                    for (var i = 0; i < columns.length; i++)
                      DataCell(Text(i < row.length ? row[i] : '',
                          style: const TextStyle(fontSize: 12))),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _font(GithubFileItem item, Uint8List bytes) {
    return FutureBuilder<String>(
      future: _registerFont(item, bytes),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        if (snapshot.hasError || snapshot.data == null) {
          return _binary(item, bytes);
        }
        final family = snapshot.data!;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Aa Bb Cc Dd Ee Ff Gg',
                  style: TextStyle(fontFamily: family, fontSize: 34)),
              const SizedBox(height: 16),
              Text(
                'The quick brown fox jumps over the lazy dog 0123456789',
                style: TextStyle(fontFamily: family, fontSize: 18, height: 1.5),
              ),
              const SizedBox(height: 24),
              Text('${item.name} · ${formatBytes(item.size)}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        );
      },
    );
  }

  /// Registers the font bytes with the engine so a sample can be drawn.
  Future<String> _registerFont(GithubFileItem item, Uint8List bytes) async {
    final family = 'reve-preview-${item.path.hashCode}';
    final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    return family;
  }

  Widget _binary(GithubFileItem item, Uint8List bytes) {
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No inline viewer for this format — ${formatBytes(bytes.length)}. '
              'Save it to open it with an app that knows it.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            SelectableText(
              _hexDump(bytes.length > 4096 ? bytes.sublist(0, 4096) : bytes),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fileCard(
    GithubFileItem item, {
    required IconData icon,
    required String title,
    required String body,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(icon, size: 34, color: cs.primary),
            ),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(body, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, height: 1.6, color: cs.onSurfaceVariant)),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  onPressed: () => _save(item),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Save file'),
                ),
                const SizedBox(width: 10),
                TextButton.icon(
                  onPressed: () => _open(item),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('GitHub'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _save(GithubFileItem item) async {
    try {
      final bytes = await _bytesOf(item);
      if (!mounted) return;
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save ${item.name}',
        fileName: item.name,
        bytes: bytes,
      );
      _toast(saved == null ? 'Save cancelled' : 'Saved ${item.name}');
    } catch (error) {
      _toast('Could not save ${item.name}: $error');
    }
  }

  Future<void> _open(GithubFileItem item) async {
    final url = item.htmlUrl;
    if (url == null) {
      _toast('No GitHub URL for this file');
      return;
    }
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String? _decode(Uint8List bytes) {
    for (var i = 0; i < (bytes.length < 4096 ? bytes.length : 4096); i++) {
      if (bytes[i] == 0) return null;
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String _prettyJson(String text) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
    } catch (_) {
      return text;
    }
  }

  static List<List<String>> _parseRows(String text, String separator) {
    final rows = <List<String>>[];
    var cell = '';
    var row = <String>[];
    var quoted = false;
    for (var i = 0; i < text.length && rows.length < 500; i++) {
      final char = text[i];
      if (quoted) {
        if (char == '"' && i + 1 < text.length && text[i + 1] == '"') {
          cell += '"';
          i++;
        } else if (char == '"') {
          quoted = false;
        } else {
          cell += char;
        }
      } else if (char == '"') {
        quoted = true;
      } else if (char == separator) {
        row.add(cell);
        cell = '';
      } else if (char == '\n') {
        row.add(cell);
        rows.add(row);
        row = <String>[];
        cell = '';
      } else if (char != '\r') {
        cell += char;
      }
    }
    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell);
      rows.add(row);
    }
    return rows;
  }

  static String _hexDump(Uint8List bytes) {
    final out = StringBuffer();
    for (var offset = 0; offset < bytes.length; offset += 16) {
      final end = offset + 16 < bytes.length ? offset + 16 : bytes.length;
      final row = bytes.sublist(offset, end);
      final hex = row.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ').padRight(47);
      final ascii = row.map((b) => b >= 32 && b < 127 ? String.fromCharCode(b) : '.').join();
      out.writeln('${offset.toRadixString(16).padLeft(8, '0')}  $hex  $ascii');
    }
    return out.toString();
  }

  Widget _details(BuildContext context, GithubFileItem item) {
    final cs = Theme.of(context).colorScheme;
    final rows = {
      'Path': item.path,
      'Size': formatBytes(item.size),
      'SHA': item.sha.isEmpty ? '—' : item.sha.substring(0, item.sha.length >= 7 ? 7 : item.sha.length),
      'Type': item.type,
    };
    return Container(
      width: double.infinity,
      color: cs.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows.entries
            .map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                          width: 56,
                          child: Text(e.key,
                              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant))),
                      Expanded(
                          child: Text(e.value,
                              style: const TextStyle(fontSize: 11.5),
                              overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Streams the file through the platform player, so audio and video open
/// inside reve instead of landing in a hex dump. The URL is the raw GitHub
/// blob with the account token attached, which also covers private repos.
class _MediaPreview extends StatefulWidget {
  const _MediaPreview({
    required this.item,
    required this.audioOnly,
    required this.url,
    required this.headers,
    required this.onSave,
  });

  final GithubFileItem item;
  final bool audioOnly;
  final String? url;
  final Map<String, String> headers;
  final Future<void> Function() onSave;

  @override
  State<_MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends State<_MediaPreview> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final url = widget.url;
    if (url == null || url.isEmpty) {
      setState(() => _error = 'No download URL for this file.');
      return;
    }
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: widget.headers,
    );
    try {
      await controller.initialize();
      try {
        await controller.play();
      } catch (_) {
        // Autoplay policies can refuse to start; the controls still work.
      }
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (error) {
      await controller.dispose();
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final controller = _controller;
    if (_error != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.audioOnly ? Icons.music_off : Icons.videocam_off_outlined,
                  size: 44, color: cs.onSurfaceVariant),
              const SizedBox(height: 14),
              const Text('This format does not play here',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(
                  '${widget.item.name} — ${widget.item.size > 0 ? formatBytes(widget.item.size) : 'unknown size'}. '
                  'The player rejected it, so save it and open it with an app that '
                  'supports this codec.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, height: 1.6, color: cs.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _error!,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => widget.onSave(),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Save file'),
              ),
            ],
          ),
        ),
      );
    }
    if (controller == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (widget.audioOnly) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 132,
                height: 132,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [cs.primaryContainer, cs.secondaryContainer],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Icon(Icons.graphic_eq, size: 56, color: cs.onPrimaryContainer),
              ),
              const SizedBox(height: 18),
              Text(
                widget.item.name,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                formatBytes(widget.item.size),
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              SizedBox(width: 340, child: _controls(controller)),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ColoredBox(
            color: Colors.black,
            child: Center(
              child: AspectRatio(
                // Audio-only mp4 files report 0, which AspectRatio rejects.
                aspectRatio: controller.value.aspectRatio > 0
                    ? controller.value.aspectRatio
                    : 16 / 9,
                child: VideoPlayer(controller),
              ),
            ),
          ),
        ),
        SafeArea(top: false, child: _controls(controller)),
      ],
    );
  }

  Widget _controls(VideoPlayerController controller) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final total = value.duration.inMilliseconds;
        final position = value.position.inMilliseconds > total ? total : value.position.inMilliseconds;
        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                value: total == 0 ? 0 : (position / total).clamp(0.0, 1.0),
                onChanged: total == 0
                    ? null
                    : (fraction) => controller
                        .seekTo(Duration(milliseconds: (fraction * total).round())),
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: value.isPlaying ? 'Pause' : 'Play',
                    icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                    onPressed: () => value.isPlaying ? controller.pause() : controller.play(),
                  ),
                  Text(
                    '${_clock(value.position)} / ${_clock(value.duration)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const Spacer(),
                  if (value.isBuffering)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  IconButton(
                    tooltip: value.volume == 0 ? 'Unmute' : 'Mute',
                    icon: Icon(value.volume == 0 ? Icons.volume_off : Icons.volume_up),
                    onPressed: () => controller.setVolume(value.volume == 0 ? 1 : 0),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  static String _clock(Duration value) {
    final seconds = value.inSeconds % 60;
    return '${value.inMinutes}:${seconds.toString().padLeft(2, '0')}';
  }
}
