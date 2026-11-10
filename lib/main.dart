import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/vault_provider.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MultiPadApp());
}

class MultiPadApp extends StatelessWidget {
  const MultiPadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider()..checkInitialState(),
        ),
        ChangeNotifierProxyProvider<AuthProvider, VaultProvider>(
          create: (context) {
            final auth = context.read<AuthProvider>();
            return VaultProvider(
              cryptoService: auth.cryptoService,
              supabaseService: auth.supabaseService,
            );
          },
          update: (_, auth, vault) {
            vault!.syncAuthState(
              isUnlocked: auth.isUnlocked,
              masterKey: auth.masterKey,
            );
            return vault;
          },
        ),
      ],
      child: MaterialApp(
        title: 'MultiPad',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.system,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.blueAccent,
          brightness: Brightness.light,
          cardTheme: const CardThemeData(elevation: 0),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.blueAccent,
          brightness: Brightness.dark,
          cardTheme: const CardThemeData(elevation: 0),
        ),
        home: const AppRootRouter(),
      ),
    );
  }
}

class AppRootRouter extends StatelessWidget {
  const AppRootRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (auth.isUnlocked) {
      return const HomeScreen();
    } else {
      return const AuthScreen();
    }
  }
}
