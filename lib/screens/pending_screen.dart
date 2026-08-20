import 'package:flutter/material.dart';
import 'login_screen.dart';

class PendingScreen extends StatelessWidget {
  const PendingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.hourglass_top,
                  color: Color(0xFF1DB954), size: 80),
              const SizedBox(height: 32),
              const Text(
                'En attente d\'approbation',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Votre demande a été envoyée à l\'administrateur. '
                'Vous recevrez l\'accès dès qu\'il aura approuvé votre compte.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: Colors.white54, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 48),
              TextButton(
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                ),
                child: const Text(
                  'Retour à la connexion',
                  style: TextStyle(color: Color(0xFF1DB954)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
