import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

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

// MUDANÇA: Agora usamos StatefulWidget porque a hora vai mudar!
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Esta variável guarda a hora escolhida. Começa nas 07:00
  DateTime _time = DateTime(2024, 1, 1, 7, 0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/logo.png',
              height: 200, // Ajusta este valor se ficar muito grande ou pequeno
            ),
            
            const SizedBox(height: 20),

            // O WIDGET DA RODA MÁGICA
            SizedBox(
              height: 200, // Altura da "roda"
              child: CupertinoTheme(
                // Forçamos o tema escuro para o texto ser branco
                data: const CupertinoThemeData(brightness: Brightness.dark), 
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time, // Apenas horas e minutos
                  initialDateTime: _time,
                  use24hFormat: true, // Formato 24h (se quiseres AM/PM mete false)
                  // Esta função corre sempre que rodas a roda
                  onDateTimeChanged: (DateTime newTime) {
                    setState(() {
                      _time = newTime; // Atualiza a variável com a nova hora
                    });
                  },
                ),
              ),
            ),

            const SizedBox(height: 50),

            ElevatedButton(
              onPressed: () {
                // Aqui vamos colocar a lógica de ativar o alarme mais tarde
                print('Alarme guardado para as ${_time.hour}:${_time.minute}');
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                backgroundColor: Colors.orange,
                foregroundColor: Colors.black, 
                side: const BorderSide(color: Colors.black, width: 3),
              ),
              child: const Text('GUARDAR'),
            ),
          ],
        ),
      ),
    );
  }
}