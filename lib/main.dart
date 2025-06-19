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

  void _showAllAppsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.purple.shade300,

      isScrollControlled: true,
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          expand: false,
          builder: (context, scrollController) {
            return GridView.builder(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.75,
              ),
              itemCount: _installedApps.length,
              itemBuilder: (context, index) {
                final app = _installedApps[index];
                final iconBase64 = app['iconBase64']!;
                final iconWidget =
                    _iconCache.containsKey(iconBase64)
                        ? Image.memory(_iconCache[iconBase64]!)
                        : Image.memory(base64Decode(iconBase64));
                return GestureDetector(
                  onTap: () => _launchApp(app['packageName']!, app['profile']!),
                  child: _buildAppIcon(iconWidget, app['appName']),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  @override
  void initState() {
    super.initState();
    _getInstalledApps();
    _getLauncherUserInfo().then((_) {
      if (_privateProfile != null) {
        _checkQuietMode(_privateProfile!);
      }
    });
    _flutterAndroidLauncherPlugin.setMethodCallHandler((call) async {
      if (call.method == "updateQuietModeStatus") {
        final isQuietModeEnabled = call.arguments as bool;
        setState(() {
          _quietModeStatus = isQuietModeEnabled ? 'Enabled' : 'Disabled';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final playStoreApp = _installedApps.firstWhereOrNull(
      (app) => app['packageName'] == 'com.android.vending',
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            if (_privateProfile != null)
              Text(
                'Quiet Mode: $_quietModeStatus',
                style: const TextStyle(color: Colors.white),
              ),
            Expanded(
              child:
                  playStoreApp == null
                      ? const Center(child: CircularProgressIndicator())
                      : LayoutBuilder(
                        builder: (context, constraints) {
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              // Only show the Play Store icon with drag-and-drop
                              ...List.generate(1, (index) {
                                final iconBase64 = playStoreApp!['iconBase64']!;
                                final iconWidget =
                                    _iconCache.containsKey(iconBase64)
                                        ? Image.memory(_iconCache[iconBase64]!)
                                        : Image.memory(
                                          base64Decode(iconBase64),
                                        );
                                final position =
                                    _positions[index] ?? const Offset(100, 200);

                                return Positioned(
                                  left: position.dx,
                                  top: position.dy,
                                  child: Draggable<int>(
                                    data: index,
                                    feedback: Material(
                                      color: Colors.transparent,
                                      child: _buildAppIcon(
                                        iconWidget,
                                        playStoreApp!['appName'],
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
                                            playStoreApp!['packageName']!,
                                            playStoreApp!['profile']!,
                                          ),
                                      child: _buildAppIcon(
                                        iconWidget,
                                        playStoreApp!['appName'],
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

            InkWell(
              onTap: () => _showAllAppsBottomSheet(context),
              child: Container(
                height: 60,
                color: Colors.white10,
                alignment: Alignment.center,
                child: const Text(
                  'Tap Here to View All Apps',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppIcon(Image iconWidget, String? name) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 64, height: 64, child: iconWidget),
        const SizedBox(height: 6),
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
