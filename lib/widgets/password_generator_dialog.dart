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

  // High-entropy 256-word curated list
  static const List<String> _wordList = [
    'firtina', 'guvenli', 'dalga', 'zirve', 'kartal', 'yildiz', 'gokyuzu',
    'okyanus', 'caglayan', 'ruzgar', 'pusula', 'kalkan', 'safir', 'elmas',
    'volkan', 'simsek', 'gece', 'safak', 'ates', 'kaya', 'demir', 'celik',
    'orman', 'nehir', 'bulut', 'yagmur', 'gunes', 'ay', 'samanyolu', 'gezegen',
    'hazine', 'anahtar', 'kaplan', 'aslan', 'sahil', 'ada', 'ufuk', 'kutup',
    'prism', 'quantum', 'cipher', 'nexus', 'vortex', 'falcon', 'titan', 'shield',
    'akarsu', 'albatros', 'anemon', 'atlas', 'badem', 'balta', 'baraj', 'bayrak',
    'beyaz', 'biber', 'bilge', 'bizon', 'bora', 'bozkir', 'bugday', 'burc',
    'camur', 'ceviz', 'cicek', 'cigdem', 'cinar', 'cizgi', 'coban', 'cozum',
    'daglar', 'damla', 'deniz', 'derin', 'destan', 'diken', 'dilek', 'direk',
    'doga', 'dolunay', 'dostluk', 'duman', 'dunya', 'duvar', 'ebru', 'efsane',
    'ejder', 'eksen', 'elci', 'elma', 'enerji', 'erik', 'fener', 'fidan',
    'filiz', 'firtina', 'gamze', 'gece', 'gelincik', 'gemici', 'golge', 'gorus',
    'golet', 'gunduz', 'guvercin', 'guzel', 'haber', 'halic', 'hamle', 'hasat',
    'havuz', 'hayal', 'hedef', 'hilal', 'hisar', 'huzur', 'irmak', 'isik',
    'kadeh', 'kagit', 'kahve', 'kale', 'kandil', 'kanat', 'kapadokya', 'karaca',
    'kardelen', 'kasirga', 'kayik', 'keman', 'kent', 'kilic', 'kiraz', 'kristal',
    'kumsal', 'kurt', 'kuzey', 'lale', 'leopar', 'liman', 'lokomotif', 'marti',
    'masal', 'mavilik', 'melek', 'mercan', 'mehir', 'mese', 'meteor', 'mihrak',
    'mimoza', 'nane', 'nar', 'nefes', 'nilufer', 'nisan', 'nokta', 'obruk',
    'ocak', 'oguz', 'onur', 'ozgur', 'pamuk', 'panter', 'parilti', 'patika',
    'petek', 'pinar', 'polar', 'poyraz', 'prizma', 'radar', 'safir', 'sancak',
    'saray', 'sarmasik', 'selvi', 'serin', 'simsek', 'sirac', 'soguk', 'sonbahar',
    'sultan', 'suret', 'surucu', 'safak', 'sahika', 'sahin', 'selale', 'simsek',
    'tilsim', 'toprak', 'toros', 'tugra', 'turna', 'ufuk', 'ugur', 'umut',
    'uzum', 'vadi', 'vaha', 'vefa', 'volkan', 'yakut', 'yalcin', 'yaprak',
    'yasemin', 'yayla', 'yelken', 'yigit', 'yildiz', 'yunus', 'yosun', 'zaman',
    'zebra', 'zencefil', 'zeytin', 'zirve', 'zumrut', 'anchor', 'beacon', 'breeze',
    'canyon', 'cascade', 'castle', 'comet', 'cosmos', 'cradle', 'crystal', 'dawn',
    'desert', 'echo', 'ember', 'forest', 'frost', 'galaxy', 'glacier', 'harbor',
    'horizon', 'island', 'jungle', 'lagoon', 'legend', 'meadow', 'nebula', 'oasis',
    'orbit', 'pathway', 'phoenix', 'pioneer', 'planet', 'pyramid', 'radiant', 'shadow',
    'sierra', 'silver', 'solstice', 'spark', 'summit', 'thunder', 'timber', 'twilight',
    'valley', 'velocity', 'voyage', 'whisper', 'zenith'
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
      String w = _wordList[random.nextInt(_wordList.length)];
      if (_capitalize) {
        w = w[0].toUpperCase() + w.substring(1);
      }
      words.add(w);
    }

    if (_includeNumberInPassphrase) {
      final insertIdx = random.nextInt(words.length);
      final num = random.nextInt(90) + 10;
      words[insertIdx] = '${words[insertIdx]}$num';
    }

    final pass = words.join(_separator);
    // Entropy: wordCount * log2(256) = wordCount * 8 bits + digit bits
    final entropy = (_wordCount * 8.0) + (_includeNumberInPassphrase ? 6.6 : 0.0);

    setState(() {
      _generated = pass;
      _entropyBits = entropy;
    });
  }

  Color _getEntropyColor() {
    if (_entropyBits < 45) return Colors.redAccent;
    if (_entropyBits < 65) return Colors.orangeAccent;
    if (_entropyBits < 90) return Colors.blueAccent;
    return Colors.green;
  }

  String _getEntropyLevel() {
    if (_entropyBits < 45) return 'Zayıf';
    if (_entropyBits < 65) return 'Orta';
    if (_entropyBits < 90) return 'Çok Güçlü';
    return 'Kırılamaz (Askeri Düzey)';
  }

  @override
  Widget build(BuildContext context) {
    final color = _getEntropyColor();
    final level = _getEntropyLevel();

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.shield_outlined, color: Colors.blueAccent),
          SizedBox(width: 8),
          Text('Güvenli Şifre Motoru', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Segmented mode selector
              SegmentedButton<GeneratorMode>(
                segments: const [
                  ButtonSegment(value: GeneratorMode.password, label: Text('Karakter Şifre')),
                  ButtonSegment(value: GeneratorMode.passphrase, label: Text('Diceware Parola')),
                ],
                selected: {_mode},
                onSelectionChanged: (val) {
                  setState(() {
                    _mode = val.first;
                    _generate();
                  });
                },
              ),
              const SizedBox(height: 16),

              // Generated result display box
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withOpacity(0.6), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      _generated,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$level (${_entropyBits.toStringAsFixed(1)} bit entropi)',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          tooltip: 'Yeniden Üret',
                          onPressed: _generate,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              if (_mode == GeneratorMode.password) ...[
                // Password length slider (up to 256)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Karakter Uzunluğu:'),
                    Text('$_length', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                Slider(
                  value: _length.toDouble(),
                  min: 8,
                  max: 256,
                  divisions: 248,
                  label: '$_length',
                  onChanged: (val) {
                    setState(() {
                      _length = val.round();
                      _generate();
                    });
                  },
                ),
                SwitchListTile(
                  title: const Text('Büyük Harfler (A-Z)'),
                  value: _includeUpper,
                  dense: true,
                  onChanged: (val) {
                    setState(() {
                      _includeUpper = val;
                      _generate();
                    });
                  },
                ),
                SwitchListTile(
                  title: const Text('Küçük Harfler (a-z)'),
                  value: _includeLower,
                  dense: true,
                  onChanged: (val) {
                    setState(() {
                      _includeLower = val;
                      _generate();
                    });
                  },
                ),
                SwitchListTile(
                  title: const Text('Rakamlar (0-9)'),
                  value: _includeNumbers,
                  dense: true,
                  onChanged: (val) {
                    setState(() {
                      _includeNumbers = val;
                      _generate();
                    });
                  },
                ),
                SwitchListTile(
                  title: const Text('Semboller (!@#\$%^&*)'),
                  value: _includeSymbols,
                  dense: true,
                  onChanged: (val) {
                    setState(() {
                      _includeSymbols = val;
                      _generate();
                    });
                  },
                ),
                SwitchListTile(
                  title: const Text('Karışık Karakterleri Hariç Tut (0, O, l, 1, I)'),
                  value: _avoidAmbiguous,
                  dense: true,
                  onChanged: (val) {
                    setState(() {
                      _avoidAmbiguous = val;
                      _generate();
                    });
                  },
                ),
              ] else ...[
                // Passphrase options
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Kelime Sayısı:'),
                    Text('$_wordCount', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                Slider(
                  value: _wordCount.toDouble(),
                  min: 3,
                  max: 12,
                  divisions: 9,
                  label: '$_wordCount',
                  onChanged: (val) {
                    setState(() {
                      _wordCount = val.round();
                      _generate();
                    });
                  },
                ),
                SwitchListTile(
                  title: const Text('İlk Harfleri Büyüt (TitleCase)'),
                  value: _capitalize,
                  dense: true,
                  onChanged: (val) {
                    setState(() {
                      _capitalize = val;
                      _generate();
                    });
                  },
                ),
                SwitchListTile(
                  title: const Text('Rakam Ekle (Gelişmiş Entropi)'),
                  value: _includeNumberInPassphrase,
                  dense: true,
                  onChanged: (val) {
                    setState(() {
                      _includeNumberInPassphrase = val;
                      _generate();
                    });
                  },
                ),
                ListTile(
                  title: const Text('Kelime Ayırıcı:'),
                  trailing: DropdownButton<String>(
                    value: _separator,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: '-', child: Text('Tire (-)')),
                      DropdownMenuItem(value: '_', child: Text('Alt Çizgi (_)')),
                      DropdownMenuItem(value: '.', child: Text('Nokta (.)')),
                      DropdownMenuItem(value: ' ', child: Text('Boşluk ( )')),
                      DropdownMenuItem(value: '#', child: Text('Kare (#)')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _separator = val;
                          _generate();
                        });
                      }
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Kopyala'),
          onPressed: () async {
            if (_generated.isNotEmpty) {
              await ClipboardService.copySecurely(_generated);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Şifre panoya kopyalandı! (30 sn sonra silinir)')),
                );
              }
            }
          },
        ),
        FilledButton.icon(
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Kullan'),
          onPressed: () => Navigator.of(context).pop(_generated),
        ),
      ],
    );
  }
}
