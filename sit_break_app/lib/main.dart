import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';

void main() => runApp(const SitBreakApp());

enum AppLanguage { ar, en, fr }

class AppLanguageHelper {
  static const Map<AppLanguage, Map<String, String>> _strings = {
    AppLanguage.ar: {
      'title': 'تذكير الجلوس والاستراحة',
      'sitDuration': 'مدة الجلوس (دقيقة)',
      'breakDuration': 'مدة الاستراحة (دقيقة)',
      'start': 'إبدأ المراقبة',
      'stop': 'إيقاف المراقبة',
      'stopAlarm': 'إيقاف المنبه 🔔',
      'stateIdle': 'متوقف',
      'stateSittingMoving': 'جالس - جاري العد',
      'stateSittingPaused': 'متوقف مؤقتاً - بانتظار الحركة',
      'stateBreak': 'الاستراحة',
      'note': 'ملاحظة: أثناء الجلوس، العداد يعمل فقط عند تحرك الجهاز ولو بحركة بسيطة.',
      'notifyBreakTitle': 'وقت الاستراحة!',
      'notifyBreakBody': 'قم من مكانك وتحرك قليلاً',
      'notifyBackTitle': 'انتهت الاستراحة!',
      'notifyBackBody': 'ارجع لجلستك، سيبدأ العد من جديد',
      'moving': 'بتحرك',
      'still': 'ثابت',
    },
    AppLanguage.en: {
      'title': 'Sit & Break Reminder',
      'sitDuration': 'Sit duration (minutes)',
      'breakDuration': 'Break duration (minutes)',
      'start': 'Start Monitoring',
      'stop': 'Stop Monitoring',
      'stopAlarm': 'Stop Alarm 🔔',
      'stateIdle': 'Stopped',
      'stateSittingCounting': 'Sitting - Counting',
      'stateSittingPaused': 'Paused - waiting for movement',
      'stateBreak': 'Break Time',
      'note': 'Note: While sitting, the timer only runs when the device is moving.',
      'notifyBreakTitle': 'Break time!',
      'notifyBreakBody': 'Get up and move a little.',
      'notifyBackTitle': 'Break finished!',
      'notifyBackBody': 'Back to your seat, the count restarts.',
      'moving': 'Moving',
      'still': 'Still',
    },
    AppLanguage.fr: {
      'title': 'Rappel Assise & Pause',
      'sitDuration': 'Durée assise (minutes)',
      'breakDuration': 'Durée de pause (minutes)',
      'start': 'Démarrer',
      'stop': 'Arrêter',
      'stopAlarm': 'Arrêter l\'alarme 🔔',
      'stateIdle': 'Arrêté',
      'stateSittingMoving': 'Assis - Décompte en cours',
      'stateSittingPaused': 'En pause - en attente de mouvement',
      'stateBreak': 'Temps de pause',
      'note': 'Remarque : En position assise, le minuteur ne fonctionne que si l\'appareil bouge.',
      'notifyBreakTitle': 'Pause !',
      'notifyBreakBody': 'Levez-vous et bougez un peu.',
      'notifyBackTitle': 'Pause terminée !',
      'notifyBackBody': 'Retournez à votre place, le compte redémarre.',
      'moving': 'En mouvement',
      'still': 'Immobile',
    },
  };

  static String t(String key, {AppLanguage lang = AppLanguage.ar}) {
    return _strings[lang]?[key] ?? key;
  }

  static bool isRtl(AppLanguage lang) => lang == AppLanguage.ar;
}

enum AppState { idle, sitting, breakTime }

