import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:collection/collection.dart';
import 'package:flutter_android_launcher/flutter_android_launcher.dart';
import 'dart:convert';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<Map<String, String>> _installedApps = [];
  List<Map<String, String>> _userProfiles = [];
  final Map<String, Uint8List> _iconCache = {};
  String _quietModeStatus = 'Enabled';
  String? _privateProfile;
  Map<int, Offset> _positions = {};

  final _flutterAndroidLauncherPlugin = FlutterAndroidLauncher();

  Future<void> _getInstalledApps() async {
    List<Map<String, String>> installedApps;
    try {
      installedApps = await _flutterAndroidLauncherPlugin.getInstalledApps();
      // Filter in  only Play Store
      installedApps =
          installedApps
              .where((app) => app['packageName'] == 'com.android.vending')
              .toList();
    } on PlatformException catch (e) {
      installedApps = [
        {
          'appName': 'Error',
          'packageName': "Failed to get installed apps: '${e.message}'.",
          'profile': 'N/A',
          'iconBase64': '',
        },
      ];
    }

    setState(() {
      _installedApps = installedApps;
      for (var app in installedApps) {
        final iconBase64 = app['iconBase64']!;
        if (!_iconCache.containsKey(iconBase64)) {
          _iconCache[iconBase64] = base64Decode(iconBase64);
        }
      }
    });
  }

  Future<void> _launchApp(String packageName, String profile) async {
    try {
      await _flutterAndroidLauncherPlugin.launchApp(packageName, profile);
    } on PlatformException catch (e) {
      print("Failed to launch app: '${e.message}'.");
    }
  }

  Future<void> _getLauncherUserInfo() async {
    try {
      final userProfiles =
          await _flutterAndroidLauncherPlugin.getLauncherUserInfo();
      setState(() {
        _userProfiles = userProfiles;
        for (var profile in userProfiles) {
          print(
            'UserProfile: ${profile['userProfile']}, UserType: ${profile['userType']}',
          );
        }

        _privateProfile =
            userProfiles.firstWhereOrNull(
              (profile) =>
                  profile['userType'] == 'android.os.usertype.profile.PRIVATE',
            )?['userProfile'];
        print('Private profile: $_privateProfile');
      });
    } on PlatformException catch (e) {
      setState(() {
        _userProfiles = [
          {
            'userProfile': 'Error',
            'userType': "Failed to get user info: '${e.message}'",
          },
        ];
      });
    }
  }

  Future<void> _checkQuietMode(String profile) async {
    try {
      final result = await _flutterAndroidLauncherPlugin.isQuietModeEnabled(
        profile,
      );
      setState(() {
        _quietModeStatus = result ? 'Enabled' : 'Disabled';
      });
    } on PlatformException catch (e) {
      setState(() {
        _quietModeStatus = "Failed to check quiet mode: '${e.message}'";
      });
    }
  }

  Future<void> _toggleQuietMode(String profile) async {
    try {
      final enableQuietMode = _quietModeStatus == 'Disabled';
      await _flutterAndroidLauncherPlugin.requestQuietModeEnabled(
        enableQuietMode,
        profile,
      );
    } on PlatformException catch (e) {
      setState(() {
        _quietModeStatus = "Failed to toggle quiet mode: '${e.message}'";
      });
    }
  }

  @override
  void initState() {
    _getInstalledApps();
    _getLauncherUserInfo().then((_) {
      if (_privateProfile != null) {
        _checkQuietMode(_privateProfile!);
      }
    });
    _flutterAndroidLauncherPlugin.setMethodCallHandler((
      FlutterAndroidLauncherMethodCall call,
    ) async {
      if (call.method == "updateQuietModeStatus") {
        final isQuietModeEnabled = call.arguments as bool;
        setState(() {
          _quietModeStatus = isQuietModeEnabled ? 'Enabled' : 'Disabled';
        });
      }
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,

      body: SafeArea(
        child: Center(
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white),
            child: Column(
              children: [
                if (_privateProfile != null)
                  Text('Quiet Mode: $_quietModeStatus'),
                _userProfiles.isEmpty
                    ? const CircularProgressIndicator()
                    : const SizedBox(),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ...List.generate(_installedApps.length, (index) {
                            final app = _installedApps[index];
                            final iconBase64 = app['iconBase64']!;
                            final iconWidget =
                                _iconCache.containsKey(iconBase64)
                                    ? Image.memory(_iconCache[iconBase64]!)
                                    : Image.memory(base64Decode(iconBase64));
                            final position =
                                _positions[index] ??
                                Offset(
                                  (index % 4) * 90.0,
                                  (index ~/ 4) * 100.0,
                                );

                            return Positioned(
                              left: position.dx,
                              top: position.dy,
                              child: Draggable<int>(
                                data: index,
                                feedback: Material(
                                  color: Colors.transparent,
                                  child: _buildAppIcon(
                                    iconWidget,
                                    app['appName'],
                                  ),
                                ),
                                childWhenDragging: const Opacity(
                                  opacity: 0.3,
                                  child: Icon(Icons.apps, size: 48),
                                ),
                                onDraggableCanceled: (velocity, offset) {
                                  setState(() {
                                    _positions[index] = offset;
                                  });
                                },
                                child: GestureDetector(
                                  onTap:
                                      () => _launchApp(
                                        app['packageName']!,
                                        app['profile']!,
                                      ),
                                  child: _buildAppIcon(
                                    iconWidget,
                                    app['appName'],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      );
                    },
                  ),
                ),

                if (_privateProfile != null)
                  ElevatedButton(
                    onPressed: () => _toggleQuietMode(_privateProfile!),
                    child: Text(
                      _quietModeStatus == 'Enabled'
                          ? 'Disable Quiet Mode'
                          : 'Enable Quiet Mode',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppIcon(Image iconWidget, String? name) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 48, height: 48, child: iconWidget),
        const SizedBox(height: 4),
        Text(
          name ?? '',
          style: const TextStyle(color: Colors.white, fontSize: 12),
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
