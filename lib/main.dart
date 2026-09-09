import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';

void main() {
  runApp(const VArrangerApp());
}

class VArrangerApp extends StatelessWidget {
  const VArrangerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'vArranger Controller',
      theme: ThemeData.dark(),
      home: const ControllerScreen(),
    );
  }
}

class ControllerScreen extends StatefulWidget {
  const ControllerScreen({super.key});

  @override
  State<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends State<ControllerScreen> {
  final MidiCommand _midiCommand = MidiCommand();
  MidiDevice? _selectedDevice;
  List<MidiDevice> _devices = [];

  @override
  void initState() {
    super.initState();
    _scanMidiDevices();
  }

  void _scanMidiDevices() async {
    var devices = await _midiCommand.devices;
    setState(() {
      _devices = devices ?? [];
    });
  }

  // Fungsi Mengirim Sinyal MIDI CC (Control Change)
  void _sendMidiCC(int controllerNumber, int value) {
    if (_selectedDevice != null) {
      // 0xB0 = Control Change pada Channel 1
      Uint8List midiData = Uint8List.fromList([0xB0, controllerNumber, value]);
      _midiCommand.sendData(midiData, timestamp: 0, device: _selectedDevice);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih perangkat MIDI terlebih dahulu!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('vArranger2 Controller'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _scanMidiDevices,
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Dropdown Pemilihan Perangkat MIDI (USB / Bluetooth)
            DropdownButton<MidiDevice>(
              hint: const Text('Pilih MIDI Port / Device'),
              value: _selectedDevice,
              isExpanded: true,
              items: _devices.map((device) {
                return DropdownMenuItem<MidiDevice>(
                  value: device,
                  child: Text(device.name),
                );
              }).toList(),
              onChanged: (device) {
                setState(() {
                  _selectedDevice = device;
                  if (device != null) {
                    _midiCommand.connectToDevice(device);
                  }
                });
              },
            ),
            const SizedBox(height: 20),
            
            // Grid Tombol Kontrol vArranger2
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                children: [
                  _buildControlButton('START / STOP', Colors.green, () {
                    _sendMidiCC(80, 127); // CC 80
                  }),
                  _buildControlButton('INTRO / ENDING', Colors.red, () {
                    _sendMidiCC(81, 127); // CC 81
                  }),
                  _buildControlButton('VARIATION A', Colors.blue, () {
                    _sendMidiCC(82, 127); // CC 82
                  }),
                  _buildControlButton('VARIATION B', Colors.blueAccent, () {
                    _sendMidiCC(83, 127); // CC 83
                  }),
                  _buildControlButton('TEMPO +', Colors.orange, () {
                    _sendMidiCC(84, 127); // CC 84
                  }),
                  _buildControlButton('TEMPO -', Colors.orangeAccent, () {
                    _sendMidiCC(85, 127); // CC 85
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton(String text, Color color, VoidCallback onPressed) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onPressed,
      child: Text(
        text,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
    );
  }
}