class SitBreakApp extends StatelessWidget {
  const SitBreakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sit & Break Reminder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1283A8),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4FFBA),
        fontFamily: 'Tajawal',
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  AppLanguage _lang = AppLanguage.ar;
  int sitMinutes = 30;
  int breakMinutes = 5;

  AppState _state = AppState.idle;
  bool _isMonitoring = false;
  bool _isAlarmRinging = false;
  Duration _remaining = Duration.zero;
  Duration _phaseTotal = Duration.zero;
  Timer? _countdownTimer;

  StreamSubscription<AccelerometerEvent>? _accelSub;
  final List<double> _magnitudeBuffer = [];
  static const int _bufferSize = 10;
  static const double _stillnessThreshold = 0.12;
  bool _isMoving = false;

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final AudioPlayer _audioPlayer = AudioPlayer();

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
    await Permission.notification.request();
  }

  // 🔔 تشغيل صوت المنبه
  Future<void> _triggerAlarm(String title, String body) async {
    setState(() => _isAlarmRinging = true);

    // تشغيل نغمة المنبه الافتراضية للنظام أو رابط MP3 مباشر
    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      // رابط صوت منبه جاهز لتجربته، يمكنك تغييره بأي رابط أو ملف asset محلي
      await _audioPlayer.play(
        UrlSource('https://actions.google.com/sounds/v1/alarms/beep_short.ogg'),
      );
    } catch (e) {
      debugPrint("خطأ في تشغيل الصوت: $e");
    }

    // إظهار الإشعار المرئي
    const androidDetails = AndroidNotificationDetails(
      'sit_break_channel',
      'Sit & Break Reminders',
      importance: Importance.max,
      priority: Priority.high,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    );
    const iosDetails = DarwinNotificationDetails();
    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(0, title, body, notificationDetails);
  }

  // ⏹️ إيقاف صوت المنبه
  Future<void> _stopAlarmSound() async {
    await _audioPlayer.stop();
    setState(() => _isAlarmRinging = false);
  }

  void _startMonitoring() {
    _magnitudeBuffer.clear();
    _isMoving = false;
    setState(() {
      _isMonitoring = true;
    });

    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen((event) {
      final finalMagnitude = sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      ) - 9.8;

      _magnitudeBuffer.add(finalMagnitude.abs());
      if (_magnitudeBuffer.length > _bufferSize) {
        _magnitudeBuffer.removeAt(0);
      }

      if (_magnitudeBuffer.length < _bufferSize) return;

      final avgVariation =
          _magnitudeBuffer.reduce((a, b) => a + b) / _magnitudeBuffer.length;
      final moving = avgVariation > _stillnessThreshold;

      if (moving != _isMoving) {
        setState(() {
          _isMoving = moving;
        });
      }
    });

    _enterSitting();
  }

  void _stopMonitoring() {
    _stopAlarmSound();
    _accelSub?.cancel();
    _accelSub = null;
    _countdownTimer?.cancel();
    setState(() {
      _isMonitoring = false;
      _state = AppState.idle;
      _remaining = Duration.zero;
      _phaseTotal = Duration.zero;
      _isMoving = false;
    });
  }

  void _enterSitting() {
    final total = Duration(minutes: sitMinutes);
    setState(() {
      _state = AppState.sitting;
      _remaining = total;
      _phaseTotal = total;
    });
    _startCountdown(
      requireMovement: true,
      onDone: () {
        _triggerAlarm(
          AppLanguageHelper.t('notifyBreakTitle', lang: _lang),
          AppLanguageHelper.t('notifyBreakBody', lang: _lang),
        );
        _enterBreak();
      },
    );
  }

  void _enterBreak() {
    final total = Duration(minutes: breakMinutes);
    setState(() {
      _state = AppState.breakTime;
      _remaining = total;
      _phaseTotal = total;
    });
    _startCountdown(
      requireMovement: false,
      onDone: () {
        _triggerAlarm(
          AppLanguageHelper.t('notifyBackTitle', lang: _lang),
          AppLanguageHelper.t('notifyBackBody', lang: _lang),
        );
        if (_isMonitoring) {
          _enterSitting();
        }
      },
    );
  }

  void _startCountdown({
    required bool requireMovement,
    required VoidCallback onDone,
  }) {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (requireMovement && !_isMoving) return;

      setState(() {
        if (_remaining.inSeconds <= 1) {
          t.cancel();
          _remaining = Duration.zero;
          onDone();
        } else {
          _remaining = Duration(seconds: _remaining.inSeconds - 1);
        }
      });
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _accelSub?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  String _stateLabel() {
    switch (_state) {
      case AppState.idle:
        return AppLanguageHelper.t('stateIdle', lang: _lang);
      case AppState.sitting:
        return _isMoving
            ? AppLanguageHelper.t('stateSittingMoving', lang: _lang)
            : AppLanguageHelper.t('stateSittingPaused', lang: _lang);
      case AppState.breakTime:
        return AppLanguageHelper.t('stateBreak', lang: _lang);
    }
  }

  Color _stateColor(ColorScheme scheme) {
    switch (_state) {
      case AppState.idle:
        return scheme.primary;
      case AppState.sitting:
        return _isMoving ? Colors.orange : Colors.grey;
      case AppState.breakTime:
        return Colors.blueAccent;
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  double _getProgressValue() {
    if (_phaseTotal.inSeconds == 0) return 0;
    return 1 - (_remaining.inSeconds / _phaseTotal.inSeconds);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: AppLanguageHelper.isRtl(_lang)
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(AppLanguageHelper.t('title', lang: _lang)),
          centerTitle: true,
          backgroundColor: scheme.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            _buildLanguageSwitcher(),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _buildSettingRow(
                        icon: Icons.event_seat_rounded,
                        label: AppLanguageHelper.t('sitDuration', lang: _lang),
                        value: sitMinutes,
                        onChanged: _isMonitoring
                            ? null
                            : (v) => setState(() => sitMinutes = v),
                      ),
                      const Divider(height: 24),
                      _buildSettingRow(
                        icon: Icons.directions_walk_rounded,
                        label: AppLanguageHelper.t('breakDuration', lang: _lang),
                        value: breakMinutes,
                        onChanged: _isMonitoring
                            ? null
                            : (v) => setState(() => breakMinutes = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Center(
                  child: SizedBox(
                    width: 220,
                    height: 220,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 220,
                          height: 220,
                          child: CircularProgressIndicator(
                            value: _getProgressValue().clamp(0.0, 1.0),
                            strokeWidth: 10,
                            backgroundColor: scheme.primary.withOpacity(0.12),
                            valueColor: AlwaysStoppedAnimation(
                              _stateColor(scheme),
                            ),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: _stateColor(scheme),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _state == AppState.idle
                                  ? '--:--'
                                  : _formatDuration(_remaining),
                              style: const TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                _stateLabel(),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _stateColor(scheme),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                if (_isAlarmRinging) ...[
                  ElevatedButton.icon(
                    onPressed: _stopAlarmSound,
                    icon: const Icon(Icons.notifications_off_rounded),
                    label: Text(AppLanguageHelper.t('stopAlarm', lang: _lang)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                ElevatedButton.icon(
                  onPressed:
                      _isMonitoring ? _stopMonitoring : _startMonitoring,
                  icon: Icon(
                    _isMonitoring
                        ? Icons.stop_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  label: Text(
                    _isMonitoring
                        ? AppLanguageHelper.t('stop', lang: _lang)
                        : AppLanguageHelper.t('start', lang: _lang),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.primary.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    AppLanguageHelper.t('note', lang: _lang),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageSwitcher() {
    return PopupMenuButton<AppLanguage>(
      icon: const Icon(Icons.language_rounded),
      onSelected: (v) => setState(() => _lang = v),
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: AppLanguage.ar,
          child: Text('العربية'),
        ),
        PopupMenuItem(
          value: AppLanguage.en,
          child: Text('English'),
        ),
        PopupMenuItem(
          value: AppLanguage.fr,
          child: Text('Français'),
        ),
      ],
    );
  }

  Widget _buildSettingRow({
    required IconData icon,
    required String label,
    required int value,
    required ValueChanged<int>? onChanged,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, color: scheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 15),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: onChanged == null || value <= 1
              ? null
              : () => onChanged(value - 1),
        ),
        SizedBox(
          width: 36,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: onChanged == null
              ? null
              : () => onChanged(value + 1),
        ),
      ],
    );
  }
}
