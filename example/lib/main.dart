import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:jnfc_flutter/jnfc_flutter.dart';


void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  String _log = 'Ready';
  NfcCard? last_card = null;

  StreamSubscription<NfcCard>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _startReading() async {
    _sub?.cancel();
    _sub = NfcIo.instance.onCardDiscovered.listen((card) {
      last_card = card;
      setState(() {
        _log = 'READ → uid=${card.uid}, content="${card.content}"';
      });
    });
    await NfcIo.instance.startReading();
    setState(() {
      _log = 'Reading started... (mock will fire in ~1s)';
    });
  }

  void _stopReading() async {
    await NfcIo.instance.stopReading();
    await _sub?.cancel();
    setState(() {
      _log = 'Reading stopped';
    });
  }

  void _startWriting() async {
    final res = await NfcIo.instance.startWriting(
      uid: last_card?.uid ?? '',
      content: 'Hi there!2',
    );
    setState(() {
      _log = res.success ? 'WRITE → success' : 'WRITE → error: ${res.error}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('nfc_io example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_log),
            const SizedBox(height: 12),
            Wrap(spacing: 12, children: [
              ElevatedButton(onPressed: _startReading, child: const Text('Start Reading')),
              ElevatedButton(onPressed: _stopReading, child: const Text('Stop Reading')),
              ElevatedButton(onPressed: _startWriting, child: const Text('Start Writing')),
            ]),
          ],
        ),
      ),
    );
  }
}
