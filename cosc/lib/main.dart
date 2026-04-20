import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/supabase_service.dart';
import 'services/signaling_service.dart';
import 'services/pairing_service.dart';
import 'services/webrtc_service.dart';
import 'utils/local_storage_service.dart';
import 'providers/connection_state.dart';
import 'providers/app_settings.dart';
import 'screens/device_setup_screen.dart';
import 'screens/pairing_request_screen.dart';
import 'screens/pairing_confirmation_screen.dart';
import 'screens/device_list_screen.dart';
import 'screens/room_screen.dart';
import 'screens/webrtc_call_screen.dart';
import 'screens/screen_share_screen.dart';
import 'screens/settings_screen.dart';

const String supabaseUrl = 'YOUR_SUPABASE_URL';
const String supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Hive for local storage
  await LocalStorageService.initialize();
  
  // Initialize Supabase
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );
  
  runApp(const CooperatingScreenApplication());
}

class CooperatingScreenApplication extends StatelessWidget {
  const CooperatingScreenApplication({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SupabaseService>(
          create: (_) => SupabaseService(),
        ),
        Provider<SignalingService>(
          create: (_) => SignalingService(
            serverUrl: 'ws://localhost:3000', // Update with actual server URL
          ),
        ),
        Provider<PairingService>(
          create: (_) => PairingService(),
        ),
        ChangeNotifierProvider<ConnectionState>(
          create: (_) => ConnectionState(),
        ),
        ChangeNotifierProvider<AppSettings>(
          create: (_) => AppSettings(),
        ),
      ],
      child: Consumer<AppSettings>(
        builder: (context, settings, _) {
          return MaterialApp(
            title: 'Cooperating Screen',
            theme: ThemeData(
              primarySwatch: Colors.blue,
              useMaterial3: true,
              brightness: Brightness.light,
            ),
            darkTheme: ThemeData(
              primarySwatch: Colors.blue,
              useMaterial3: true,
              brightness: Brightness.dark,
            ),
            themeMode: _getThemeModeFromSettings(settings.themeMode),
            home: const AuthWrapper(),
            routes: {
              '/home': (context) => const HomeScreen(),
              '/setup': (context) => const DeviceSetupScreen(),
              '/pairing-request': (context) => const PairingRequestScreen(),
              '/pairing-confirm': (context) => const PairingConfirmationScreen(),
              '/devices': (context) => const DeviceListScreen(),
              '/room': (context) => const RoomScreen(),
              '/webrtc-call': (context) => const WebRTCCallScreen(
                remoteDeviceName: 'Remote Device',
                remoteDeviceSerial: 'SERIAL123',
              ),
              '/screen-share': (context) => const ScreenShareScreen(
                remoteDeviceName: 'Remote Device',
                remoteDeviceSerial: 'SERIAL123',
              ),
              '/settings': (context) => const SettingsScreen(),
            },
          );
        },
      ),
    );
  }

  ThemeMode _getThemeModeFromSettings(ThemeMode settingsMode) {
    switch (settingsMode) {
      case ThemeMode.light:
        return ThemeMode.light;
      case ThemeMode.dark:
        return ThemeMode.dark;
      case ThemeMode.system:
        return ThemeMode.system;
    }
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final supabaseService = context.read<SupabaseService>();
    
    return FutureBuilder(
      future: supabaseService.isDeviceRegistered(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        
        if (snapshot.hasData && snapshot.data == true) {
          return const HomeScreen();
        }
        
        return const DeviceSetupScreen();
      },
    );
  }
}
