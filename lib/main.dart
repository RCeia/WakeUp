import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';

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

class _HomeScreenState extends State<HomeScreen> {
  DateTime _time = DateTime(2024, 1, 1, 7, 0);
  bool _isAlarmRinging = false;
  
  // O LEITOR DE MÚSICA
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  // Função para simular o disparo do alarme
  void _scheduleAlarm() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Alarme definido! Espera 3 segundos...')),
    );

    Future.delayed(const Duration(seconds: 3), () async {
      setState(() {
        _isAlarmRinging = true; // ATIVA O MODO ALARME
      });

      // 1. VIBRAÇÃO
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(pattern: [500, 1000, 500, 2000], repeat: 0);
      }

      // 2. SOM (Agora aponta diretamente para alarm.mp3 na pasta assets)
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      // O flutter assume que AssetSource começa dentro da pasta 'assets/'
      await _audioPlayer.play(AssetSource('alarm.mp3')); 
    });
  }

  // Função chamada quando o QR Code é lido com sucesso
  void _onQrCodeScanned(String code) async {
    if (code == 'DESLIGAR_WAKEUP_AGORA') {
      
      // PARAR VIBRAÇÃO E SOM
      Vibration.cancel();
      await _audioPlayer.stop();

      setState(() {
        _isAlarmRinging = false;
      });

      if (mounted) {
        Navigator.pop(context); // Fecha a câmara
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Colors.green, content: Text('Bom dia! Silêncio restaurado.')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: Colors.red, content: Text('QR Code errado! Tenta outra vez!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- MODO ALARME (VERMELHO) ---
    if (_isAlarmRinging) {
      return Scaffold(
        backgroundColor: Colors.red,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.volume_up, size: 100, color: Colors.white),
              const Text(
                'ACORDA!',
                style: TextStyle(fontSize: 50, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text('A tocar alarme...', style: TextStyle(color: Colors.white70)),
              ),
              const SizedBox(height: 50),
              ElevatedButton.icon(
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('PARAR BARULHO'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.red,
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => QrScannerScreen(onScan: _onQrCodeScanned),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );
    }

    // --- MODO NORMAL ---
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            tryLoadLogo(),
            const SizedBox(height: 20),
            
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

            const SizedBox(height: 50),

            ElevatedButton(
              onPressed: _scheduleAlarm,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                backgroundColor: Colors.orange,
                foregroundColor: Colors.black,
                side: const BorderSide(color: Colors.black, width: 3),
              ),
              child: const Text('TESTAR SOM (3s)'),
            ),
          ],
        ),
      ),
    );
  }

  Widget tryLoadLogo() {
    return Image.asset(
      'assets/logo.png',
      height: 150,
      errorBuilder: (context, error, stackTrace) {
        return const Text('Wake Up', style: TextStyle(fontSize: 40, color: Colors.orange));
      },
    );
  }
}

// --- ECRÃ DO LEITOR DE QR ---
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
    return Scaffold(
      appBar: AppBar(title: const Text('Encontra o QR Code!')),
      body: MobileScanner(
        onDetect: (capture) {
          if (_hasScanned) return; 
          final List<Barcode> barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            if (barcode.rawValue != null) {
              _hasScanned = true; 
              widget.onScan(barcode.rawValue!);
              break;
            }
          }
        },
      ),
    );
  }
}