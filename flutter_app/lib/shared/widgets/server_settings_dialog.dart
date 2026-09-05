import 'package:flutter/material.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/network/server_discovery.dart';

/// A small dialog that lets the user enter their PC's LAN IP address so the
/// app can connect to the backend on a real device without needing an emulator.
///
/// Implemented as a proper StatefulWidget (not StatefulBuilder) so that
/// Navigator.pop(context) always uses the widget's own stable BuildContext,
/// which prevents layout assertion errors on the underlying screen when async
/// operations complete and call setState.
Future<void> showServerSettingsDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _ServerSettingsDialog(),
  );
}

class _ServerSettingsDialog extends StatefulWidget {
  const _ServerSettingsDialog();

  @override
  State<_ServerSettingsDialog> createState() => _ServerSettingsDialogState();
}

class _ServerSettingsDialogState extends State<_ServerSettingsDialog> {
  final _ctrl = TextEditingController();
  bool _saving = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadSavedIp();
  }

  Future<void> _loadSavedIp() async {
    final saved = await ServerDiscovery.getManualIp();
    if (mounted) {
      setState(() {
        _ctrl.text = saved ?? '';
        _loaded = true;
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _autoDetect() async {
    setState(() => _saving = true);
    await ServerDiscovery.clearManualIp();
    await ApiClient.rediscover();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _save() async {
    final ip = _ctrl.text.trim();
    setState(() => _saving = true);
    if (ip.isNotEmpty) {
      await ServerDiscovery.setManualIp(ip);
    } else {
      await ServerDiscovery.clearManualIp();
    }
    await ApiClient.rediscover();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const AlertDialog(
        content: SizedBox(
          height: 60,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16))),
      title: Row(children: [
        Icon(Icons.wifi_find_rounded, color: cs.primary, size: 22),
        const SizedBox(width: 8),
        const Text('Server Connection', style: TextStyle(fontSize: 17)),
      ]),
      // SizedBox(width: double.maxFinite) gives AlertDialog's IntrinsicWidth
      // a finite reference width so TextField / Container borders (which use
      // RenderPhysicalShape) don't receive unbounded constraints.
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your PC\'s IP address (same Wi-Fi network).\n'
              'Leave blank to use auto-discovery.',
              style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.5),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: const Text(
                '💡 Windows: open Command Prompt → type ipconfig\n'
                '    look for "IPv4 Address" under your Wi-Fi adapter\n'
                '    e.g.  192.168.1.8\n\n'
                '🖥  Start backend with:\n'
                '    uvicorn app.main:app --host 0.0.0.0 --port 8000',
                style: TextStyle(fontSize: 11.5, color: Colors.black87, height: 1.6),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _ctrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'PC IP Address',
                hintText: '192.168.1.x',
                prefixIcon: const Icon(Icons.computer_rounded),
                prefixText: 'http://',
                suffixText: ':8000',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      actions: [
        OutlinedButton(
          onPressed: _saving ? null : _autoDetect,
          child: const Text('Auto-detect'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: cs.primary),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Save & Connect'),
        ),
      ],
    );
  }
}
