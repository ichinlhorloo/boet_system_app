import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:io';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    print('Background message: ${message.notification?.title}');
  } catch (e) {
    print('Background handler error: $e');
  }
}

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  bool firebaseInitialized = false;

  // Firebase эхлүүлэх
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    firebaseInitialized = true;
    print('✅ Firebase initialized');
  } catch (e) {
    print('⚠️ Firebase initialization failed: $e');
  }

  // Notification тохируулах
  if (firebaseInitialized) {
    try {
      const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
      );

      await flutterLocalNotificationsPlugin.initialize(initializationSettings);

      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'high_importance_channel',
        'High Importance Notifications',
        description: 'This channel is used for important notifications.',
        importance: Importance.high,
      );

      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
      flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation != null) {
        await androidImplementation.createNotificationChannel(channel);
      }
      print('✅ Notifications initialized');
    } catch (e) {
      print('⚠️ Notification initialization failed: $e');
    }
  }

  print('🚀 Starting app...');
  runApp(BoetSystemApp(firebaseEnabled: firebaseInitialized));
}

class BoetSystemApp extends StatelessWidget {
  final bool firebaseEnabled;

  const BoetSystemApp({Key? key, required this.firebaseEnabled}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BOET System',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: WebViewScreen(firebaseEnabled: firebaseEnabled),
      debugShowCheckedModeBanner: false,
    );
  }
}

class WebViewScreen extends StatefulWidget {
  final bool firebaseEnabled;

  const WebViewScreen({Key? key, required this.firebaseEnabled}) : super(key: key);

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  InAppWebViewController? webViewController;
  PullToRefreshController? pullToRefreshController;
  double progress = 0;
  String? fcmToken;
  Timer? _periodicTimer;
  bool _tokenSent = false;

  // Native Method Channel - Android DownloadManager-тай холбох
  static const platform = MethodChannel('com.boetsystem.app/download');

  @override
  void initState() {
    super.initState();
    print('🔧 WebViewScreen initState');
    _initializePullToRefresh();
    if (widget.firebaseEnabled) {
      _initializeFirebaseMessaging();
    }
  }

  @override
  void dispose() {
    _periodicTimer?.cancel();
    super.dispose();
  }

