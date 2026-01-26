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
      theme: ThemeData.dark(),
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
  String _statusMessage = "Escolhe uma hora";
  bool _isAlarmScheduled = false;

  bool _isAlarmRinging = false;
  bool _isMonitoringActivity = false;

  final AudioPlayer _audioPlayer = AudioPlayer();
  static const platform = MethodChannel('com.rodri.wakeup/pinning');
  
  Timer? _uiGuardTimer;
  Timer? _inactivityTimer;
  Timer? _successTimer;
  StreamSubscription? _accelSubscription;
  StreamSubscription? _alarmSubscription;

  // --- ALTERAÇÕES DE TEMPO AQUI ---
  final int _monitorDurationSeconds = 10; // Agora são apenas 10 SEGUNDOS
  final int _maxInactivitySeconds = 3;    // Se parares 3 segundos, perdes
  int _secondsRemaining = 10;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedTime = DateTime.now();

    // LÓGICA V3.1.5
    _alarmSubscription = Alarm.ringStream.stream.listen((alarmSettings) {
      Alarm.stop(alarmSettings.id); 
      _triggerAlarm();
    });

    _checkScheduledAlarms();
  }

  Future<void> _checkScheduledAlarms() async {
    if (Alarm.getAlarms().isNotEmpty) {
      setState(() {
        _isAlarmScheduled = true;
        _statusMessage = "Alarme ativo (Recuperado).";
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alarmSubscription?.cancel();
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
      _statusMessage = "Alarme definido para $dayStr às $hourStr:$minStr";
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Podes fechar a app. O alarme vai tocar!')),
    );
  }

  Future<void> _cancelAlarm() async {
    await Alarm.stop(42);
    setState(() {
      _isAlarmScheduled = false;
      _statusMessage = "Alarme cancelado.";
    });
  }

  void _triggerAlarm() async {
    _inactivityTimer?.cancel();
    _successTimer?.cancel();
    _accelSubscription?.cancel();
    
    await WakelockPlus.enable(); 
    await _lockApp();    
    _hideSystemBars();
    
    try {
      await FlutterVolumeController.setVolume(1.0, stream: AudioStream.alarm);
    } catch (e) {
      print("Erro volume: $e");
    }
    
    _uiGuardTimer?.cancel();
    _uiGuardTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isAlarmRinging || _isMonitoringActivity) {
        _hideSystemBars();
        try { 
          FlutterVolumeController.setVolume(1.0, stream: AudioStream.alarm); 
        } catch (e) {}
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
      // Define o tempo restante para os 10 segundos
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
    
    setState(() {
      _isAlarmRinging = false;
      _isMonitoringActivity = false;
      _statusMessage = "Bom dia! Rotina completa.";
    });

    if (_isDaily) {
      _setAlarm();
      if (mounted) {
        showDialog(
          context: context, 
          builder: (_) => const AlertDialog(title: Text("Até amanhã"), content: Text("Alarme reagendado."))
        );
      }
    } else {
       if (mounted) {
        showDialog(
          context: context, 
          builder: (_) => const AlertDialog(title: Text("Parabéns!"), content: Text("És livre."))
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

  @override
  Widget build(BuildContext context) {
    if (_isAlarmRinging) return PopScope(canPop: false, child: Scaffold(backgroundColor: Colors.red, body: _buildAlarmScreen()));
    if (_isMonitoringActivity) return PopScope(canPop: false, child: Scaffold(backgroundColor: Colors.deepOrange, body: _buildMonitorScreen()));

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/logo.png', height: 120, errorBuilder: (_,__,___) => const Text('WakeUp', style: TextStyle(color: Colors.orange, fontSize: 40))),
            const SizedBox(height: 10),
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(_statusMessage, textAlign: TextAlign.center, style: TextStyle(color: _isAlarmScheduled ? Colors.green : Colors.white70, fontSize: 16)),
            ),

            const SizedBox(height: 20),

            IgnorePointer(
              ignoring: _isAlarmScheduled,
              child: Opacity(
                opacity: _isAlarmScheduled ? 0.5 : 1.0,
                child: SizedBox(
                  height: 180,
                  child: CupertinoTheme(
                    data: const CupertinoThemeData(brightness: Brightness.dark),
                    child: CupertinoDatePicker(
                      mode: CupertinoDatePickerMode.time,
                      initialDateTime: _selectedTime,
                      use24hFormat: true,
                      onDateTimeChanged: (t) => _selectedTime = t,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Checkbox(
                  value: _isDaily, 
                  activeColor: Colors.orange,
                  onChanged: _isAlarmScheduled ? null : (v) => setState(() => _isDaily = v!)
                ),
                const Text("Repetir Diariamente")
              ],
            ),

            const SizedBox(height: 30),

            _isAlarmScheduled 
            ? ElevatedButton(
                onPressed: _cancelAlarm,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[800], foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15)),
                child: const Text('CANCELAR ALARME'),
              )
            : ElevatedButton(
                onPressed: _setAlarm,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15)),
                child: const Text('DEFINIR ALARME'),
              ),
              
             const SizedBox(height: 20),
             if (!_isAlarmScheduled)
               TextButton(
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
                 child: const Text("Testar (Fecha a App e Espera 10s)", style: TextStyle(color: Colors.white24)),
               )
          ],
        ),
      ),
    );
  }

  Widget _buildAlarmScreen() {
    return SizedBox.expand(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.warning_amber, size: 80, color: Colors.white),
          const Text('ACORDA!', style: TextStyle(fontSize: 50, fontWeight: FontWeight.bold, color: Colors.white)),
          Text(_isMonitoringActivity ? 'PARASTE DE MEXER!' : 'Lê o QR Code!', style: const TextStyle(color: Colors.white, fontSize: 20)),
          const SizedBox(height: 50),
          ElevatedButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => QrScannerScreen(onScan: _onQrCodeScanned))),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.red, padding: const EdgeInsets.all(20)),
            child: const Text('LER QR CODE', style: TextStyle(fontSize: 20)),
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
          const Icon(Icons.directions_run, size: 80, color: Colors.white),
          const Text('Mexe-te!', style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 20),
          const Text('Não pares por 3s!', style: TextStyle(color: Colors.white70, fontSize: 18)),
          const SizedBox(height: 40),
          // MOSTRAR APENAS SEGUNDOS AGORA
          Text('${_secondsRemaining}',
            style: const TextStyle(fontSize: 80, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 10),
          const Text('segundos restantes', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: LinearProgressIndicator(
              value: 1 - (_secondsRemaining / _monitorDurationSeconds), // Cálculo corrigido
              color: Colors.white, backgroundColor: Colors.orangeAccent,
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