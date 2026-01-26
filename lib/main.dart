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

void main() {
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
  // CONFIGURAÇÕES DO UTILIZADOR
  DateTime _selectedTime = DateTime.now(); // Hora escolhida na roda
  bool _isDaily = false; // Checkbox Diário
  String _statusMessage = "Escolhe uma hora";
  bool _isAlarmScheduled = false; // Para mudar o botão de Set para Cancelar

  // ESTADOS DO SISTEMA
  bool _isAlarmRinging = false;
  bool _isMonitoringActivity = false;

  final AudioPlayer _audioPlayer = AudioPlayer();
  static const platform = MethodChannel('com.rodri.wakeup/pinning');
  
  Timer? _alarmTimer;           // O Timer que espera até à hora certa
  Timer? _uiGuardTimer;         // Esconde botões
  Timer? _inactivityTimer;      // Castigo de movimento
  Timer? _successTimer;         // Meta de 10 minutos
  StreamSubscription? _accelSubscription;

  final int _monitorDurationMinutes = 10;
  final int _maxInactivitySeconds = 45;
  int _secondsRemaining = 600;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Inicializa a roda com a hora atual
    _selectedTime = DateTime.now();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopEverything();
    super.dispose();
  }

  void _stopEverything() {
    _audioPlayer.stop();
    _alarmTimer?.cancel(); // Cancela o alarme agendado
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

  // --- FUNÇÕES DE BLOQUEIO ---
  Future<void> _lockApp() async { try { await platform.invokeMethod('pinApp'); } catch (e) {} }
  Future<void> _unlockApp() async { try { await platform.invokeMethod('unpinApp'); } catch (e) {} }
  void _hideSystemBars() { SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky); }
  void _showSystemBars() { SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge); }

  // --- LÓGICA DE AGENDAMENTO ---
  
  void _setAlarm() {
    DateTime now = DateTime.now();
    
    // Criar um objeto DateTime com a hora escolhida, mas com a data de hoje
    DateTime targetTime = DateTime(
      now.year,
      now.month,
      now.day,
      _selectedTime.hour,
      _selectedTime.minute,
      0 // Segundos a 0 para ser preciso
    );

    // Se a hora escolhida já passou hoje (ex: são 15:00 e escolhi 07:00),
    // então o alarme é para amanhã.
    if (targetTime.isBefore(now)) {
      targetTime = targetTime.add(const Duration(days: 1));
    }

    Duration waitDuration = targetTime.difference(now);

    // Cancelar timer antigo se existir
    _alarmTimer?.cancel();

    // Iniciar o countdown
    _alarmTimer = Timer(waitDuration, () {
      _triggerAlarm();
    });

    setState(() {
      _isAlarmScheduled = true;
      // Formatar a string para mostrar ao utilizador
      String dayStr = targetTime.day == now.day ? "hoje" : "amanhã";
      String hourStr = targetTime.hour.toString().padLeft(2, '0');
      String minStr = targetTime.minute.toString().padLeft(2, '0');
      _statusMessage = "Alarme definido para $dayStr às $hourStr:$minStr";
    });
    
    // Manter o ecrã ligado para o Timer não morrer (opcional, mas recomendado no Huawei)
    WakelockPlus.enable();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Dorme bem! Faltam ${waitDuration.inHours}h ${waitDuration.inMinutes % 60}m.')),
    );
  }

  void _cancelAlarm() {
    _alarmTimer?.cancel();
    WakelockPlus.disable();
    setState(() {
      _isAlarmScheduled = false;
      _statusMessage = "Alarme cancelado.";
    });
  }

  // --- DISPARAR O ALARME ---
  void _triggerAlarm() async {
    _inactivityTimer?.cancel();
    _successTimer?.cancel();
    _accelSubscription?.cancel();

    await WakelockPlus.enable(); 
    await _lockApp();    
    _hideSystemBars();
    
    _uiGuardTimer?.cancel();
    _uiGuardTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_isAlarmRinging || _isMonitoringActivity) _hideSystemBars();
    });

    setState(() { 
      _isAlarmRinging = true; 
      _isMonitoringActivity = false;
      _isAlarmScheduled = false; // O alarme disparou, já não está agendado
    });

    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(pattern: [500, 1000, 500, 2000], repeat: 0);
    }

    await _audioPlayer.setAudioContext(AudioContext(
      android: AudioContextAndroid(
        isSpeakerphoneOn: true,
        stayAwake: true,
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.alarm, 
        audioFocus: AndroidAudioFocus.gainTransient, 
      ),
      iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
    ));

    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    await _audioPlayer.play(AssetSource('alarm.mp3'));
  }

  // --- MODO FISCAL ---
  void _startActivityMonitoring() {
    setState(() {
      _isAlarmRinging = false;
      _isMonitoringActivity = true;
      _secondsRemaining = _monitorDurationMinutes * 60;
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

    // REAGENDAR SE FOR DIÁRIO
    if (_isDaily) {
      // Reutilizamos a função de Set, ela calcula automaticamente para amanhã
      _setAlarm();
      if (mounted) {
        showDialog(
          context: context, 
          builder: (_) => const AlertDialog(
            title: Text("Missão Cumprida"), 
            content: Text("O alarme já foi reagendado para amanhã."),
          )
        );
      }
    } else {
       if (mounted) {
        showDialog(
          context: context, 
          builder: (_) => AlertDialog(
            title: const Text("Parabéns!"), 
            content: const Text("Sobreviveste aos 10 minutos. Bom dia!"),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
          )
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
    if (_isAlarmRinging) {
      return PopScope(canPop: false, child: Scaffold(backgroundColor: Colors.red, body: _buildAlarmScreen()));
    }

    if (_isMonitoringActivity) {
      return PopScope(canPop: false, child: Scaffold(backgroundColor: Colors.deepOrange, body: _buildMonitorScreen()));
    }

    // ECRÃ PRINCIPAL (SETUP)
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/logo.png', height: 120, errorBuilder: (_,__,___) => const Text('WakeUp', style: TextStyle(color: Colors.orange, fontSize: 40))),
            const SizedBox(height: 10),
            
            // Mensagem de Status
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(_statusMessage, textAlign: TextAlign.center, style: TextStyle(color: _isAlarmScheduled ? Colors.green : Colors.white70, fontSize: 16)),
            ),

            const SizedBox(height: 20),

            // Roda de Tempo (Só ativa se o alarme NÃO estiver definido)
            IgnorePointer(
              ignoring: _isAlarmScheduled, // Bloqueia a roda se já estiver definido
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

            // Checkbox Diário
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

            // Botão Principal (Set ou Cancelar)
            _isAlarmScheduled 
            ? ElevatedButton(
                onPressed: _cancelAlarm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[800], foregroundColor: Colors.white, 
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15)
                ),
                child: const Text('CANCELAR ALARME'),
              )
            : ElevatedButton(
                onPressed: _setAlarm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange, foregroundColor: Colors.black, 
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15)
                ),
                child: const Text('DEFINIR ALARME'),
              ),
              
             const SizedBox(height: 20),
             // Botão de Teste Rápido (Para não teres de esperar horas para testar)
             if (!_isAlarmScheduled)
               TextButton(
                 onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Teste rápido em 3 segundos...')));
                    Future.delayed(const Duration(seconds: 3), _triggerAlarm);
                 },
                 child: const Text("Testar Agora (3s)", style: TextStyle(color: Colors.white24)),
               )
          ],
        ),
      ),
    );
  }

  // Widgets auxiliares para limpar o código principal
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
          const Text('Não pares por 45s!', style: TextStyle(color: Colors.white70, fontSize: 18)),
          const SizedBox(height: 40),
          Text('${(_secondsRemaining / 60).floor()}:${(_secondsRemaining % 60).toString().padLeft(2, '0')}',
            style: const TextStyle(fontSize: 60, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: LinearProgressIndicator(
              value: 1 - (_secondsRemaining / (_monitorDurationMinutes * 60)),
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