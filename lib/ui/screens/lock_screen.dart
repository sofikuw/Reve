import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/reve_provider.dart';

/// Numeric gate for the app-lock PIN. Has no network access: the PIN is only
/// a question "are you the owner of this phone", and the answers are in the
/// file manager once unlocked.
class LockScreen extends StatefulWidget {
  final VoidCallback onUnlock;

  const LockScreen({super.key, required this.onUnlock});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  static const List<String> _digits = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];
  final List<String> _entered = [];
  String _error = '';

  void _press(String digit) {
    if (_entered.length >= 8) return;
    _entered.add(digit);
    if (_entered.length == 6) _tryUnlock();
  }

  void _backspace() {
    if (_entered.isEmpty) return;
    _entered.removeLast();
    setState(() => _error = '');
  }

  Future<void> _tryUnlock() async {
    final pin = _entered.join();
    _entered.clear();
    final ok = await context.read<ReveProvider>().verifyPin(pin);
    if (!mounted) return;
    if (ok) {
      widget.onUnlock();
    } else {
      setState(() => _error = 'Wrong PIN — try again');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dots = _entered.map((d) => Icon(Icons.circle, size: 10, color: cs.onSurfaceVariant)).toList();
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: PreferredSize(
        preferredSize: const Size(0.0, 0.0),
        child: const SizedBox.shrink(),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, size: 56, color: cs.primary),
          const SizedBox(height: 18),
          const Text('Enter the PIN', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          Row(mainAxisSize: MainAxisSize.min, children: dots),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(_error, style: TextStyle(fontSize: 12.5, color: cs.error)),
          ],
          SizedBox(
            width: 280,
            child: GridView.count(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
              crossAxisCount: 3,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.1,
              children: [
                for (var d in _digits)
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _press(d),
                    child: Ink(
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text(d,
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: cs.onSurface)),
                      ),
                    ),
                  ),
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _backspace,
                  child: Ink(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.backspace_outlined, size: 22, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