  void _initializePullToRefresh() {
    pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(color: Colors.blue),
      onRefresh: () async {
        webViewController?.reload();
      },
    );
  }

  void _initializeFirebaseMessaging() async {
    try {
      fcmToken = await FirebaseMessaging.instance.getToken();
      print('🔑 FCM Token: $fcmToken');

      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('📨 Foreground message received');
        if (message.notification != null) {
          _showNotification(
            message.notification!.title ?? 'Notification',
            message.notification!.body ?? '',
          );
        }
      });

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print('🔔 Notification clicked');
        if (message.data['url'] != null) {
          webViewController?.loadUrl(
              urlRequest: URLRequest(url: WebUri(message.data['url']))
          );
        }
      });

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        print('🔄 Token refreshed');
        fcmToken = newToken;
        _tokenSent = false;
        _checkAndSendToken();
      });
    } catch (e) {
      print('⚠️ Firebase messaging initialization error: $e');
    }
  }

  void _startPeriodicCheck() {
    _periodicTimer?.cancel();

    if (!_tokenSent && widget.firebaseEnabled) {
      _periodicTimer = Timer.periodic(Duration(seconds: 3), (timer) {
        _checkAndSendToken();
      });
    }
  }

  Future<void> _checkAndSendToken() async {
    try {
      if (_tokenSent || !widget.firebaseEnabled) return;
      if (webViewController == null || fcmToken == null) return;

      var result = await webViewController!.evaluateJavascript(
          source: """
          (function() {
            if (sessionStorage.getItem('username')) {
              return sessionStorage.getItem('username');
            }
            if (localStorage.getItem('username')) {
              return localStorage.getItem('username');
            }
            return null;
          })()
        """
      );

      if (result != null &&
          result.toString() != 'null' &&
          result.toString() != '""' &&
          result.toString().trim().isNotEmpty) {

        String username = result.toString()
            .replaceAll('"', '')
            .replaceAll("'", '')
            .trim();

        if (username.isNotEmpty && username != 'null') {
          print('✅ Username found: $username');
          await _sendTokenToBackend(fcmToken!, username);
          _tokenSent = true;
          _periodicTimer?.cancel();
        }
      }
    } catch (e) {
      print('⚠️ Error in _checkAndSendToken: $e');
    }
  }

  Future<void> _sendTokenToBackend(String token, String username) async {
    try {
      final response = await http.post(
        Uri.parse('http://boet-system.com/save_token.php'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'username': username, 'token': token},
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        print('✅ Token sent successfully');
      }
    } catch (e) {
      print('⚠️ Error sending token: $e');
    }
  }

  Future<void> _showNotification(String title, String body) async {
    try {
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'high_importance_channel',
        'High Importance Notifications',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );

      await flutterLocalNotificationsPlugin.show(
        DateTime.now().millisecond,
        title,
        body,
        NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      print('⚠️ Show notification error: $e');
    }
  }

  // 📥 ФАЙЛ ТАТАХ - NATIVE ANDROID DOWNLOADMANAGER АШИГЛАХ
  Future<void> _downloadFile(String url, String filename) async {
    try {
      print('📥 Starting native download: $url');
      print('📄 Filename: $filename');

      if (!Platform.isAndroid) {
        _showToast('iOS дэмжигдэхгүй байна');
        return;
      }

      // Cookie авах
      CookieManager cookieManager = CookieManager.instance();
      List<Cookie> cookies = await cookieManager.getCookies(url: WebUri(url));
      String cookieString = cookies.map((c) => '${c.name}=${c.value}').join('; ');

      print('🍪 Cookie: ${cookieString.substring(0, cookieString.length > 50 ? 50 : cookieString.length)}...');

      // ✅ ЗАСВАРЛАСАН ХЭСЭГ - TIMEOUT НЭМСЭН
      final result = await platform.invokeMethod('downloadFile', {
        'url': url,
        'filename': filename,
        'cookie': cookieString,
      }).timeout(
        Duration(seconds: 10),
        onTimeout: () {
          print('⚠️ Download method timeout');
          _showToast('Хугацаа хэтэрсэн, дахин оролдоно уу');
          return false;
        },
      );

      if (result == true) {
        print('✅ Download started successfully');
        _showToast('Файл татаж эхэллээ...');
      } else {
        print('❌ Download failed to start');
        _showToast('Файл татах эхлүүлэх боломжгүй');
      }
    } on TimeoutException catch (e) {
      print('❌ Timeout error: $e');
      _showToast('Хугацаа хэтэрсэн');
    } on PlatformException catch (e) {
      print('❌ Platform error: ${e.message}');
      _showToast('Алдаа: ${e.message}');
    } catch (e) {
      print('❌ Download error: $e');
      _showToast('Алдаа: ${e.toString()}');
    }
  }

  void _showToast(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: Duration(seconds: 2)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (webViewController != null) {
          bool canGoBack = await webViewController!.canGoBack();
          if (canGoBack) {
            webViewController!.goBack();
            return false;
          }
        }
        return true;
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              progress < 1.0
                  ? LinearProgressIndicator(value: progress)
                  : Container(),
              Expanded(
                child: InAppWebView(
                  initialUrlRequest: URLRequest(
                    url: WebUri('http://boet-system.com'),
                  ),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    domStorageEnabled: true,
                    supportZoom: true,
                    builtInZoomControls: true,
                    displayZoomControls: false,
                    useWideViewPort: true,
                    loadWithOverviewMode: true,
                    mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                    thirdPartyCookiesEnabled: true,
                    useOnDownloadStart: true,
                  ),
                  pullToRefreshController: pullToRefreshController,
                  onWebViewCreated: (controller) {
                    webViewController = controller;
                    print('✅ WebView created');
                  },
                  onLoadStart: (controller, url) {
                    print('🔄 Loading: $url');
                    setState(() => progress = 0);
                  },
                  onLoadStop: (controller, url) async {
                    print('✅ Loaded: $url');
                    setState(() => progress = 1.0);
                    pullToRefreshController?.endRefreshing();

                    if (widget.firebaseEnabled &&
                        (url.toString().contains('dashboard') ||
                            url.toString().contains('boet-system.com'))) {
                      await Future.delayed(Duration(seconds: 2));
                      _checkAndSendToken();
                      _startPeriodicCheck();
                    }
                  },
                  onProgressChanged: (controller, prog) {
                    setState(() => progress = prog / 100);
                  },
                  onLoadError: (controller, url, code, message) {
                    print('⚠️ Load Error: $message');
                    pullToRefreshController?.endRefreshing();
                  },
                  onDownloadStartRequest: (controller, request) async {
                    try {
                      print('📥 Download requested: ${request.url}');
                      String filename = request.suggestedFilename ??
                          'download_${DateTime.now().millisecondsSinceEpoch}';
                      await _downloadFile(request.url.toString(), filename);
                    } catch (e) {
                      print('⚠️ Download handler error: $e');
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}