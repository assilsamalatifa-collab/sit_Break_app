import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:audioplayers/audioplayers.dart';

void main() {
  runApp(const SitBreakApp());
}

class SitBreakApp extends StatelessWidget {
  const SitBreakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sit & Break',
      theme: ThemeData(primarySwatch: Colors.teal),
      home: const LanguageScreen(),
    );
  }
}

// ================= 1. شاشة اختيار اللغة =================
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Select Your Language / اختر اللغة',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              const SizedBox(height: 40),
              ElevatedButton(
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: () => _setLanguage(context, 'ar'),
                child: const Text('العربية', style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: () => _setLanguage(context, 'en'),
                child: const Text('English', style: TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setLanguage(BuildContext context, String lang) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang', lang);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    );
  }
}

// ================= 2. شاشة الإعدادات =================
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double workMinutes = 25;
  double breakMinutes = 5;
  String selectedTone = 'Default Bell';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Timer Settings / الإعدادات')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Text('Work Duration: ${workMinutes.toInt()} mins'),
            Slider(
              value: workMinutes,
              min: 1,
              max: 60,
              divisions: 59,
              label: '${workMinutes.toInt()} mins',
              onChanged: (val) => setState(() => workMinutes = val),
            ),
            const Divider(),
            Text('Break Duration: ${breakMinutes.toInt()} mins'),
            Slider(
              value: breakMinutes,
              min: 1,
              max: 30,
              divisions: 29,
              label: '${breakMinutes.toInt()} mins',
              onChanged: (val) => setState(() => breakMinutes = val),
            ),
            const Divider(),
            const Text('Alarm Tone / نغمة المنبه'),
            DropdownButton<String>(
              value: selectedTone,
              isExpanded: true,
              items: ['Default Bell', 'Digital Beep', 'Soft Chime']
                  .map((tone) => DropdownMenuItem(value: tone, child: Text(tone)))
                  .toList(),
              onChanged: (val) => setState(() => selectedTone = val!),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(55),
                backgroundColor: Colors.teal,
              ),
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TimerScreen(
                      workTime: workMinutes.toInt() * 60,
                      breakTime: breakMinutes.toInt() * 60,
                      tone: selectedTone,
                    ),
                  ),
                );
              },
              child: const Text('Start App / بدء التطبيق',
                  style: TextStyle(fontSize: 18, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= 3. شاشة المؤقت والشروط الذكية =================
class TimerScreen extends StatefulWidget {
  final int workTime;
  final int breakTime;
  final String tone;

  const TimerScreen({
    super.key,
    required this.workTime,
    required this.breakTime,
    required this.tone,
  });

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  late int remainingSeconds;
  bool isWorking = true;
  bool isRunning = false;
  
  // شروط التشغيل
  bool isPhoneMoving = false;
  bool isScreenActive = true; // افترضنا التشغيل الافتراضي، يمكن ربطه ب حزم الحالة

  StreamSubscription? accelerometerSub;
  Timer? timer;
  final AudioPlayer audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    remainingSeconds = widget.workTime;
    _initSensors();
    _startMainTimer();
  }

  // مراقبة حركة الهاتف عبر حساس التسارع
  void _initSensors() {
    accelerometerSub = accelerometerEvents.listen((event) {
      // إذا تغيرت الإحداثيات بقيمة محسوسة، فهذا يعني أن الهاتف يتحرك
      double totalMovement = event.x.abs() + event.y.abs() + event.z.abs();
      setState(() {
        // إذا كان مجموع الحركة يتجاوز عتبة معين، نعتبره يتحرك
        isPhoneMoving = totalMovement > 11.5; // 9.8 هي الجاذبية الأرضية الثابتة
      });
    });
  }

  void _startMainTimer() {
    timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      // الشرط الأساسي: هل الهاتف شغال ويتحرك معاً؟
      // (هنا نفترض أن شاشة التطبيق أمامك تعمل كدلالة على أن الهاتف شغال، ونراقب الحركة بالـ Sensor)
      bool conditionsMet = isPhoneMoving; 

      if (conditionsMet) {
        setState(() {
          isRunning = true;
          if (remainingSeconds > 0) {
            remainingSeconds--;
          } else {
            _playAlarm();
            // تبديل بين العمل والاستراحة
            isWorking = !isWorking;
            remainingSeconds = isWorking ? widget.workTime : widget.breakTime;
          }
        });
      } else {
        setState(() {
          isRunning = false; // المؤقت متوقف لأن الشروط غير متوفرة
        });
      }
    });
  }

  void _playAlarm() async {
    // تشغيل الصوت بناءً على النغمة المختارة
    // يمكنك وضع ملفات صوتية في assets وتشغيلها عبر audioplayers
    // مثال افتراضي:
    // await audioPlayer.play(AssetSource('alarm.mp3'));
  }

  @override
  void dispose() {
    accelerometerSub?.cancel();
    timer?.cancel();
    audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    int minutes = remainingSeconds ~/ 60;
    int seconds = remainingSeconds % 60;

    return Scaffold(
      appBar: AppBar(
        title: Text(isWorking ? 'Work Time / وقت العمل' : 'Break Time / وقت الاستراحة'),
        backgroundColor: isWorking ? Colors.teal : Colors.orange,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // مؤشر حالة الشروط
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isRunning ? Colors.green.shade100 : Colors.red.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isRunning ? '🟢 Timer Running (Conditions Met)' : '🔴 Timer Paused (Move phone / keep active)',
                style: TextStyle(
                  color: isRunning ? Colors.green.shade800 : Colors.red.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 40),
            // عرض الوقت بصيغة تنازلية
            Text(
              '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 64, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Text(
              isWorking ? 'Focus on your task!' : 'Relax and take a breath!',
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 40),
            // تفاصيل الحالة الحية للمستشعرات للتوضيح
            Text('Phone Moving: ${isPhoneMoving ? "Yes ✅" : "No ❌"}',
                style: const TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
