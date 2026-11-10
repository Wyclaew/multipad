import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/vault_provider.dart';
import '../services/clipboard_service.dart';
import '../services/pairing_service.dart';

enum PairingRole {
  send,    // Host device sharing configuration/vault to a new device
  receive, // New device receiving setup from an existing device
}

class DevicePairingScreen extends StatefulWidget {
  final PairingRole initialRole;

  const DevicePairingScreen({super.key, required this.initialRole});

  @override
  State<DevicePairingScreen> createState() => _DevicePairingScreenState();
}

class _DevicePairingScreenState extends State<DevicePairingScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Send (Host) State
  bool _includeUnlockedKey = true;
  PairingHostSession? _hostSession;
  PairingHostStatus _hostStatus = PairingHostStatus.waiting;
  String _hostStatusMessage = 'Aynı Wi-Fi ağındaki cihazların bağlanması bekleniyor...';
  bool _isStartingHost = false;

  // Send (Token) State
  final _tokenPinController = TextEditingController();
  String? _generatedToken;
  bool _isGeneratingToken = false;

  // Receive (Client LAN) State
  RawDatagramSocket? _discoverySocket;
  final Map<String, DiscoveredPairingDevice> _discoveredDevices = {};
  DiscoveredPairingDevice? _selectedDevice;
  bool _showManualIp = false;
  final _manualIpController = TextEditingController();
  final _manualPortController = TextEditingController();
  final _lanPinController = TextEditingController();
  bool _isConnectingLan = false;

  // Receive (Token) State
  final _pasteTokenController = TextEditingController();
  final _pastePinController = TextEditingController();
  bool _isParsingToken = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    if (widget.initialRole == PairingRole.send) {
      _startLanHost();
    } else {
      _startLanDiscovery();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _hostSession?.stop();
    _discoverySocket?.close();
    _tokenPinController.dispose();
    _manualIpController.dispose();
    _manualPortController.dispose();
    _lanPinController.dispose();
    _pasteTokenController.dispose();
    _pastePinController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // SEND MODE (HOST) LOGIC
  // ---------------------------------------------------------------------------
  Future<void> _startLanHost() async {
    await _hostSession?.stop();
    if (!mounted) return;

    setState(() {
      _isStartingHost = true;
      _hostStatus = PairingHostStatus.waiting;
      _hostStatusMessage = 'Güvenli X25519 eşleştirme tüneli başlatılıyor...';
    });

    try {
      final auth = context.read<AuthProvider>();
      final pairingService = PairingService(auth.cryptoService);
      final payload = await auth.buildPairingPayload(includeUnlockedKey: _includeUnlockedKey);

      final session = await pairingService.startHostSession(
        payload: payload,
        onStatusChanged: (status, message) {
          if (!mounted) return;
          setState(() {
            _hostStatus = status;
            _hostStatusMessage = message;
          });
        },
      );

      if (!mounted) {
        await session.stop();
        return;
      }

      setState(() {
        _hostSession = session;
        _isStartingHost = false;
        _hostStatusMessage = 'Aynı Wi-Fi ağındaki cihazların bağlanması bekleniyor...';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isStartingHost = false;
        _hostStatus = PairingHostStatus.closed;
        _hostStatusMessage = 'Yerel ağ sunucusu başlatılamadı: $e';
      });
    }
  }

  Future<void> _generateEncryptedToken() async {
    final pin = _tokenPinController.text.trim();
    if (pin.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Güvenlik için aktarım şifresi / PIN en az 6 karakter olmalıdır.')),
      );
      return;
    }

    setState(() => _isGeneratingToken = true);
    try {
      final auth = context.read<AuthProvider>();
      final pairingService = PairingService(auth.cryptoService);
      final payload = await auth.buildPairingPayload(includeUnlockedKey: _includeUnlockedKey);
      final token = await pairingService.createEncryptedSetupToken(
        payload: payload,
        passphrase: pin,
      );

      if (!mounted) return;
      setState(() {
        _generatedToken = token;
        _isGeneratingToken = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGeneratingToken = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kod oluşturma hatası: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // RECEIVE MODE (CLIENT) LOGIC
  // ---------------------------------------------------------------------------
  Future<void> _startLanDiscovery() async {
    _discoverySocket?.close();
    _discoverySocket = await PairingService.startDiscoveryListener((device) {
      if (!mounted) return;
      setState(() {
        _discoveredDevices[device.sessionId] = device;
        _selectedDevice ??= device;
      });
    });
  }

  Future<void> _connectViaLan() async {
    String hostIp;
    int port;

    if (!_showManualIp && _selectedDevice != null) {
      hostIp = _selectedDevice!.ip;
      port = _selectedDevice!.port;
    } else {
      hostIp = _manualIpController.text.trim();
      port = int.tryParse(_manualPortController.text.trim()) ?? 0;
    }

    final pin = _lanPinController.text.trim().replaceAll(RegExp(r'\s+'), '');

    if (hostIp.isEmpty || port <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen listeden bir cihaz seçin veya IP/Port girin.')),
      );
      return;
    }
    if (pin.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen gönderen cihazdaki 6 haneli PIN kodunu girin.')),
      );
      return;
    }

    setState(() => _isConnectingLan = true);
    try {
      final auth = context.read<AuthProvider>();
      final pairingService = PairingService(auth.cryptoService);
      final payload = await pairingService.connectAndPair(
        hostIp: hostIp,
        port: port,
        pin: pin,
      );

      await _applyPairingSuccess(payload);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isConnectingLan = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _connectViaToken() async {
    final token = _pasteTokenController.text.trim();
    final pin = _pastePinController.text.trim();

    if (token.isEmpty || pin.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen aktarım kodunu ve PIN/şifreyi girin.')),
      );
      return;
    }

    setState(() => _isParsingToken = true);
    try {
      final auth = context.read<AuthProvider>();
      final pairingService = PairingService(auth.cryptoService);
      final payload = await pairingService.parseEncryptedSetupToken(
        token: token,
        passphrase: pin,
      );

      await _applyPairingSuccess(payload);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isParsingToken = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _applyPairingSuccess(PairingPayload payload) async {
    final auth = context.read<AuthProvider>();
    final vault = context.read<VaultProvider>();
    final ok = await auth.completePairingSetup(payload);

    if (!mounted) return;
    setState(() {
      _isConnectingLan = false;
      _isParsingToken = false;
    });

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.errorMessage ?? 'Kurulum uygulanamadı.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // Trigger immediate vault load if unlocked
    if (auth.isUnlocked) {
      await vault.loadVault();
    }

    if (!mounted) return;

    // Offer instant biometric setup if device supports it and vault unlocked
    if (auth.isUnlocked && auth.canUseBiometrics && !auth.isBiometricEnabled) {
      final enableBio = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.fingerprint_rounded, color: Colors.blueAccent),
              SizedBox(width: 10),
              Text('Kurulum Tamamlandı!'),
            ],
          ),
          content: const Text(
            'Kasalarınız ve bulut ayarlarınız başarıyla aktarıldı!\n\n'
            'Bundan sonra şifre yazmadan tek dokunuşla açmak için Parmak İzi / Yüz Tanıma kilidini şimdi aktifleştirmek ister misiniz?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Daha Sonra'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.fingerprint_rounded),
              label: const Text('Aktifleştir'),
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      );

      if (enableBio == true && mounted) {
        await auth.toggleBiometrics(true);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            auth.isUnlocked
                ? '✅ Cihaz eşleştirildi ve kasalarınız senkronize edildi!'
                : '✅ Bulut ayarları aktarıldı! Şimdi Ana Şifrenizle giriş yapabilirsiniz.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    }

    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSend = widget.initialRole == PairingRole.send;

    return Scaffold(
      appBar: AppBar(
        title: Text(isSend ? 'Yeni Cihaz Bağla / Aktar' : 'Başka Cihazdan Hızlı Kurulum'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.wifi_tethering_rounded),
              text: isSend ? 'Aynı Wi-Fi ile Aktar' : 'Aynı Wi-Fi (Otomatik)',
            ),
            Tab(
              icon: const Icon(Icons.qr_code_2_rounded),
              text: 'Aktarım Kodu (Uzaktan)',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          isSend ? _buildSendLanTab() : _buildReceiveLanTab(),
          isSend ? _buildSendTokenTab() : _buildReceiveTokenTab(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI BUILDERS: SEND MODE
  // ---------------------------------------------------------------------------
  Widget _buildSendLanTab() {
    final theme = Theme.of(context);
    final formattedPin = _hostSession != null
        ? '${_hostSession!.pin.substring(0, 3)} ${_hostSession!.pin.substring(3)}'
        : '------';

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: SwitchListTile(
            secondary: const Icon(Icons.key_rounded, color: Colors.blueAccent),
            title: const Text('Kasayı da Kilitsiz Aktar (Önerilen)'),
            subtitle: const Text(
              'Açık olduğunda yeni cihazda uzun Ana Şifrenizi elle yazmanız gerekmez; telefonunuz doğrudan açılır.',
              style: TextStyle(fontSize: 12),
            ),
            value: _includeUnlockedKey,
            onChanged: (val) {
              setState(() => _includeUnlockedKey = val);
              _startLanHost();
            },
          ),
        ),
        const SizedBox(height: 16),

        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: _hostStatus == PairingHostStatus.paired
                  ? Colors.green
                  : Colors.blueAccent.withOpacity(0.5),
              width: 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(
                  _hostStatus == PairingHostStatus.paired
                      ? Icons.check_circle_rounded
                      : Icons.phonelink_setup_rounded,
                  size: 48,
                  color: _hostStatus == PairingHostStatus.paired ? Colors.green : Colors.blueAccent,
                ),
                const SizedBox(height: 12),
                const Text(
                  '6 Haneli Eşleştirme PIN Kodu',
                  style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                if (_isStartingHost)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: SelectableText(
                      formattedPin,
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        letterSpacing: 6,
                        color: Colors.blueAccent,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  _hostStatusMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _hostStatus == PairingHostStatus.paired
                        ? Colors.green
                        : _hostStatus == PairingHostStatus.lockedOut || _hostStatus == PairingHostStatus.expired
                            ? Colors.redAccent
                            : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (_hostSession != null && _hostSession!.localIps.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Otomatik bulunmazsa manuel adres:\nIP: ${_hostSession!.localIps.first}   |   Port: ${_hostSession!.serverPort}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.grey),
                  ),
                ],
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Yeni PIN Kodu Üret'),
                  onPressed: _startLanHost,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(
            children: [
              Icon(Icons.verified_user_outlined, color: Colors.green, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'X25519 Eliptik Eğri Anahtar Değişimi + AES-256-GCM ile korunur. PIN asla ağ üzerinden açık gönderilmez; 3 hatalı denemede otomatik kapanır.',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSendTokenTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Farklı Ağlar İçin Şifreli Kurulum Paketi',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'Telefonunuz mobil verideyse veya farklı Wi-Fi ağındaysanız, tüm bulut ayarlarınızı ve kasa anahtarınızı tek bir şifreli metin paketine dönüştürüp kendinize gönderebilirsiniz.',
          style: TextStyle(fontSize: 13, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _tokenPinController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Aktarım İçin Geçici Şifre / PIN (En az 6 karakter)',
            prefixIcon: Icon(Icons.lock_outline),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _isGeneratingToken ? null : _generateEncryptedToken,
          icon: _isGeneratingToken
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.vpn_key_outlined),
          label: const Text('Şifreli Kurulum Kodunu Oluştur'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.all(14)),
        ),
        if (_generatedToken != null) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blueAccent.withOpacity(0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Şifreli Kurulum Paketi Hazır:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                SelectableText(
                  _generatedToken!,
                  maxLines: 4,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Kodu Kopyala (WhatsApp / Notlar ile Telefona At)'),
                  onPressed: () async {
                    await ClipboardService.copySecurely(_generatedToken!, timeoutSeconds: 120);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Şifreli kurulum kodu kopyalandı! (PIN olmadan kimse çözemez)')),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // UI BUILDERS: RECEIVE MODE
  // ---------------------------------------------------------------------------
  Widget _buildReceiveLanTab() {
    final devices = _discoveredDevices.values.toList();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Aynı Wi-Fi Ağındaki Cihazlar',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Diğer cihazınızda (örn: Mac) MultiPad -> "Yeni Cihaz Bağla" ekranını açın; burada otomatik görünecektir.',
          style: TextStyle(fontSize: 13, color: Colors.grey),
        ),
        const SizedBox(height: 14),

        if (devices.isEmpty)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Row(
                children: [
                  SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Aynı Wi-Fi ağında MultiPad yayını aranıyor...',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...devices.map((dev) {
            final isSelected = _selectedDevice?.sessionId == dev.sessionId && !_showManualIp;
            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isSelected ? Colors.blueAccent : Theme.of(context).colorScheme.outlineVariant,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: ListTile(
                leading: const Icon(Icons.computer_rounded, color: Colors.blueAccent, size: 28),
                title: Text(dev.deviceName, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${dev.ip}:${dev.port}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.blueAccent) : null,
                onTap: () => setState(() {
                  _selectedDevice = dev;
                  _showManualIp = false;
                }),
              ),
            );
          }),

        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: Icon(_showManualIp ? Icons.expand_less : Icons.edit_location_alt_outlined, size: 18),
            label: Text(_showManualIp ? 'Otomatik Listeye Dön' : 'Cihaz çıkmadıysa IP & Port\'u elle gir'),
            onPressed: () => setState(() => _showManualIp = !_showManualIp),
          ),
        ),

        if (_showManualIp) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _manualIpController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Cihaz IP (örn: 192.168.1.35)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _manualPortController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: 16),
        TextField(
          controller: _lanPinController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontFamily: 'monospace', letterSpacing: 8, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(
            labelText: 'Diğer Cihazdaki 6 Haneli PIN',
            hintText: '000000',
            border: OutlineInputBorder(),
          ),
        ),

        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _isConnectingLan ? null : _connectViaLan,
          icon: _isConnectingLan
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.sync_lock_rounded),
          label: const Text('Bağlan ve Tüm Ayarları Aktar', style: TextStyle(fontWeight: FontWeight.bold)),
          style: FilledButton.styleFrom(padding: const EdgeInsets.all(15)),
        ),
      ],
    );
  }

  Widget _buildReceiveTokenTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Şifreli Kurulum Koduyla Aktar',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'Diğer cihazınızda oluşturduğunuz "MPSETUP:..." ile başlayan şifreli kodu buraya yapıştırın ve belirlediğiniz aktarım şifresini girin.',
          style: TextStyle(fontSize: 13, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _pasteTokenController,
          maxLines: 4,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: InputDecoration(
            labelText: 'Aktarım Kodu (MPSETUP:...)',
            alignLabelWithHint: true,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.paste_rounded),
              tooltip: 'Panodan Yapıştır',
              onPressed: () async {
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                if (data?.text != null) {
                  setState(() => _pasteTokenController.text = data!.text!);
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _pastePinController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Aktarım Şifresi / PIN',
            prefixIcon: Icon(Icons.key_rounded),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _isParsingToken ? null : _connectViaToken,
          icon: _isParsingToken
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.download_done_rounded),
          label: const Text('Kodu Çöz ve Kurulumu Tamamla', style: TextStyle(fontWeight: FontWeight.bold)),
          style: FilledButton.styleFrom(padding: const EdgeInsets.all(15)),
        ),
      ],
    );
  }
}
