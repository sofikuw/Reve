import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../models/file_item.dart';
import '../../providers/reve_provider.dart';
import '../kit.dart';

/// Minimal streaming music player over the audio files already in the drive.
class MusicScreen extends StatefulWidget {
  const MusicScreen({super.key});

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> {
  VideoPlayerController? _controller;
  int? _index;
  String? _error;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _play(int index, List<GithubFileItem> tracks) async {
    await _controller?.dispose();
    final provider = context.read<ReveProvider>();
    final item = tracks[index];
    final url = await provider.streamUrlFor(item);
    if (url == null) {
      setState(() => _error = 'No stream URL for ${item.name}');
      return;
    }
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _index = index;
        _error = null;
      });
      await controller.play();
    } catch (e) {
      await controller.dispose();
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReveProvider>();
    final tracks = provider
        .allCachedItems()
        .where((item) => fileKind(item.name) == 'audio')
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Scaffold(
      appBar: AppBar(title: const Text('Music')),
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (_index != null)
            Card(
              margin: const EdgeInsets.all(12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Text(tracks[_index!].name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    VideoPlayer(_controller!),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.skip_previous_rounded),
                          onPressed: _index! > 0 ? () => _play(_index! - 1, tracks) : null,
                        ),
                        IconButton(
                          icon: Icon(_controller!.value.isPlaying
                              ? Icons.pause_circle_rounded
                              : Icons.play_circle_rounded),
                          iconSize: 36,
                          onPressed: () => _controller!.value.isPlaying
                              ? _controller!.pause()
                              : _controller!.play(),
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_next_rounded),
                          onPressed: _index! < tracks.length - 1
                              ? () => _play(_index! + 1, tracks)
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: tracks.isEmpty
                ? const Center(child: Text('No audio files cached yet'))
                : ListView.separated(
                    itemCount: tracks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final item = tracks[index];
                      return ListTile(
                        leading: const Icon(Icons.audiotrack_rounded),
                        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(item.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => _play(index, tracks),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
