import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../providers/reve_provider.dart';

/// Captures a photo with the camera and files it into the drive.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _folder = TextEditingController(text: 'Scans');
  Uint8List? _bytes;
  String? _name;
  bool _saving = false;

  @override
  void dispose() {
    _folder.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _name = picked.name;
    });
  }

  Future<void> _save() async {
    final bytes = _bytes;
    if (bytes == null) return;
    setState(() => _saving = true);
    final provider = context.read<ReveProvider>();
    final folder = _folder.text.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    final name = folder.isEmpty ? _name! : '$folder/${_name!}';
    final ok = bytes.lengthInBytes > ReveProvider.maxUploadBytes
        ? (await provider.uploadLargeFile(
            fileName: name,
            length: bytes.lengthInBytes,
            bytes: bytes,
          )).ok
        : (await provider.commitBatch([
            BatchedFile(name: name, bytes: bytes),
          ])).uploaded.isNotEmpty;
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Scan uploaded' : 'Could not upload scan')),
    );
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan document')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 260,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: _bytes == null
                  ? const Icon(Icons.document_scanner_outlined, size: 48)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.memory(_bytes!, fit: BoxFit.contain),
                    ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _capture,
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Capture with camera'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _folder,
              decoration: const InputDecoration(labelText: 'Destination folder'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _bytes == null || _saving ? null : _save,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: Text(_saving ? 'Uploading…' : 'Upload scan'),
            ),
          ],
        ),
      ),
    );
  }
}
