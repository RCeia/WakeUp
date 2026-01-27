import 'dart:async';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:alarm/alarm.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Alarm.init();
  runApp(const WakeUpApp());
}

class WakeUpApp extends StatelessWidget {
  const WakeUpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: Colors.orange,
        colorScheme: const ColorScheme.dark(
          primary: Colors.orange,
          secondary: Colors.deepOrange,
        ),
      ),
      // --- IDIOMA E RODA ---
      locale: const Locale('en', 'US'), 
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', 'US'),
        Locale('pt', 'PT'),
      ],
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  DateTime _selectedTime = DateTime.now();
  bool _isDaily = false;
  String _statusMessage = "Define a tua hora de acordar";
  bool _isAlarmScheduled = false;
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  bool _isAlarmRinging = false;
  bool _isMonitoringActivity = false;

  final AudioPlayer _audioPlayer = AudioPlayer();
  static const platform = MethodChannel('com.rodri.wakeup/pinning');
  
  Timer? _uiGuardTimer;
  Timer? _inactivityTimer;
  Timer? _successTimer;
  StreamSubscription? _accelSubscription;
  StreamSubscription? _alarmSubscription;

  final int _monitorDurationSeconds = 600; 
  final int _maxInactivitySeconds = 45;    
  int _secondsRemaining = 600;

  // --- MEMÓRIA ---
  Future<void> _loadDailyPreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDaily = prefs.getBool('is_daily_check') ?? false;
    });
  }

  Future<void> _saveDailyPreference(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_daily_check', value);
  }

  Future<void> _cancelStickyNotification() async {
    try {
      await _notificationsPlugin.cancel(888);
    } catch (e) {
      print("Erro ao cancelar notificação: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    final now = DateTime.now();
    _selectedTime = DateTime(now.year, now.month, now.day, now.hour, now.minute);

    _loadDailyPreference(); 

    _alarmSubscription = Alarm.ringStream.stream.listen((alarmSettings) {
      Alarm.stop(alarmSettings.id); 
      _triggerAlarm();
    });

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    _notificationsPlugin.initialize(initializationSettings);
    _checkScheduledAlarms();
  }

  Future<void> _checkScheduledAlarms() async {
    final alarms = Alarm.getAlarms();
    if (alarms.isNotEmpty) {
      setState(() {
        _isAlarmScheduled = true;
        _statusMessage = "Alarme Ativo. Bom descanso.";
      });
      _showStickyNotification(alarms.first.dateTime);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alarmSubscription?.cancel();
    _cancelStickyNotification();
    _stopEverything();
    super.dispose();
  }

  void _stopEverything() {
    _audioPlayer.stop();
    _uiGuardTimer?.cancel();
    _inactivityTimer?.cancel();
    _successTimer?.cancel();
    _accelSubscription?.cancel();
    WakelockPlus.disable();
    _unlockApp();
    _showSystemBars();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isAlarmRinging || _isMonitoringActivity) {
      if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
        if (_isAlarmRinging) _audioPlayer.resume(); 
        WakelockPlus.enable();
      }
      if (state == AppLifecycleState.resumed) {
        _hideSystemBars();
      }
    }
  }

  Future<void> _lockApp() async { try { await platform.invokeMethod('pinApp'); } catch (e) {} }
  Future<void> _unlockApp() async { try { await platform.invokeMethod('unpinApp'); } catch (e) {} }
  void _hideSystemBars() { SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky); }
  void _showSystemBars() { SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge); }

  Future<void> _setAlarm() async {
    DateTime now = DateTime.now();
    DateTime targetTime = DateTime(
      now.year, now.month, now.day,
      _selectedTime.hour, _selectedTime.minute, 0
    );

    if (targetTime.isBefore(now)) {
      targetTime = targetTime.add(const Duration(days: 1));
    }

    final alarmSettings = AlarmSettings(
      id: 42,
      dateTime: targetTime,
      assetAudioPath: 'assets/alarm.mp3',
      loopAudio: true,
      vibrate: true,
      fadeDuration: 3.0,
      notificationTitle: 'ACORDA!',
      notificationBody: 'Toca para parar',
      enableNotificationOnKill: true,
    );

    await Alarm.set(alarmSettings: alarmSettings);

    setState(() {
      _isAlarmScheduled = true;
      String dayStr = targetTime.day == now.day ? "hoje" : "amanhã";
      String hourStr = targetTime.hour.toString().padLeft(2, '0');
      String minStr = targetTime.minute.toString().padLeft(2, '0');
      _statusMessage = "Alarme para $dayStr às $hourStr:$minStr";
    });

    _showStickyNotification(targetTime);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Alarme agendado com sucesso!')),
    );
  }

  Future<void> _cancelAlarm() async {
    await Alarm.stop(42);
    _cancelStickyNotification();
    setState(() {
      _isAlarmScheduled = false;
      _statusMessage = "Alarme cancelado.";
    });
  }

  void _triggerAlarm() async {
    _cancelStickyNotification(); 

    _inactivityTimer?.cancel();
    _successTimer?.cancel();
    _accelSubscription?.cancel();
    
    await WakelockPlus.enable(); 
    await _lockApp();    
    _hideSystemBars();
    
    try { await FlutterVolumeController.setVolume(1.0, stream: AudioStream.alarm); } catch (e) {}
    
    _uiGuardTimer?.cancel();
    _uiGuardTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isAlarmRinging || _isMonitoringActivity) {
        _hideSystemBars();
        try { FlutterVolumeController.setVolume(1.0, stream: AudioStream.alarm); } catch (e) {}
      }
    });

    setState(() { 
      _isAlarmRinging = true; 
      _isMonitoringActivity = false;
      _isAlarmScheduled = false; 
    });

    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(pattern: [500, 1000, 500, 2000], repeat: 0);
    }

    await _audioPlayer.setAudioContext(const AudioContext(
      android: AudioContextAndroid(
        isSpeakerphoneOn: true,
        stayAwake: true,
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.alarm, 
        audioFocus: AndroidAudioFocus.gainTransient, 
      ),
      iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
    ));

    await _audioPlayer.setVolume(1.0); 
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    await _audioPlayer.play(AssetSource('alarm.mp3'));
  }

  void _startActivityMonitoring() {
    setState(() {
      _isAlarmRinging = false;
      _isMonitoringActivity = true;
      _secondsRemaining = _monitorDurationSeconds; 
    });

    _audioPlayer.stop();
    Vibration.cancel();
    _resetInactivityTimer();
    
    _accelSubscription = accelerometerEvents.listen((AccelerometerEvent event) {
      double force = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      if (force > 11.0 || force < 8.5) {
        _resetInactivityTimer();
      }
    });

    _successTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_secondsRemaining > 0) {
          _secondsRemaining--;
        } else {
          _finishMorningRoutine();
        }
      });
    });
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(Duration(seconds: _maxInactivitySeconds), _triggerAlarm);
  }

  void _finishMorningRoutine() async {
    _stopEverything(); 
    
    if (_isDaily) {
      await _setAlarm(); 
      setState(() {
        _isAlarmRinging = false;
        _isMonitoringActivity = false;
      });
      if (mounted) {
        showDialog(
          context: context, 
          builder: (_) => const AlertDialog(title: Text("Ciclo Diário"), content: Text("Alarme reagendado para amanhã."))
        );
      }
    } else {
      _cancelStickyNotification();
      setState(() {
        _isAlarmRinging = false;
        _isMonitoringActivity = false;
        _statusMessage = "Rotina Completa. Bom dia!";
      });
      if (mounted) {
       showDialog(
         context: context, 
         builder: (_) => const AlertDialog(title: Text("Parabéns!"), content: Text("Sobreviveste."))
       );
     }
    }
  }

  void _onQrCodeScanned(String code) {
    if (code == 'DESLIGAR_WAKEUP_AGORA') {
      Navigator.pop(context);
      if (_isMonitoringActivity) {
        _audioPlayer.stop();
        Vibration.cancel();
        setState(() { _isAlarmRinging = false; });
        _resetInactivityTimer();
      } else {
        _startActivityMonitoring();
      }
    }
  }

  Future<void> _showStickyNotification(DateTime targetTime) async {
    final now = DateTime.now();
    String dayStr = targetTime.day == now.day ? "hoje" : "amanhã";
    String hourStr = targetTime.hour.toString().padLeft(2, '0');
    String minStr = targetTime.minute.toString().padLeft(2, '0');
    String message = "Toca $dayStr às $hourStr:$minStr";

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'sticky_channel_id', 
      'Estado do Alarme',
      channelDescription: 'Mostra que o alarme está ativo',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,      
      autoCancel: false, 
      showWhen: false,
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails);
    try {
      await _notificationsPlugin.show(888, 'Alarme Agendado', message, details);
    } catch (e) {
      print("Erro notificação: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isAlarmRinging) return PopScope(canPop: false, child: Scaffold(backgroundColor: Colors.red, body: _buildAlarmScreen()));
    if (_isMonitoringActivity) return PopScope(canPop: false, child: Scaffold(backgroundColor: Colors.deepOrange, body: _buildMonitorScreen()));

    return Scaffold(
      backgroundColor: const Color(0xFF121212), 
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          // CORREÇÃO DO SCROLL: Usamos Column com Spacer para fixar tudo
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // LOGO E STATUS
              const Spacer(),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 25),
                padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.05),
                  border: Border.all(color: Colors.orange, width: 2),
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(color: Colors.orange.withOpacity(0.15), blurRadius: 20, spreadRadius: 1)
                  ]
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/logo.png', 
                      height: 120, // Reduzi um pouco para garantir espaço
                      errorBuilder: (_,__,___) => const Icon(Icons.alarm, size: 80, color: Colors.orange)
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_isAlarmScheduled ? Icons.check_circle : Icons.schedule, color: _isAlarmScheduled ? Colors.green : Colors.white70),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            _statusMessage, 
                            textAlign: TextAlign.center, 
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // RODA DE TEMPO
              Stack(
                alignment: Alignment.center,
                children: [
                  IgnorePointer(
                    ignoring: _isAlarmScheduled,
                    child: Opacity(
                      opacity: _isAlarmScheduled ? 0.5 : 1.0,
                      child: SizedBox(
                        height: 178, 
                        child: CupertinoTheme(
                          data: const CupertinoThemeData(
                            brightness: Brightness.dark,
                            textTheme: CupertinoTextThemeData(
                              dateTimePickerTextStyle: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w500),
                            ),
                          ),
                          child: CupertinoDatePicker(
                            key: UniqueKey(),
                            mode: CupertinoDatePickerMode.time,
                            initialDateTime: _selectedTime,
                            use24hFormat: true,
                            onDateTimeChanged: (t) => _selectedTime = t,
                          ),
                        ),
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: Container(
                      height: 35,
                      margin: const EdgeInsets.symmetric(horizontal: 30),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.05),
                        border: Border.all(color: Colors.orange, width: 2.0),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  )
                ],
              ),

              const Spacer(),

              // CHECKBOX DIÁRIO
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Checkbox(
                    value: _isDaily, 
                    activeColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange), 
                    checkColor: Colors.black,
                    onChanged: _isAlarmScheduled ? null : (v) {
                      if (v == null) return;
                      setState(() => _isDaily = v);
                      _saveDailyPreference(v); 
                    }
                  ),
                  const Text("Repetir Diariamente", style: TextStyle(color: Colors.white70))
                ],
              ),

              const Spacer(),

              // BOTÕES
              _isAlarmScheduled 
              ? ElevatedButton(
                  onPressed: _cancelAlarm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color((0xFF121212)), 
                    foregroundColor: Colors.white, 
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))
                  ),
                  child: const Text('CANCELAR ALARME', style: TextStyle(fontSize: 16)),
                )
              : ElevatedButton(
                  onPressed: _setAlarm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange, 
                    foregroundColor: Colors.black, 
                    padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    elevation: 10,
                    shadowColor: Colors.orange.withOpacity(0.5)
                  ),
                  child: const Text('DEFINIR ALARME', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                
               const Spacer(),
               
               // TESTE RÁPIDO
               if (!_isAlarmScheduled)
                 TextButton.icon(
                   onPressed: () async {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fecha a app AGORA! Toca em 10s.')));
                      final now = DateTime.now();
                      final target = now.add(const Duration(seconds: 10));
                      final alarmSettings = AlarmSettings(
                        id: 42,
                        dateTime: target,
                        assetAudioPath: 'assets/alarm.mp3',
                        loopAudio: true,
                        vibrate: true,
                        fadeDuration: 3.0,
                        notificationTitle: 'TESTE',
                        notificationBody: 'Abre a app!',
                        enableNotificationOnKill: true,
                      );
                      await Alarm.set(alarmSettings: alarmSettings);
                   },
                   icon: const Icon(Icons.science, color: Colors.white24, size: 16),
                   label: const Text("Teste Rápido (10s)", style: TextStyle(color: Colors.white24)),
                 ),
                 
               const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlarmScreen() {
    return SizedBox.expand(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.warning_amber, size: 100, color: Colors.white),
          const SizedBox(height: 20),
          const Text('ACORDA!', style: TextStyle(fontSize: 60, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 5)),
          const Text('A única saída é o QR Code', style: TextStyle(color: Colors.white70, fontSize: 18)),
          const SizedBox(height: 60),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => QrScannerScreen(onScan: _onQrCodeScanned))),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.red, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20)),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('LER QR CODE', style: TextStyle(fontSize: 20)),
          ),
        ],
      ),
    );
  }

  Widget _buildMonitorScreen() {
    return SizedBox.expand(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.directions_run, size: 100, color: Colors.white),
          const SizedBox(height: 20),
          const Text('MEXE-TE!', style: TextStyle(fontSize: 50, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 10),
          const Text('Não pares por 45 segundos!', style: TextStyle(color: Colors.white70, fontSize: 18)),
          const SizedBox(height: 50),
          Text('${_secondsRemaining}',
            style: const TextStyle(fontSize: 100, fontWeight: FontWeight.bold, color: Colors.white)),
          const Text('segundos restantes', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 40),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 50),
            child: LinearProgressIndicator(
              value: 1 - (_secondsRemaining / _monitorDurationSeconds),
              color: Colors.white, backgroundColor: Colors.deepOrangeAccent, minHeight: 10, borderRadius: BorderRadius.circular(5),
            ),
          )
        ],
      ),
    );
  }
}

class QrScannerScreen extends StatefulWidget {
  final Function(String) onScan;
  const QrScannerScreen({super.key, required this.onScan});
  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  bool _hasScanned = false;
  @override
  Widget build(BuildContext context) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    return Scaffold(
      body: MobileScanner(onDetect: (capture) {
        if (_hasScanned) return;
        if (capture.barcodes.any((b) => b.rawValue != null)) {
          _hasScanned = true;
          widget.onScan(capture.barcodes.first.rawValue!);
        }
      }),
    );
  }
}