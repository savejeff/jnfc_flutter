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

  StreamSubscription<NfcCard?>? _sub;
  final TextEditingController _writeController = TextEditingController(text: '');

  @override
  void dispose() {
    _sub?.cancel();
    _writeController.dispose();
    super.dispose();
  }

  void _startReading() async {
    _sub?.cancel();
    _sub = NfcIo.instance.onCardDiscovered.listen((card) {
      if(card == null) {
        setState(() {
        _log = 'READ Canceled';
        });
      } else {
        last_card = card;
        _writeController.text = card.content;
        setState(() {
          _log = 'READ → uid=${card.uid}, content="${card.content}"';
        });
      }
    });
    await NfcIo.instance.startReading();
    setState(() {
      _log = 'Reading started...';
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
      content: _writeController.text,
    );
    setState(() {
      _log = res.success ? 'WRITE → success' : 'WRITE → error: ${res.error}';
    });
  }

  void _cancelWriting() async {
    await NfcIo.instance.cancelWriting();
    setState(() {
      _log = 'WRITE → canceled';
    });
  }


  @override
  Widget build(BuildContext context) {
    final uidText = last_card?.uid ?? '<none>';
    final contentText = last_card?.content ?? '<none>';

    return Scaffold(
      appBar: AppBar(title: const Text('nfc_io example')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_log),
            const SizedBox(height: 8),
            Text('Last UID: $uidText', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Last Content: $contentText'),
            const SizedBox(height: 12),
            TextField(
              controller: _writeController,
              decoration: const InputDecoration(
                labelText: 'Content to write',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton(
                  onPressed: _startReading,
                  child: const Text('Start Reading'),
                ),
                ElevatedButton(
                  onPressed: _stopReading,
                  child: const Text('Stop Reading'),
                ),
                ElevatedButton(
                  onPressed: _startWriting,
                  child: const Text('Start Writing'),
                ),
                OutlinedButton(
                  onPressed: _cancelWriting,
                  child: const Text('Cancel Writing'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

}
