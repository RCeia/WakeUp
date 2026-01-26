import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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
  DateTime _time = DateTime(2024, 1, 1, 7, 0); // Variável que guarda a hora escolhida
  bool _isAlarmRinging = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  static const platform = MethodChannel('com.rodri.wakeup/pinning');
  Timer? _uiGuardTimer; 

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _audioPlayer.dispose();
    _uiGuardTimer?.cancel();
    super.dispose();
  }

  // SE TENTAREM SAIR, O SOM CONTINUA!
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isAlarmRinging) {
      if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
        _audioPlayer.resume(); 
        WakelockPlus.enable();
      }
      if (state == AppLifecycleState.resumed) {
        _hideSystemBars();
      }
    }
  }

  Future<void> _lockApp() async {
    try { await platform.invokeMethod('pinApp'); } catch (e) { print(e); }
  }

  Future<void> _unlockApp() async {
    try { await platform.invokeMethod('unpinApp'); } catch (e) { print(e); }
  }

  void _hideSystemBars() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _showSystemBars() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _scheduleAlarm() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Alarme em 3 segundos...')),
    );

    Future.delayed(const Duration(seconds: 3), () async {
      await WakelockPlus.enable(); 
      await _lockApp();    
      _hideSystemBars();
      
      _uiGuardTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
        if (_isAlarmRinging) _hideSystemBars();
      });

      setState(() { _isAlarmRinging = true; });

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
    });
  }

  void _onQrCodeScanned(String code) async {
    if (code == 'DESLIGAR_WAKEUP_AGORA') {
      _uiGuardTimer?.cancel();
      await _unlockApp();
      await WakelockPlus.disable();
      _showSystemBars(); 
      Vibration.cancel();
      await _audioPlayer.stop();

      setState(() { _isAlarmRinging = false; });
      if (mounted) Navigator.pop(context); 
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isAlarmRinging) {
      return PopScope(
        canPop: false, 
        child: Scaffold(
          backgroundColor: Colors.red,
          body: SizedBox.expand(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock, size: 80, color: Colors.white),
                const Text('BLOQUEADO!', style: TextStyle(fontSize: 50, fontWeight: FontWeight.bold, color: Colors.white)),
                const Text('Não tentes sair.\nLê o QR Code!', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 20)),
                const SizedBox(height: 50),
                ElevatedButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => QrScannerScreen(onScan: _onQrCodeScanned))),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.red, padding: const EdgeInsets.all(20)),
                  child: const Text('LER QR CODE', style: TextStyle(fontSize: 20)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/logo.png', height: 150, errorBuilder: (_,__,___) => const Text('WakeUp', style: TextStyle(color: Colors.orange, fontSize: 40))),
            
            const SizedBox(height: 20),

            // --- AQUI ESTÁ A RODA DE VOLTA! ---
            SizedBox(
              height: 200,
              child: CupertinoTheme(
                data: const CupertinoThemeData(brightness: Brightness.dark),
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  initialDateTime: _time,
                  use24hFormat: true,
                  onDateTimeChanged: (DateTime newTime) {
                    setState(() {
                      _time = newTime;
                    });
                  },
                ),
              ),
            ),
            // ----------------------------------

            const SizedBox(height: 50),
            ElevatedButton(
              onPressed: _scheduleAlarm,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15)),
              child: const Text('TESTAR ALARME IMORTAL'),
            )
          ],
        ),
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