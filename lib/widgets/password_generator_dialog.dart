import 'dart:math';
import 'package:flutter/material.dart';
import '../services/clipboard_service.dart';

enum GeneratorMode {
  password,
  passphrase,
}

class PasswordGeneratorDialog extends StatefulWidget {
  const PasswordGeneratorDialog({super.key});

  @override
  State<PasswordGeneratorDialog> createState() => _PasswordGeneratorDialogState();
}

class _PasswordGeneratorDialogState extends State<PasswordGeneratorDialog> {
  GeneratorMode _mode = GeneratorMode.password;

  // Password options
  int _length = 24; // Up to 256 characters!
  bool _includeUpper = true;
  bool _includeLower = true;
  bool _includeNumbers = true;
  bool _includeSymbols = true;
  bool _avoidAmbiguous = true; // Excludes 0, O, l, 1, I
  int _minNumbers = 2;
  int _minSymbols = 2;

  // Passphrase options
  int _wordCount = 5;
  String _separator = '-';
  bool _capitalize = true;
  bool _includeNumberInPassphrase = true;

  String _generated = '';
  double _entropyBits = 0.0;

  static const List<String> _wordList = [
    'firtina', 'guvenli', 'dalga', 'zirve', 'kartal', 'yildiz', 'gokyuzu',
    'okyanus', 'caglayan', 'ruzgar', 'pusula', 'kalkan', 'safir', 'elmas',
    'volkan', 'simsek', 'gece', 'safak', 'ates', 'kaya', 'demir', 'celik',
    'orman', 'nehir', 'bulut', 'yagmur', 'gunes', 'ay', 'samanyolu', 'gezegen',
    'hazine', 'anahtar', 'kaplan', 'aslan', 'sahil', 'ada', 'ufuk', 'kutup',
    'prism', 'quantum', 'cipher', 'nexus', 'vortex', 'falcon', 'titan', 'shield'
  ];

  @override
  void initState() {
    super.initState();
    _generate();
  }

  void _generate() {
    if (_mode == GeneratorMode.password) {
      _generatePassword();
    } else {
      _generatePassphrase();
    }
  }

  void _generatePassword() {
    String upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    String lower = 'abcdefghijklmnopqrstuvwxyz';
    String numbers = '0123456789';
    String symbols = '!@#\$%^&*()-_=+[]{}|;:,.<>?';

    if (_avoidAmbiguous) {
      upper = upper.replaceAll(RegExp(r'[OI]'), '');
      lower = lower.replaceAll(RegExp(r'[l]'), '');
      numbers = numbers.replaceAll(RegExp(r'[01]'), '');
    }

    String pool = '';
    if (_includeUpper) pool += upper;
    if (_includeLower) pool += lower;
    if (_includeNumbers) pool += numbers;
    if (_includeSymbols) pool += symbols;

    if (pool.isEmpty) {
      setState(() {
        _generated = '';
        _entropyBits = 0.0;
      });
      return;
    }

    final random = Random.secure();
    final chars = <String>[];

    // Guarantee minimum numbers and symbols
    if (_includeNumbers && numbers.isNotEmpty) {
      for (int i = 0; i < min(_minNumbers, _length ~/ 3); i++) {
        chars.add(numbers[random.nextInt(numbers.length)]);
      }
    }
    if (_includeSymbols && symbols.isNotEmpty) {
      for (int i = 0; i < min(_minSymbols, _length ~/ 3); i++) {
        chars.add(symbols[random.nextInt(symbols.length)]);
      }
    }

    while (chars.length < _length) {
      chars.add(pool[random.nextInt(pool.length)]);
    }

    chars.shuffle(random);
    final pass = chars.join();
    final entropy = _length * (log(pool.length) / ln2);

    setState(() {
      _generated = pass;
      _entropyBits = entropy;
    });
  }

  void _generatePassphrase() {
    final random = Random.secure();
    final words = <String>[];

    for (int i = 0; i < _wordCount; i++) {
      String word = _wordList[random.nextInt(_wordList.length)];
      if (_capitalize) {
        word = word[0].toUpperCase() + word.substring(1);
      }
      words.add(word);
    }

    if (_includeNumberInPassphrase) {
      final num = random.nextInt(900) + 100;
      words.add(num.toString());
    }

    final phrase = words.join(_separator);
    final entropy = _wordCount * (log(_wordList.length) / ln2) +
        (_includeNumberInPassphrase ? (log(900) / ln2) : 0);

    setState(() {
      _generated = phrase;
      _entropyBits = entropy;
    });
  }

