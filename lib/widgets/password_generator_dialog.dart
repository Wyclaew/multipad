import 'dart:math';
import 'package:flutter/material.dart';
import '../services/clipboard_service.dart';

class PasswordGeneratorDialog extends StatefulWidget {
  const PasswordGeneratorDialog({super.key});

  @override
  State<PasswordGeneratorDialog> createState() => _PasswordGeneratorDialogState();
}

class _PasswordGeneratorDialogState extends State<PasswordGeneratorDialog> {
  int _length = 16;
  bool _includeUpper = true;
  bool _includeLower = true;
  bool _includeNumbers = true;
  bool _includeSymbols = true;
  String _generatedPassword = '';

  @override
  void initState() {
    super.initState();
    _generatePassword();
  }

  void _generatePassword() {
    const upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const lower = 'abcdefghijklmnopqrstuvwxyz';
    const numbers = '0123456789';
    const symbols = '!@#\$%^&*()-_=+[]{}|;:,.<>?';

    String pool = '';
    if (_includeUpper) pool += upper;
    if (_includeLower) pool += lower;
    if (_includeNumbers) pool += numbers;
    if (_includeSymbols) pool += symbols;

    if (pool.isEmpty) {
      setState(() => _generatedPassword = '');
      return;
    }

    final random = Random.secure();
    final buffer = StringBuffer();
    for (int i = 0; i < _length; i++) {
      buffer.write(pool[random.nextInt(pool.length)]);
    }

    setState(() {
      _generatedPassword = buffer.toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.shield_outlined, color: Colors.blueAccent),
          SizedBox(width: 8),
          Text('Güçlü Şifre Üretici'),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      _generatedPassword.isEmpty ? 'Kriter seçin' : _generatedPassword,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Yeniden Üret',
                    onPressed: _generatePassword,
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: 'Kopyala (30sn güvenli)',
                    onPressed: _generatedPassword.isEmpty
                        ? null
                        : () async {
                            await ClipboardService.copySecurely(_generatedPassword);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Şifre kopyalandı! (30 sn sonra panodan otomatik silinecektir)'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Uzunluk: $_length'),
                Expanded(
                  child: Slider(
                    value: _length.toDouble(),
                    min: 8,
                    max: 48,
                    divisions: 40,
                    label: '$_length',
                    onChanged: (val) {
                      setState(() => _length = val.round());
                      _generatePassword();
                    },
                  ),
                ),
              ],
            ),
            SwitchListTile(
              dense: true,
              title: const Text('Büyük Harfler (A-Z)'),
              value: _includeUpper,
              onChanged: (val) {
                setState(() => _includeUpper = val);
                _generatePassword();
              },
            ),
            SwitchListTile(
              dense: true,
              title: const Text('Küçük Harfler (a-z)'),
              value: _includeLower,
              onChanged: (val) {
                setState(() => _includeLower = val);
                _generatePassword();
              },
            ),
            SwitchListTile(
              dense: true,
              title: const Text('Rakamlar (0-9)'),
              value: _includeNumbers,
              onChanged: (val) {
                setState(() => _includeNumbers = val);
                _generatePassword();
              },
            ),
            SwitchListTile(
              dense: true,
              title: const Text('Özel Karakterler (!@#\$)'),
              value: _includeSymbols,
              onChanged: (val) {
                setState(() => _includeSymbols = val);
                _generatePassword();
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
        FilledButton(
          onPressed: _generatedPassword.isEmpty
              ? null
              : () => Navigator.of(context).pop(_generatedPassword),
          child: const Text('Bu Şifreyi Kullan'),
        ),
      ],
    );
  }
}
