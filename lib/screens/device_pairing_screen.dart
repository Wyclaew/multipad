import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../services/clipboard_service.dart';
import '../services/native_bridge_service.dart';
import '../services/pairing_service.dart';
import '../widgets/qr_scanner_dialog.dart';

enum PairingRole {
  send,
  receive,
}

class DevicePairingScreen extends StatefulWidget {
  final PairingRole initialRole;

  const DevicePairingScreen({super.key, required this.initialRole});

  @override
  State<DevicePairingScreen> createState() => _DevicePairingScreenState();
}

class _DevicePairingScreenState extends State<DevicePairingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Send (Host) state
  bool _includeUnlockedKey = true;
  PairingHostSession? _hostSession;
  PairingHostStatus _hostStatus = PairingHostStatus.waiting;
  String _hostStatusMessage = '';
  bool _isStartingHost = false;
  String? _generatedToken;
  bool _isGeneratingToken = false;
  Timer? _countdownTimer;
  int _remainingSeconds = 0;

  // Receive (Client) state
  RawDatagramSocket? _discoverySocket;
  Timer? _staleCleanupTimer;
  Timer? _popDelayTimer;
  final Map<String, DiscoveredPairingDevice> _discoveredDevices = {};
  DiscoveredPairingDevice? _selectedDevice;
  final _pinController = TextEditingController();
  final _manualIpController = TextEditingController();
  final _manualPortController = TextEditingController();
  final _tokenInputController = TextEditingController();
  final _tokenPinController = TextEditingController();
  bool _isConnecting = false;
  String? _clientStatusMsg;
  bool _clientSuccess = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (widget.initialRole == PairingRole.send) {
      _startPairingHost();
    } else {
      _startListeningForHosts();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _staleCleanupTimer?.cancel();
    _popDelayTimer?.cancel();
    _hostSession?.stop();
    _discoverySocket?.close();
    NativeBridgeService.setMulticastLock(false);
    _tabController.dispose();
    _pinController.dispose();
    _manualIpController.dispose();
    _manualPortController.dispose();
    _tokenInputController.dispose();
    _tokenPinController.dispose();
    super.dispose();
  }

  // --- HOST LOGIC (EXISTING DEVICE) ---

  Future<void> _startPairingHost() async {
    final auth = context.read<AuthProvider>();
    await _hostSession?.stop();
    _countdownTimer?.cancel();

    if (!mounted) return;
    setState(() {
      _isStartingHost = true;
      _hostStatus = PairingHostStatus.waiting;
      _hostStatusMessage = 'Yerel ağ yayını başlatılıyor...';
    });

    try {
      final pairingService = PairingService(auth.cryptoService);
      final payload = await auth.buildPairingPayload(
        includeUnlockedKey: _includeUnlockedKey,
      );

      final session = await pairingService.startHostSession(
        payload: payload,
        onStatusChanged: (status, message) {
          if (!mounted) return;
          setState(() {
            _hostStatus = status;
            _hostStatusMessage = message;
            if (status == PairingHostStatus.paired) {
              _countdownTimer?.cancel();
            }
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
        _remainingSeconds = session.remainingSeconds;
      });

      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || _hostSession == null) {
          t.cancel();
          return;
        }
        final rem = _hostSession!.remainingSeconds;
        setState(() => _remainingSeconds = rem);
        if (rem <= 0) {
          t.cancel();
          setState(() {
            _hostStatus = PairingHostStatus.expired;
            _hostStatusMessage = 'Eşleştirme kodunun süresi doldu.';
          });
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isStartingHost = false;
        _hostStatus = PairingHostStatus.closed;
        _hostStatusMessage = 'Yerel eşleştirme başlatılamadı: $e';
      });
    }
  }

  Future<void> _generateSetupToken({bool lightweightFallback = false}) async {
    final pin = _tokenPinController.text.trim();
    if (pin.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen en az 6 haneli geçici PIN / şifre belirleyin.'),
        ),
      );
      return;
    }

    setState(() => _isGeneratingToken = true);
    try {
      final auth = context.read<AuthProvider>();
      final pairingService = PairingService(auth.cryptoService);
      var payload = await auth.buildPairingPayload(
        includeUnlockedKey: _includeUnlockedKey,
      );
      if (lightweightFallback) {
        payload = PairingPayload(
          supabaseUrl: payload.supabaseUrl,
          supabaseAnonKey: payload.supabaseAnonKey,
          email: payload.email,
          masterSalt: payload.masterSalt,
          masterKeyBase64: payload.masterKeyBase64,
          offlineItems: const [],
        );
      }
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
        SnackBar(content: Text('Kod oluşturma hatası: $e')),
      );
    }
  }

  // --- CLIENT LOGIC (NEW DEVICE) ---

  Future<void> _startListeningForHosts() async {
    _discoverySocket?.close();
    _staleCleanupTimer?.cancel();
    await NativeBridgeService.setMulticastLock(true);
    _discoverySocket = await PairingService.startDiscoveryListener((device) {
      if (!mounted) return;
      setState(() {
        _discoveredDevices[device.sessionId] = device;
        _selectedDevice ??= device;
      });
    });

    _staleCleanupTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      bool changed = false;
      _discoveredDevices.removeWhere((key, dev) {
        final expired = now.difference(dev.lastSeen).inSeconds > 8;
        if (expired) changed = true;
        return expired;
      });
      if (_selectedDevice != null &&
          !_discoveredDevices.containsKey(_selectedDevice!.sessionId)) {
        _selectedDevice = _discoveredDevices.isNotEmpty
            ? _discoveredDevices.values.first
            : null;
        changed = true;
      }
      if (changed) setState(() {});
    });
  }

  Future<void> _connectToHost({
    List<String>? overrideIps,
    int? overridePort,
    String? overridePin,
  }) async {
    var ips = overrideIps ?? _selectedDevice?.allIps ?? const <String>[];
    var port = overridePort ?? _selectedDevice?.port;
    final pin = overridePin ?? _pinController.text.replaceAll(RegExp(r'\s+'), '');

    if (ips.isEmpty && port == null) {
      var rawIp = _manualIpController.text.trim();
      var rawPort = _manualPortController.text.trim();
      if (rawIp.isNotEmpty) {
        final colonIdx = rawIp.lastIndexOf(':');
        if (rawPort.isEmpty &&
            colonIdx > 0 &&
            colonIdx < rawIp.length - 1 &&
            !rawIp.contains(']')) {
          final parsedHost = rawIp.substring(0, colonIdx).trim();
          final parsedPort = rawIp.substring(colonIdx + 1).trim();
          if (int.tryParse(parsedPort) != null) {
            rawIp = parsedHost;
            rawPort = parsedPort;
          }
        }
        final parsedPort = int.tryParse(rawPort);
        if (parsedPort == null || parsedPort < 1 || parsedPort > 65535) {
          setState(
            () => _clientStatusMsg =
                'Lütfen geçerli bir port numarası (1-65535) girin.',
          );
          return;
        }
        ips = [rawIp];
        port = parsedPort;
      }
    }

    if (ips.isEmpty || port == null) {
      setState(
        () => _clientStatusMsg =
            'Lütfen listeden bir cihaz seçin, QR tarayın ya da IP & Port girin.',
      );
      return;
    }
    if (pin.length != 6) {
      setState(() => _clientStatusMsg = '6 haneli PIN kodunu eksiksiz girin.');
      return;
    }

    setState(() {
      _isConnecting = true;
      _clientStatusMsg = 'Şifreli tünel kuruluyor (${ips.first}:$port)...';
    });

    try {
      final auth = context.read<AuthProvider>();
      final pairingService = PairingService(auth.cryptoService);
      final payload = await pairingService.connectAndPairAny(
        hostIps: ips,
        port: port,
        pin: pin,
      );
      await _applyPairingSuccess(payload);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _clientStatusMsg =
            'Bağlantı başarısız: ${e.toString().replaceAll("Exception: ", "")}';
      });
    }
  }

  Future<void> _scanReceiveQr() async {
    final scanned = await QrScannerDialog.scan(
      context,
      title: 'Cihaz Eşleştirme QR Tarayıcı',
      subtitle:
          'Diğer cihazdaki MultiPad eşleştirme QR kodunu okutun veya ekran görüntüsü seçin.',
    );
    if (scanned == null || scanned.trim().isEmpty || !mounted) return;

    final clean = scanned.trim();
    if (clean.startsWith('MPPAIR:v1:')) {
      final parsed = PairingService.parseQrPairingUri(clean);
      if (parsed == null) {
        setState(() => _clientStatusMsg = 'QR eşleştirme verisi okunamadı.');
        return;
      }
      _pinController.text = parsed.pin;
      _tabController.animateTo(0);
      await _connectToHost(
        overrideIps: parsed.ips,
        overridePort: parsed.port,
        overridePin: parsed.pin,
      );
      return;
    }

    if (clean.startsWith('MPSETUP:')) {
      _tokenInputController.text = clean;
      _tabController.animateTo(1);
      if (_tokenPinController.text.trim().length >= 6) {
        await _applyToken();
      } else {
        setState(() {
          _clientStatusMsg =
              'Aktarım kodu QR ile tarandı! Şimdi geçici şifreyi girip "Kodu Çöz"e dokunun.';
        });
      }
      return;
    }

    setState(() {
      _clientStatusMsg = 'Tanınmayan QR formatı. MPPAIR veya MPSETUP QR kodu okutun.';
    });
  }

  Future<void> _applyToken() async {
    final token = _tokenInputController.text.trim();
    final pin = _tokenPinController.text.trim();
    if (token.isEmpty || pin.isEmpty) {
      setState(() => _clientStatusMsg = 'Aktarım kodunu ve şifresini girin.');
      return;
    }

    setState(() {
      _isConnecting = true;
      _clientStatusMsg = 'Şifreli kurulum paketi çözülüyor...';
    });

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
      setState(() {
        _isConnecting = false;
        _clientStatusMsg =
            'Hata: ${e.toString().replaceAll("Exception: ", "")}';
      });
    }
  }

  Future<void> _applyPairingSuccess(PairingPayload payload) async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.completePairingSetup(payload);
    if (!mounted) return;

    if (ok) {
      final requiresMfa = auth.status == VaultLockStatus.mfaRequired;
      setState(() {
        _isConnecting = false;
        _clientSuccess = true;
        if (requiresMfa) {
          _clientStatusMsg =
              'Eşleştirme başarılı! Devam etmek için 2FA doğrulama kodunu girin.';
        } else if (payload.masterKeyBase64 != null) {
          _clientStatusMsg =
              'Eşleştirme başarılı! Kasanız açıldı ve veriler aktarıldı.';
        } else {
          _clientStatusMsg =
              'Hesap yapılandırması aktarıldı! Şimdi ana parolanızla giriş yapabilirsiniz.';
        }
      });
      _popDelayTimer?.cancel();
      _popDelayTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted && (ModalRoute.of(context)?.isCurrent ?? true)) {
          Navigator.of(context).pop(true);
        }
      });
    } else {
      setState(() {
        _isConnecting = false;
        _clientStatusMsg =
            auth.errorMessage ?? 'Eşleştirme kurulumu uygulanamadı.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isSend = widget.initialRole == PairingRole.send;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isSend
              ? l10n.tr('Başka Cihaza Bağlan / Paylaş', 'Pair New Device')
              : l10n.tr('Mevcut Cihazdan Eşleştir', 'Receive From Existing Device'),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.wifi),
              text: l10n.tr('Aynı Ağ (PIN / QR)', 'Local Network'),
            ),
            Tab(
              icon: const Icon(Icons.qr_code_2),
              text: l10n.tr('Aktarım Kodu', 'Transfer Token'),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          isSend ? _buildHostLanTab() : _buildClientLanTab(),
          isSend ? _buildHostTokenTab() : _buildClientTokenTab(),
        ],
      ),
    );
  }

  Widget _buildHostLanTab() {
    final theme = Theme.of(context);
    final pinFormatted = _hostSession != null
        ? '${_hostSession!.pin.substring(0, 3)} ${_hostSession!.pin.substring(3)}'
        : '--- ---';
    final qrData = _hostSession?.buildQrPairingUri();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: SwitchListTile(
                title: const Text('Kilidi Açık Kasayı Dahil Et (Önerilen)'),
                subtitle: const Text(
                  'Yeni cihazda ana parolayı tekrar yazmadan oturumu ve kasayı anında açar.',
                ),
                value: _includeUnlockedKey,
                onChanged: (val) {
                  setState(() => _includeUnlockedKey = val);
                  _startPairingHost();
                },
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _hostStatus == PairingHostStatus.paired
                    ? Colors.green.withValues(alpha: 0.14)
                    : theme.colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.4,
                      ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _hostStatus == PairingHostStatus.paired
                      ? Colors.green
                      : Colors.indigoAccent.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    _hostStatus == PairingHostStatus.paired
                        ? Icons.check_circle
                        : Icons.wifi_tethering,
                    size: 46,
                    color: _hostStatus == PairingHostStatus.paired
                        ? Colors.green
                        : Colors.indigoAccent,
                  ),
                  const SizedBox(height: 10),
                  if (_isStartingHost)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    )
                  else ...[
                    Text(
                      'Eşleştirme PIN Kodu',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      pinFormatted,
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 6,
                        fontFamily: 'monospace',
                      ),
                    ),
                    if (_hostStatus == PairingHostStatus.waiting) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Kalan süre: $_remainingSeconds saniye',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.amber,
                        ),
                      ),
                    ],
                    if (qrData != null &&
                        _hostStatus == PairingHostStatus.waiting) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: QrImageView(
                          data: qrData,
                          size: 165,
                          backgroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Telefonunuzda "QR Kod Tara"ya basarak anında bağlanabilirsiniz.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: theme.hintColor),
                      ),
                    ],
                    if (_hostSession != null &&
                        _hostSession!.localIps.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Ağ IP: ${_hostSession!.localIps.join(", ")}:${_hostSession!.serverPort ?? ""}',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: theme.hintColor),
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),
                  Text(
                    _hostStatusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: _hostStatus == PairingHostStatus.paired
                          ? Colors.green
                          : (_hostStatus == PairingHostStatus.lockedOut ||
                                    _hostStatus == PairingHostStatus.expired
                                ? Colors.redAccent
                                : theme.hintColor),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_hostStatus == PairingHostStatus.paired)
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Tamamlandı'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: _isStartingHost ? null : _startPairingHost,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Yeni PIN & QR Oluştur'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHostTokenTab() {
    final theme = Theme.of(context);
    final canQr = _generatedToken != null && _generatedToken!.length <= 2200;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Ağlarınız farklıysa veya Wi-Fi eşleştirmesi engelleniyorsa, şifreli aktarım kodu üretip yeni cihaza QR/kopyala ile aktarabilirsiniz.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _tokenPinController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Tek Kullanımlık Koruma Şifresi (en az 6 hane)',
                prefixIcon: Icon(Icons.password),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isGeneratingToken
                        ? null
                        : () => _generateSetupToken(lightweightFallback: false),
                    icon: _isGeneratingToken
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.enhanced_encryption),
                    label: const Text('Tam Kurulum Kodu Üret'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _isGeneratingToken
                      ? null
                      : () => _generateSetupToken(lightweightFallback: true),
                  child: const Text('Hafif QR'),
                ),
              ],
            ),
            if (_generatedToken != null) ...[
              const SizedBox(height: 16),
              if (canQr)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: QrImageView(
                      data: _generatedToken!,
                      size: 190,
                      backgroundColor: Colors.white,
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Tam kasa verisi QR kod sınırını aştığı için metin kodu üretildi (QR için "Hafif QR" seçeneğini kullanabilirsiniz).',
                    style: TextStyle(fontSize: 12, color: theme.hintColor),
                  ),
                ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  _generatedToken!,
                  maxLines: 5,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  await ClipboardService.copySecurely(
                    _generatedToken!,
                    timeoutSeconds: 120,
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Aktarım kodu kopyalandı (120 sn sonra panodan temizlenir).',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.copy),
                label: const Text('Aktarım Kodunu Kopyala'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildClientLanTab() {
    final theme = Theme.of(context);
    final devices = _discoveredDevices.values.toList();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            FilledButton.tonalIcon(
              onPressed: _isConnecting ? null : _scanReceiveQr,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('QR Kod Tara ve Otomatik Eşleştir'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  'Aynı Ağda Bulunan Cihazlar',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _startListeningForHosts,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Yenile'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (devices.isEmpty)
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text(
                      'Aynı ağdaki MultiPad cihazları dinleniyor...\nCihaz görünmüyorsa yukarıdaki QR Kod Tara butonunu veya Aktarım Kodu sekmesini kullanın.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              )
            else
              ...devices.map((dev) {
                final selected = _selectedDevice?.sessionId == dev.sessionId;
                return Card(
                  color: selected
                      ? Colors.indigoAccent.withValues(alpha: 0.14)
                      : null,
                  child: ListTile(
                    leading: Icon(
                      Icons.devices,
                      color: selected ? Colors.indigoAccent : null,
                    ),
                    title: Text(dev.deviceName),
                    subtitle: Text('${dev.allIps.join(", ")}:${dev.port}'),
                    trailing: selected
                        ? const Icon(Icons.check_circle, color: Colors.indigoAccent)
                        : null,
                    onTap: () => setState(() => _selectedDevice = dev),
                  ),
                );
              }),
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text(
                'Cihaz görünmüyorsa IP & Port ile manuel bağlan',
                style: TextStyle(fontSize: 13),
              ),
              children: [
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _manualIpController,
                        onChanged: (_) {
                          if (_selectedDevice != null) {
                            setState(() => _selectedDevice = null);
                          }
                        },
                        decoration: const InputDecoration(
                          labelText: 'Diğer Cihazın IP Adresi',
                          hintText: 'Örn: 192.168.1.42',
                          prefixIcon: Icon(Icons.lan),
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
                          hintText: 'Örn: 54321',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                letterSpacing: 6,
                fontWeight: FontWeight.bold,
              ),
              decoration: const InputDecoration(
                labelText: 'Diğer Cihazdaki 6 Haneli PIN',
                counterText: '',
              ),
            ),
            if (_clientStatusMsg != null) ...[
              const SizedBox(height: 12),
              Text(
                _clientStatusMsg!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _clientSuccess ? Colors.green : Colors.orangeAccent,
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _isConnecting ? null : () => _connectToHost(),
              icon: _isConnecting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link),
              label: const Text('Eşleştir ve Kasayı Aktar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClientTokenTab() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            FilledButton.tonalIcon(
              onPressed: _isConnecting ? null : _scanReceiveQr,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Aktarım QR Kodunu Tara'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _tokenInputController,
              maxLines: 5,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: InputDecoration(
                labelText: 'MPSETUP:... Aktarım Kodu',
                alignLabelWithHint: true,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.paste),
                  tooltip: 'Panodan Yapıştır',
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    final text = data?.text?.trim();
                    if (text != null && text.isNotEmpty && mounted) {
                      _tokenInputController.text = text;
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tokenPinController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Koruma Şifresi (en az 6 hane)',
                prefixIcon: Icon(Icons.password),
              ),
            ),
            if (_clientStatusMsg != null) ...[
              const SizedBox(height: 12),
              Text(
                _clientStatusMsg!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _clientSuccess ? Colors.green : Colors.orangeAccent,
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _isConnecting ? null : _applyToken,
              icon: _isConnecting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_done),
              label: const Text('Kodu Çöz ve Kurulumu Tamamla'),
            ),
          ],
        ),
      ),
    );
  }
}
