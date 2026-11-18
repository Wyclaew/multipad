import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'l10n/app_localizations.dart';
import 'providers/auth_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/vault_provider.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'services/native_bridge_service.dart';
import 'services/totp_ticker_service.dart';
import 'widgets/quick_search_dialog.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MultiPadApp());
}

class MultiPadApp extends StatelessWidget {
  final AuthProvider? authProvider;
  final SettingsProvider? settingsProvider;
  final VaultProvider? vaultProvider;
  final Widget? home;

  const MultiPadApp({
    super.key,
    this.authProvider,
    this.settingsProvider,
    this.vaultProvider,
    this.home,
  });

  ThemeData _buildTheme(Brightness brightness, {bool amoled = false}) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: isDark ? Colors.indigoAccent : Colors.indigo,
      brightness: brightness,
      surface: amoled ? Colors.black : null,
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: amoled ? Colors.black : null,
      appBarTheme: amoled
          ? const AppBarTheme(
              backgroundColor: Colors.black,
              surfaceTintColor: Colors.transparent,
            )
          : null,
      cardTheme: CardThemeData(
        elevation: 0,
        color: amoled ? const Color(0xFF0A0A0E) : null,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AuthProvider? inheritedAuth = authProvider;
    if (inheritedAuth == null) {
      try {
        inheritedAuth = Provider.of<AuthProvider>(context, listen: false);
      } catch (_) {}
    }

    SettingsProvider? inheritedSettings = settingsProvider;
    if (inheritedSettings == null) {
      try {
        inheritedSettings =
            Provider.of<SettingsProvider>(context, listen: false);
      } catch (_) {}
    }

    VaultProvider? inheritedVault = vaultProvider;
    if (inheritedVault == null) {
      try {
        inheritedVault = Provider.of<VaultProvider>(context, listen: false);
      } catch (_) {}
    }

    return MultiProvider(
      providers: [
        if (inheritedSettings != null)
          ChangeNotifierProvider<SettingsProvider>.value(
            value: inheritedSettings,
          )
        else
          ChangeNotifierProvider<SettingsProvider>(
            create: (_) => SettingsProvider()..load(),
          ),
        if (inheritedAuth != null)
          ChangeNotifierProvider<AuthProvider>.value(
            value: inheritedAuth,
          )
        else
          ChangeNotifierProvider<AuthProvider>(
            create: (_) => AuthProvider()..checkInitialState(),
          ),
        if (inheritedVault != null)
          ChangeNotifierProvider<VaultProvider>.value(
            value: inheritedVault,
          )
        else
          ChangeNotifierProxyProvider2<AuthProvider, SettingsProvider,
              VaultProvider>(
            create: (context) {
              final auth = context.read<AuthProvider>();
              final settings = context.read<SettingsProvider>();
              return VaultProvider(
                isUnlocked: auth.isUnlocked,
                masterKey: auth.masterKey,
                isDuressMode: auth.isDuressMode,
              )..setAutofillEnabledSetting(settings.autofillEnabled);
            },
            update: (_, auth, settings, previous) {
              final vault = previous ?? VaultProvider();
              vault.setAutofillEnabledSetting(settings.autofillEnabled);
              vault.syncAuthState(
                isUnlocked: auth.isUnlocked,
                masterKey: auth.masterKey,
                isDuressMode: auth.isDuressMode,
              );
              return vault;
            },
          ),
      ],
      child: Consumer2<AuthProvider, SettingsProvider>(
        builder: (context, auth, settings, _) {
          return MaterialApp(
            navigatorKey: rootNavigatorKey,
            title: 'MultiPad',
            debugShowCheckedModeBanner: false,
            themeMode: settings.themeMode,
            theme: _buildTheme(Brightness.light),
            darkTheme: _buildTheme(
              Brightness.dark,
              amoled: settings.isAmoledBlack,
            ),
            locale: settings.locale,
            supportedLocales: const [Locale('tr'), Locale('en')],
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) {
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(
                  textScaler: TextScaler.linear(settings.fontScale),
                ),
                child: VaultLifecycleShell(
                  child: child ?? const SizedBox.shrink(),
                ),
              );
            },
            home: home ??
                (auth.isUnlocked ? const HomeScreen() : const AuthScreen()),
          );
        },
      ),
    );
  }
}

@visibleForTesting
class VaultLifecycleShell extends StatefulWidget {
  final Widget child;
  const VaultLifecycleShell({super.key, required this.child});

  @override
  State<VaultLifecycleShell> createState() => VaultLifecycleShellState();
}

class VaultLifecycleShellState extends State<VaultLifecycleShell>
    with WidgetsBindingObserver {
  Timer? _inactivityTimer;
  int _lastTimeoutMinutes = -1;
  bool _wasUnlocked = false;
  bool _quickSearchDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NativeBridgeService.initialize(
      onQuickSearchRequested: () => _handleQuickSearchRequested(),
      onLockVaultRequested: _handleNativeLockRequested,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthProvider>();
    final settings = context.watch<SettingsProvider>();
    if (_lastTimeoutMinutes != settings.autoLockMinutes ||
        _wasUnlocked != auth.isUnlocked) {
      _lastTimeoutMinutes = settings.autoLockMinutes;
      _wasUnlocked = auth.isUnlocked;
      _resetInactivityTimer();
    }
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _handleNativeLockRequested() {
    if (!mounted) return;
    context.read<AuthProvider>().lockVault(
          reason: 'Sistem tepsisi / menü çubuğundan kilitlendi.',
        );
  }

  Future<void> _handleQuickSearchRequested({
    bool allowPostFrameRetry = true,
  }) async {
    if (!mounted || _quickSearchDialogOpen) return;
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) {
      if (allowPostFrameRetry && mounted && !Platform.environment.containsKey('FLUTTER_TEST')) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _handleQuickSearchRequested(allowPostFrameRetry: false);
          }
        });
      }
      return;
    }
    _quickSearchDialogOpen = true;
    try {
      await showDialog<void>(
        context: ctx,
        builder: (_) => const QuickSearchDialog(),
      );
    } finally {
      _quickSearchDialogOpen = false;
    }
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final minutes = context.read<SettingsProvider>().autoLockMinutes;
    if (!auth.isUnlocked || minutes <= 0) return;

    _inactivityTimer = Timer(Duration(minutes: minutes), () {
      if (!mounted) return;
      final curAuth = context.read<AuthProvider>();
      if (curAuth.isUnlocked && !curAuth.isAutoLockSuppressed) {
        curAuth.lockVault(
          reason: '$minutes dakikalık işlem yapılmama süresi doldu.',
        );
      } else if (curAuth.isUnlocked) {
        _resetInactivityTimer();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final settings = context.read<SettingsProvider>();

    if (state == AppLifecycleState.resumed) {
      TotpTickerService.instance.resume();
      auth.notifyAppResumed();
      _resetInactivityTimer();
    } else if (state == AppLifecycleState.paused ||
               state == AppLifecycleState.hidden) {
      TotpTickerService.instance.pause();
    }

    // Only lock on true backgrounding (paused / hidden), NOT inactive (OS prompts/sheets).
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden) &&
        settings.lockOnBackground &&
        auth.isUnlocked &&
        !auth.isAutoLockSuppressed) {
      auth.lockVault(reason: 'Uygulama arka plana alındığı için kilitlendi.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetInactivityTimer(),
      onPointerMove: (_) => _resetInactivityTimer(),
      child: Focus(
        onKeyEvent: (_, __) {
          _resetInactivityTimer();
          return KeyEventResult.ignored;
        },
        child: widget.child,
      ),
    );
  }
}
