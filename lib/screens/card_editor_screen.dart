import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/vault_item.dart';
import '../providers/vault_provider.dart';
import '../services/clipboard_service.dart';

class CardEditorScreen extends StatefulWidget {
  final VaultItem? initialItem;

  const CardEditorScreen({super.key, this.initialItem});

  @override
  State<CardEditorScreen> createState() => _CardEditorScreenState();
}

class _CardEditorScreenState extends State<CardEditorScreen> {
  late TextEditingController _titleController;
  late TextEditingController _holderController;
  late TextEditingController _numberController;
  late TextEditingController _expiryController;
  late TextEditingController _cvvController;
  late TextEditingController _pinController;
  late TextEditingController _notesController;
  late TextEditingController _tagInputController;
  late List<String> _tags;
  late bool _isFavorite;
  late bool _isPinned;

  bool _obscureNumber = true;
  bool _obscureCvv = true;
  bool _obscurePin = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    _titleController = TextEditingController(text: item?.title ?? '');
    _holderController = TextEditingController(text: item?.cardHolder ?? '');
    _numberController = TextEditingController(text: item?.cardNumber ?? '');
    _expiryController = TextEditingController(text: item?.cardExpiry ?? '');
    _cvvController = TextEditingController(text: item?.cardCvv ?? '');
    _pinController = TextEditingController(text: item?.cardPin ?? '');
    _notesController = TextEditingController(text: item?.content ?? '');
    _tagInputController = TextEditingController();
    _tags = List<String>.from(item?.tags ?? []);
    _isFavorite = item?.isFavorite ?? false;
    _isPinned = item?.isPinned ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _holderController.dispose();
    _numberController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    _pinController.dispose();
    _notesController.dispose();
    _tagInputController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty && _numberController.text.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _isSaving = true);
    final vault = context.read<VaultProvider>();

    final updated = (widget.initialItem ?? vault.createNewCard()).copyWith(
      title: title.isEmpty ? 'İsimsiz Kart' : title,
      cardHolder: _holderController.text.trim(),
      cardNumber: _numberController.text.trim(),
      cardExpiry: _expiryController.text.trim(),
      cardCvv: _cvvController.text.trim(),
      cardPin: _pinController.text.trim(),
      content: _notesController.text.trim(),
      tags: _tags,
      isFavorite: _isFavorite,
      isPinned: _isPinned,
      clientUpdatedAt: DateTime.now().toUtc(),
    );

    await vault.saveItem(updated);
    setState(() => _isSaving = false);

    if (mounted) Navigator.of(context).pop();
  }

  void _addTag(String rawTag) {
    final tag = rawTag.trim().replaceAll('#', '');
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      setState(() {
        _tags.add(tag);
        _tagInputController.clear();
      });
    }
  }

  void _removeTag(String tag) {
    setState(() => _tags.remove(tag));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialItem == null ? 'Yeni Kart Ekle' : 'Kartı Düzenle'),
        actions: [
          IconButton(
            icon: Icon(_isPinned ? Icons.push_pin : Icons.push_pin_outlined),
            color: _isPinned ? Colors.blueAccent : null,
            tooltip: _isPinned ? 'Sabitlemeyi Kaldır' : 'Başa Sabitle',
            onPressed: () => setState(() => _isPinned = !_isPinned),
          ),
          IconButton(
            icon: Icon(_isFavorite ? Icons.star_rounded : Icons.star_outline_rounded),
            color: _isFavorite ? Colors.amber : null,
            tooltip: _isFavorite ? 'Favorilerden Çıkar' : 'Favorilere Ekle',
            onPressed: () => setState(() => _isFavorite = !_isFavorite),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            icon: _isSaving
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined, size: 18),
            label: const Text('Kaydet'),
            onPressed: _isSaving ? null : _save,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Title (Card label)
                TextField(
                  controller: _titleController,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    labelText: 'Kart Adı / Etiketi',
                    hintText: 'Örn: Ana Banka Kartım, Şirket Kredi Kartı',
                    prefixIcon: Icon(Icons.credit_card_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // Cardholder Name
                TextField(
                  controller: _holderController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Kart Üzerindeki İsim',
                    hintText: 'AHMET YILMAZ',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // Card Number
                TextField(
                  controller: _numberController,
                  keyboardType: TextInputType.number,
                  obscureText: _obscureNumber,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    letterSpacing: _obscureNumber ? 2 : 1.5,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Kart Numarası',
                    hintText: '0000 0000 0000 0000',
                    prefixIcon: const Icon(Icons.payment_outlined),
                    border: const OutlineInputBorder(),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(_obscureNumber ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscureNumber = !_obscureNumber),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 18),
                          tooltip: 'Kart Numarasını Kopyala (30 sn)',
                          onPressed: () async {
                            if (_numberController.text.isNotEmpty) {
                              await ClipboardService.copySecurely(_numberController.text);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Kart numarası kopyalandı! (30 sn güvenli)')),
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Expiry & CVV & PIN Row
                Row(
                  children: [
                    // Expiry
                    Expanded(
                      flex: 4,
                      child: TextField(
                        controller: _expiryController,
                        keyboardType: TextInputType.datetime,
                        decoration: const InputDecoration(
                          labelText: 'Son Kullanma',
                          hintText: 'AA/YY',
                          prefixIcon: Icon(Icons.calendar_today_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // CVV
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _cvvController,
                        keyboardType: TextInputType.number,
                        obscureText: _obscureCvv,
                        maxLength: 4,
                        decoration: InputDecoration(
                          labelText: 'CVV / CVC',
                          counterText: '',
                          prefixIcon: const Icon(Icons.security_outlined),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureCvv ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                            onPressed: () => setState(() => _obscureCvv = !_obscureCvv),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // PIN
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _pinController,
                        keyboardType: TextInputType.number,
                        obscureText: _obscurePin,
                        maxLength: 6,
                        decoration: InputDecoration(
                          labelText: 'Kart PIN',
                          counterText: '',
                          prefixIcon: const Icon(Icons.lock_clock_outlined),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePin ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                            onPressed: () => setState(() => _obscurePin = !_obscurePin),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Tags
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ..._tags.map(
                      (tag) => Chip(
                        label: Text('#$tag', style: const TextStyle(fontSize: 12)),
                        onDeleted: () => _removeTag(tag),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    SizedBox(
                      width: 130,
                      child: TextField(
                        controller: _tagInputController,
                        style: const TextStyle(fontSize: 12),
                        decoration: const InputDecoration(
                          hintText: '+ etiket ekle',
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onSubmitted: _addTag,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Notes
                TextField(
                  controller: _notesController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Güvenli Notlar (Müşteri no, IBAN, banka şubesi vb.)',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