  @override
  Widget build(BuildContext context) {
    Color entropyColor = Colors.green;
    String entropyText = 'Kırılması İmkansız';
    if (_entropyBits < 40) {
      entropyColor = Colors.redAccent;
      entropyText = 'Zayıf';
    } else if (_entropyBits < 70) {
      entropyColor = Colors.orangeAccent;
      entropyText = 'Makul';
    } else if (_entropyBits < 100) {
      entropyColor = Colors.blueAccent;
      entropyText = 'Çok Güçlü';
    }

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.shield_outlined, color: Colors.blueAccent),
          SizedBox(width: 10),
          Text('Gelişmiş Şifre Motoru'),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Result Box
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            _generated.isEmpty ? 'Kriter seçin' : _generated,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          tooltip: 'Yeniden Üret',
                          onPressed: _generate,
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          tooltip: 'Kopyala (30 sn güvenli)',
                          onPressed: _generated.isEmpty
                              ? null
                              : () async {
                                  await ClipboardService.copySecurely(_generated);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Şifre kopyalandı! (30 sn sonra silinir)')),
                                    );
                                  }
                                },
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Entropy Badge
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: entropyColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${_entropyBits.round()} bit entropi ($entropyText)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: entropyColor,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${_generated.length} karakter',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Mode Switcher (Password vs Passphrase)
              SegmentedButton<GeneratorMode>(
                segments: const [
                  ButtonSegment(
                    value: GeneratorMode.password,
                    label: Text('Karakter Şifre'),
                    icon: Icon(Icons.password, size: 16),
                  ),
                  ButtonSegment(
                    value: GeneratorMode.passphrase,
                    label: Text('Akılda Kalıcı'),
                    icon: Icon(Icons.text_fields, size: 16),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (val) {
                  setState(() => _mode = val.first);
                  _generate();
                },
              ),

              const SizedBox(height: 16),

              if (_mode == GeneratorMode.password) ...[
                // Length Slider (Up to 256 chars!)
                Row(
                  children: [
                    Text('Uzunluk: $_length'),
                    Expanded(
                      child: Slider(
                        value: _length.toDouble(),
                        min: 8,
                        max: 256,
                        divisions: 248,
                        label: '$_length',
                        onChanged: (val) {
                          setState(() => _length = val.round());
                          _generate();
                        },
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('Büyük Harfler (A-Z)'),
                  value: _includeUpper,
                  onChanged: (v) {
                    setState(() => _includeUpper = v);
                    _generate();
                  },
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('Küçük Harfler (a-z)'),
                  value: _includeLower,
                  onChanged: (v) {
                    setState(() => _includeLower = v);
                    _generate();
                  },
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('Rakamlar (0-9)'),
                  value: _includeNumbers,
                  onChanged: (v) {
                    setState(() => _includeNumbers = v);
                    _generate();
                  },
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('Özel Karakterler (!@#\$)'),
                  value: _includeSymbols,
                  onChanged: (v) {
                    setState(() => _includeSymbols = v);
                    _generate();
                  },
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('Karıştırılan Karakterleri Çıkar (0, O, l, 1, I)'),
                  value: _avoidAmbiguous,
                  onChanged: (v) {
                    setState(() => _avoidAmbiguous = v);
                    _generate();
                  },
                ),
              ] else ...[
                // Passphrase Options
                Row(
                  children: [
                    Text('Kelime Sayısı: $_wordCount'),
                    Expanded(
                      child: Slider(
                        value: _wordCount.toDouble(),
                        min: 3,
                        max: 10,
                        divisions: 7,
                        label: '$_wordCount',
                        onChanged: (val) {
                          setState(() => _wordCount = val.round());
                          _generate();
                        },
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('Ayırıcı:'),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: _separator,
                      items: const [
                        DropdownMenuItem(value: '-', child: Text('Tire (-)')),
                        DropdownMenuItem(value: '_', child: Text('Alt Çizgi (_)')),
                        DropdownMenuItem(value: '.', child: Text('Nokta (.)')),
                        DropdownMenuItem(value: ' ', child: Text('Boşluk ( )')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _separator = val);
                          _generate();
                        }
                      },
                    ),
                  ],
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('Baş Harfleri Büyüt'),
                  value: _capitalize,
                  onChanged: (v) {
                    setState(() => _capitalize = v);
                    _generate();
                  },
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('Rastgele Sayı Ekle'),
                  value: _includeNumberInPassphrase,
                  onChanged: (v) {
                    setState(() => _includeNumberInPassphrase = v);
                    _generate();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
        FilledButton(
          onPressed: _generated.isEmpty
              ? null
              : () => Navigator.of(context).pop(_generated),
          child: const Text('Bu Şifreyi Kullan'),
        ),
      ],
    );
  }
}
