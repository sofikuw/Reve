import 'package:flutter/material.dart';

import '../models/file_item.dart';
import 'theme.dart';

/// File families, matching the web client's tile colours.
String fileKind(String name, {bool directory = false}) {
  if (directory) return 'dir';
  final dot = name.lastIndexOf('.');
  final ext = dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
  if (const {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'avif', 'heic', 'svg'}
      .contains(ext)) {
    return 'image';
  }
  if (const {
    'mp4', 'webm', 'mkv', 'avi', 'mov', 'ogv', 'm4v', '3gp', 'ts', 'm2ts',
    'mpd', 'wmv', 'flv',
  }.contains(ext)) {
    return 'video';
  }
  if (const {
    'mp3', 'wav', 'ogg', 'oga', 'flac', 'm4a', 'm4b', 'aac', 'opus', 'amr',
    'wma', 'mid',
  }.contains(ext)) {
    return 'audio';
  }
  if (const {'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz'}.contains(ext)) {
    return 'archive';
  }
  if (const {
    'pdf', 'doc', 'docx', 'txt', 'md', 'markdown', 'xls', 'xlsx', 'csv',
    'json', 'xml', 'yaml', 'yml', 'log',
  }.contains(ext)) {
    return 'doc';
  }
  if (const {
    'js', 'mjs', 'ts', 'tsx', 'jsx', 'dart', 'py', 'rb', 'go', 'rs', 'java',
    'kt', 'c', 'h', 'cpp', 'hpp', 'cs', 'php', 'sh', 'html', 'css', 'scss',
    'sql', 'toml', 'ini', 'conf',
  }.contains(ext)) {
    return 'code';
  }
  return 'file';
}

IconData kindIcon(String kind) => switch (kind) {
      'dir' => Icons.folder_rounded,
      'image' => Icons.image_rounded,
      'video' => Icons.movie_rounded,
      'audio' => Icons.graphic_eq_rounded,
      'doc' => Icons.description_rounded,
      'archive' => Icons.folder_zip_rounded,
      'code' => Icons.code_rounded,
      _ => Icons.insert_drive_file_rounded,
    };

Color kindColor(String kind) => switch (kind) {
      'dir' => const Color(0xFFF2B429),
      'image' => const Color(0xFF4F9CF9),
      'video' => const Color(0xFFFF6B9D),
      'audio' => const Color(0xFF8B5CF6),
      'doc' => const Color(0xFF38BDF8),
      'archive' => const Color(0xFFF59E0B),
      'code' => const Color(0xFF34D399),
      _ => const Color(0xFF94A3B8),
    };

/// A rounded, tinted square holding the family glyph — the visual unit the web
/// list and grid are built on.
class KindTile extends StatelessWidget {
  final String kind;
  final double size;

  const KindTile({super.key, required this.kind, this.size = 42});

  @override
  Widget build(BuildContext context) {
    final color = kindColor(kind);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(kindIcon(kind), color: color, size: size * 0.5),
    );
  }
}

