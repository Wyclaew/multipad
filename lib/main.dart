import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'constants.dart';
import 'l10n/app_localizations.dart';
import 'providers/auth_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/vault_provider.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/splash_screen.dart';
import 'services/browser_bridge_service.dart';
import 'services/native_bridge_service.dart';
import 'services/pending_capture_coordinator.dart';
import 'services/totp_ticker_service.dart';
import 'widgets/desktop_title_bar.dart';
import 'widgets/quick_search_dialog.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MultiPadApp(showSplash: true));
}

class MultiPadApp extends StatelessWidget {
  final AuthProvider? authProvider;
  final SettingsProvider? settingsProvider;
  final VaultProvider? vaultProvider;
  final Widget? home;
  final bool showSplash;

  const MultiPadApp({
    super.key,
    this.authProvider,
    this.settingsProvider,
    this.vaultProvider,
    this.home,
    this.showSplash = false,
  });

  ThemeData _buildTheme(Brightness brightness, {bool amoled = false}) {
    final isDark = brightness == Brightness.dark;

    final primaryColor = isDark
        ? AppThemeConstants.indigoDark
        : AppThemeConstants.indigoLight;
    final secondaryColor = isDark
        ? AppThemeConstants.slateDark
        : AppThemeConstants.slateLight;

    final Color surfaceColor;
    final Color surfaceLowest;
    final Color surfaceLow;
    final Color surfaceContainer;
    final Color surfaceHigh;
    final Color surfaceHighest;
    final Color outlineVariantColor;
    final Color scaffoldBg;

    if (amoled) {
      surfaceColor = AppThemeConstants.amoledSurface;
      surfaceLowest = AppThemeConstants.amoledSurfaceContainerLowest;
      surfaceLow = AppThemeConstants.amoledSurfaceContainerLow;
      surfaceContainer = AppThemeConstants.amoledSurfaceContainer;
      surfaceHigh = AppThemeConstants.amoledSurfaceContainerHigh;
      surfaceHighest = AppThemeConstants.amoledSurfaceContainerHighest;
      outlineVariantColor = AppThemeConstants.amoledOutlineVariant;
      scaffoldBg = AppThemeConstants.amoledBg;
    } else if (isDark) {
      surfaceColor = AppThemeConstants.darkSurface;
      surfaceLowest = AppThemeConstants.darkSurfaceContainerLowest;
      surfaceLow = AppThemeConstants.darkSurfaceContainerLow;
      surfaceContainer = AppThemeConstants.darkSurfaceContainer;
      surfaceHigh = AppThemeConstants.darkSurfaceContainerHigh;
      surfaceHighest = AppThemeConstants.darkSurfaceContainerHighest;
      outlineVariantColor = AppThemeConstants.darkOutlineVariant;
      scaffoldBg = AppThemeConstants.darkBg;
    } else {
      surfaceColor = AppThemeConstants.lightSurface;
      surfaceLowest = AppThemeConstants.lightSurfaceContainerLowest;
      surfaceLow = AppThemeConstants.lightSurfaceContainerLow;
      surfaceContainer = AppThemeConstants.lightSurfaceContainer;
      surfaceHigh = AppThemeConstants.lightSurfaceContainerHigh;
      surfaceHighest = AppThemeConstants.lightSurfaceContainerHighest;
      outlineVariantColor = AppThemeConstants.lightOutlineVariant;
      scaffoldBg = AppThemeConstants.lightBg;
    }

    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: brightness,
      primary: primaryColor,
      secondary: secondaryColor,
      surface: surfaceColor,
      surfaceContainerLowest: surfaceLowest,
      surfaceContainerLow: surfaceLow,
      surfaceContainer: surfaceContainer,
      surfaceContainerHigh: surfaceHigh,
      surfaceContainerHighest: surfaceHighest,
      outlineVariant: outlineVariantColor,
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scaffoldBg,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: outlineVariantColor.withValues(alpha: 0.55),
            width: 0.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.only(bottom: 10),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceLow,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: outlineVariantColor.withValues(alpha: 0.6),
            width: 0.8,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: outlineVariantColor.withValues(alpha: 0.6),
            width: 0.8,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColor, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error, width: 1.0),
        ),
        hintStyle: TextStyle(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          fontSize: 14,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: amoled ? AppThemeConstants.amoledSurfaceContainerLow : surfaceColor,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: outlineVariantColor.withValues(alpha: 0.4),
            width: 0.5,
          ),
        ),
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 14,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: amoled ? AppThemeConstants.amoledSurfaceContainerLow : surfaceColor,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: amoled ? AppThemeConstants.amoledSurfaceContainerLow : surfaceColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        clipBehavior: Clip.antiAlias,
        showDragHandle: true,
        dragHandleColor: outlineVariantColor,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceLow,
        selectedColor: colorScheme.primaryContainer,
        side: BorderSide(
          color: outlineVariantColor.withValues(alpha: 0.5),
          width: 0.5,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurface,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: outlineVariantColor),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: outlineVariantColor.withValues(alpha: 0.4),
        thickness: 0.5,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: amoled ? Colors.black : surfaceLow,
        indicatorColor: colorScheme.primaryContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
          );
        }),
      ),
      textTheme: TextTheme(
        headlineMedium: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        titleLarge: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleMedium: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        titleSmall: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 15,
        ),
        bodyMedium: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 14,
        ),
        bodySmall: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
        labelLarge: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
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
              final isDesktop = NativeBridgeService.isDesktopPlatform;

              return MediaQuery(
                data: media.copyWith(
                  textScaler: TextScaler.linear(settings.fontScale),
                ),
                child: VaultLifecycleShell(
                  child: isDesktop
                      ? Scaffold(
                          body: Column(
                            children: [
                              const DesktopTitleBar(),
                              Expanded(
                                child: child ?? const SizedBox.shrink(),
                              ),
                            ],
                          ),
                        )
                      : (child ?? const SizedBox.shrink()),
                ),
              );
            },
            home: home ??
                (showSplash
                    ? SplashScreen(
                        nextScreen: auth.isUnlocked
                            ? const HomeScreen()
                            : const AuthScreen(),
                      )
                    : (auth.isUnlocked
                        ? const HomeScreen()
                        : const AuthScreen())),
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
  BrowserBridgeService? _browserBridge;

  BrowserBridgeService? get browserBridge => _browserBridge;

  void _initBrowserBridge() {
    if (_browserBridge != null) return;
    _browserBridge = BrowserBridgeService(
      isUnlocked: () {
        if (!mounted) return false;
        return context.read<AuthProvider>().isUnlocked;
      },
      getItems: () {
        if (!mounted) return [];
        return context.read<VaultProvider>().items;
      },
      onSaveItem: (item) async {
        if (!mounted) return;
        await context.read<VaultProvider>().saveItem(item);
      },
    );
    BrowserBridgeService.instance = _browserBridge;
    _browserBridge!.start().catchError((e) {
      debugPrint('BrowserBridgeService startup notice: $e');
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NativeBridgeService.initialize(
      onQuickSearchRequested: () => _handleQuickSearchRequested(),
      onLockVaultRequested: _handleNativeLockRequested,
    );
    if ((Platform.isMacOS || Platform.isWindows) &&
        !Platform.environment.containsKey('FLUTTER_TEST')) {
      _initBrowserBridge();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthProvider>();
    final settings = context.watch<SettingsProvider>();
    if (_lastTimeoutMinutes != settings.autoLockMinutes ||
        _wasUnlocked != auth.isUnlocked) {
      if (_wasUnlocked && !auth.isUnlocked) {
        rootNavigatorKey.currentState?.popUntil((route) => route.isFirst);
      }
      final bool justUnlocked = !_wasUnlocked && auth.isUnlocked;
      _lastTimeoutMinutes = settings.autoLockMinutes;
      _wasUnlocked = auth.isUnlocked;
      _resetInactivityTimer();

      if (justUnlocked) {
        final ctx = rootNavigatorKey.currentContext;
        if (ctx != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (ctx.mounted) {
              PendingCaptureCoordinator.checkAndShow(ctx);
            }
          });
        }
      }
    }

  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _browserBridge?.stop();
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
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null) {
        PendingCaptureCoordinator.checkAndShow(ctx);
      }
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
