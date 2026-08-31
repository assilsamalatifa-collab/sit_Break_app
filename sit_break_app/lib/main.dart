import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const SitBreakApp());
}

class SitBreakApp extends StatelessWidget {
  const SitBreakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'تذكير الجلوس والاستراحة',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
        fontFamily: 'Tajawal', // اختياري: أضف الخط في pubspec لو تبي
      ),
      home: const HomePage(),
    );
  }
}

enum AppState { idle, sitting, onBreak }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ---- إعدادات المستخدم ----
  int sitMinutes = 30;
  int breakMinutes = 5;

  // ---- حالة التطبيق ----
  AppState state = AppState.idle;
  bool monitoring = false;

  // ---- عداد الوقت ----
  Timer? _countdownTimer;
  Duration remaining = Duration.zero;

  // ---- كشف الحركة ----
  StreamSubscription<AccelerometerEvent>? _accelSub;
  final List<double> _magnitudeBuffer = [];
  static const int _bufferSize = 20; // ~2 ثانية عند 10hz معالجة
  static const double _stillnessThreshold = 0.35; // اضبطه حسب التجربة

  DateTime? _stillSince;
  DateTime? _movingSince;
  static const Duration _confirmStillFor = Duration(seconds: 8);
  static const Duration _confirmMovingFor = Duration(seconds: 5);

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );
    await _notifications.initialize(initSettings);

    // طلب صلاحية الإشعارات (مهم على iOS و Android 13+)
    await Permission.notification.request();
  }

  Future<void> _showNotification(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'sit_break_channel',
      'تذكيرات الجلوس والاستراحة',
      importance: Importance.max,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    await _notifications.show(0, title, body, details);
  }

  // ---------------- منطق الكشف عن الحركة ----------------

  void _startMonitoring() {
    setState(() {
      monitoring = true;
      state = AppState.idle;
    });
    _magnitudeBuffer.clear();
    _stillSince = null;
    _movingSince = null;

    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen(_onAccelEvent);
  }

  void _stopMonitoring() {
    _accelSub?.cancel();
    _accelSub = null;
    _countdownTimer?.cancel();
    setState(() {
      monitoring = false;
      state = AppState.idle;
      remaining = Duration.zero;
    });
  }

  void _onAccelEvent(AccelerometerEvent event) {
    // نحسب مقدار المتجه ونطرح الجاذبية (~9.8) لنعرف مقدار الحركة الفعلية
    final magnitude = sqrt(
          event.x * event.x + event.y * event.y + event.z * event.z,
        ) -
        9.8;

    _magnitudeBuffer.add(magnitude.abs());
    if (_magnitudeBuffer.length > _bufferSize) {
      _magnitudeBuffer.removeAt(0);
    }
    if (_magnitudeBuffer.length < _bufferSize) return;

    final avgVariation =
        _magnitudeBuffer.reduce((a, b) => a + b) / _magnitudeBuffer.length;

    final now = DateTime.now();
    final isStill = avgVariation < _stillnessThreshold;

    if (isStill) {
      _movingSince = null;
      _stillSince ??= now;

      if (state == AppState.idle &&
          now.difference(_stillSince!) >= _confirmStillFor) {
        _enterSitting();
      }
    } else {
      _stillSince = null;
      _movingSince ??= now;

      if (state == AppState.sitting &&
          now.difference(_movingSince!) >= _confirmMovingFor) {
        _backToIdle(userGotUp: true);
      }
    }
  }

  // ---------------- إدارة الحالات ----------------

  void _enterSitting() {
    setState(() {
      state = AppState.sitting;
      remaining = Duration(minutes: sitMinutes);
    });
    _startCountdown(onDone: () {
      _showNotification('وقت الاستراحة! 🧍', 'قم من مكانك وتحرك قليلاً.');
      _enterBreak();
    });
  }

  void _enterBreak() {
    setState(() {
      state = AppState.onBreak;
      remaining = Duration(minutes: breakMinutes);
    });
    _startCountdown(onDone: () {
      _showNotification('انتهت الاستراحة 💺', 'يمكنك الرجوع لجلستك الآن.');
      _backToIdle(userGotUp: false);
    });
  }

  void _backToIdle({required bool userGotUp}) {
    _countdownTimer?.cancel();
    setState(() {
      state = AppState.idle;
      remaining = Duration.zero;
    });
    _stillSince = null;
    _movingSince = null;
    if (userGotUp) {
      _showNotification('لاحظنا أنك تحركت', 'تم إيقاف عداد الجلوس مؤقتاً.');
    }
  }

  void _startCountdown({required VoidCallback onDone}) {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() {
        if (remaining.inSeconds <= 1) {
          t.cancel();
          remaining = Duration.zero;
          onDone();
        } else {
          remaining -= const Duration(seconds: 1);
        }
      });
    });
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  String _stateLabel() {
    switch (state) {
      case AppState.idle:
        return monitoring ? 'بانتظار الثبات لبدء العد...' : 'متوقف';
      case AppState.sitting:
        return 'جالس - جاري العد';
      case AppState.onBreak:
        return 'وقت الاستراحة';
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تذكير الجلوس والاستراحة')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSettingRow(
                label: 'مدة الجلوس (دقيقة)',
                value: sitMinutes,
                onChanged: monitoring
                    ? null
                    : (v) => setState(() => sitMinutes = v),
              ),
              const SizedBox(height: 12),
              _buildSettingRow(
                label: 'مدة الاستراحة (دقيقة)',
                value: breakMinutes,
                onChanged: monitoring
                    ? null
                    : (v) => setState(() => breakMinutes = v),
              ),
              const SizedBox(height: 30),
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Text(
                        _stateLabel(),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      if (state != AppState.idle)
                        Text(
                          _formatDuration(remaining),
                          style: Theme.of(context)
                              .textTheme
                              .displayMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: monitoring ? _stopMonitoring : _startMonitoring,
                icon: Icon(monitoring ? Icons.stop : Icons.play_arrow),
                label: Text(monitoring ? 'إيقاف' : 'ابدأ المراقبة'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'ملاحظة: الكشف يعتمد على ثبات الجهاز كمؤشر تقريبي للجلوس، '
                'وقد لا يكون دقيقاً 100%. اترك الجوال بجانبك أثناء الجلوس '
                'ليعمل الكشف بشكل أفضل.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingRow({
    required String label,
    required int value,
    required ValueChanged<int>? onChanged,
  }) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: onChanged == null || value <= 1
              ? null
              : () => onChanged(value - 1),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: onChanged == null ? null : () => onChanged(value + 1),
        ),
      ],
    );
  }
}
