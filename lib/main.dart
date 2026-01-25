import 'package:flutter/material.dart';

void main() {
  runApp(const WakeUpApp());
}

class WakeUpApp extends StatelessWidget {
  const WakeUpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, // Remove a etiqueta "Debug" do canto
      theme: ThemeData.dark(), // Tema escuro para não ferir os olhos de manhã
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Fundo preto
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, // Alinha tudo ao centro vertical
          children: [
            // Texto da Hora
            const Text(
              '07:00',
              style: TextStyle(
                fontSize: 80,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            
            const SizedBox(height: 20), // Um espaço vazio entre o texto e o botão
            
            // Botão de Acordar
            ElevatedButton(
              onPressed: () {
                print('Botão clicado!'); 
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                backgroundColor: Colors.orange, // Cor do botão
              ),
              child: const Text(
                'DEFINIR ALARME',
                style: TextStyle(fontSize: 20, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}