/// Marks a file that lives in the release rather than in a commit.
class CloudBadge extends StatelessWidget {
  const CloudBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 7, vertical: compact ? 2 : 3),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_done_rounded, size: compact ? 10 : 11, color: cs.onTertiaryContainer),
          const SizedBox(width: 3),
          Text(
            'large',
            style: TextStyle(
              fontSize: compact ? 8.5 : 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: cs.onTertiaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

/// One file in list view. Everything is in memory, so this stays a cheap
/// widget: a tinted glyph, two lines of text and the size on the right.
class FileRow extends StatelessWidget {
  final GithubFileItem item;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const FileRow({
    super.key,
    required this.item,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final kind = fileKind(item.name, directory: item.isDirectory);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: selected ? cs.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(ReveTokens.rM),
        child: InkWell(
          borderRadius: BorderRadius.circular(ReveTokens.rM),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                if (selecting)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Icon(
                      selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                      size: 20,
                      color: selected ? cs.primary : cs.outline,
                    ),
                  ),
                KindTile(kind: kind),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: selected ? cs.onSecondaryContainer : cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.isDirectory
                            ? 'Folder'
                            : '${formatBytes(item.size)}${item.isAsset ? ' · release asset' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (item.isAsset) const CloudBadge(compact: true),
                if (!item.isDirectory) ...[
                  const SizedBox(width: 8),
                  Text(
                    formatBytes(item.size),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One file in grid view: a big glyph or thumbnail, then name and size.
class FileCard extends StatelessWidget {
  final GithubFileItem item;
  final String? imageUrl;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const FileCard({
    super.key,
    required this.item,
    this.imageUrl,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final kind = fileKind(item.name, directory: item.isDirectory);
    final showImage = kind == 'image' && imageUrl != null;
    return Material(
      color: selected ? cs.secondaryContainer : cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(ReveTokens.rL),
      child: InkWell(
        borderRadius: BorderRadius.circular(ReveTokens.rL),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ReveTokens.rL),
            border: Border.all(
              color: selected
                  ? cs.primary.withValues(alpha: 0.6)
                  : cs.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(ReveTokens.rM),
                        child: showImage
                            ? Image.network(
                                imageUrl!,
                                fit: BoxFit.cover,
                                cacheWidth: 320,
                                filterQuality: FilterQuality.low,
                                errorBuilder: (context, error, stack) =>
                                    _GlyphPlate(kind: kind),
                              )
                            : _GlyphPlate(kind: kind),
                      ),
                    ),
                    if (selecting)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Icon(
                          selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                          size: 18,
                          color: selected ? cs.primary : Colors.white,
                        ),
                      ),
                    if (item.isAsset)
                      const Positioned(top: 6, right: 6, child: CloudBadge()),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Text(
                  item.isDirectory ? 'Folder' : formatBytes(item.size),
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlyphPlate extends StatelessWidget {
  final String kind;
  const _GlyphPlate({required this.kind});

  @override
  Widget build(BuildContext context) {
    final color = kindColor(kind);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.22),
            color.withValues(alpha: 0.08),
          ],
        ),
      ),
      child: Center(child: Icon(kindIcon(kind), size: 34, color: color)),
    );
  }
}

/// The repo/branch/storage header. Replaces two dropdowns in the app bar with
/// one tap target that says where the files live and how full it is.
class DriveHeader extends StatelessWidget {
  final String title;
  final String branch;
  final int files;
  final int committedBytes;
  final int assetBytes;
  final VoidCallback onTap;

  const DriveHeader({
    super.key,
    required this.title,
    required this.branch,
    required this.files,
    required this.committedBytes,
    required this.assetBytes,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = committedBytes + assetBytes;
    final share = total <= 0 ? 0.0 : assetBytes / total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(ReveTokens.rL),
        child: InkWell(
          borderRadius: BorderRadius.circular(ReveTokens.rL),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ReveTokens.rL),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: ReveTokens.brandGradient),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.folder_special_rounded, size: 20, color: Colors.white),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, letterSpacing: -0.1),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.call_split_rounded, size: 12, color: cs.onSurfaceVariant),
                          const SizedBox(width: 3),
                          Text(
                            branch.isEmpty ? 'default branch' : branch,
                            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                          ),
                          Text(
                            '  ·  $files item${files == 1 ? '' : 's'}  ·  ${formatBytes(total)}',
                            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (total > 0)
                  Tooltip(
                    message: assetBytes > 0
                        ? '${formatBytes(assetBytes)} in release assets'
                        : 'Committed files',
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: share,
                            strokeWidth: 3.4,
                            backgroundColor: cs.surfaceContainerHighest,
                            strokeCap: StrokeCap.round,
                          ),
                          Text(
                            '${(share * 100).round()}',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(width: 2),
                Icon(Icons.unfold_more_rounded, size: 18, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
