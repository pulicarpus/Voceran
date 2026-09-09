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
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Colors.amber,
          surface: Color(0xFF1E1E1E),
        ),
      ),
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

  void _sendMidiCC(int controllerNumber, int value) {
    if (_selectedDevice != null) {
      // 0xB0 = Control Change pada MIDI Channel 1
      Uint8List midiData = Uint8List.fromList([0xB0, controllerNumber, value]);
      // Menggunakan parameter `deviceId` sesuai API flutter_midi_command terbaru
      _midiCommand.sendData(midiData, timestamp: 0, deviceId: _selectedDevice?.id);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pilih perangkat MIDI (USB/Bluetooth) terlebih dahulu!'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('vArranger2 Controller'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _scanMidiDevices,
            tooltip: 'Refresh Perangkat MIDI',
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Dropdown Pemilihan Perangkat MIDI
            Container(
              padding: const EdgeInsets.horizontal(12, 4),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber, width: 1),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<MidiDevice>(
                  hint: const Text('Pilih MIDI Device (USB / Bluetooth)'),
                  value: _selectedDevice,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF2A2A2A),
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
              ),
            ),
            const SizedBox(height: 20),

            // Grid Tombol Kontrol vArranger2
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.3,
                children: [
                  _buildButton('START / STOP', Colors.green, () => _sendMidiCC(80, 127)),
                  _buildButton('INTRO / ENDING', Colors.red, () => _sendMidiCC(81, 127)),
                  _buildButton('VARIATION A', Colors.blue, () => _sendMidiCC(82, 127)),
                  _buildButton('VARIATION B', Colors.blueAccent, () => _sendMidiCC(83, 127)),
                  _buildButton('VARIATION C', Colors.indigo, () => _sendMidiCC(86, 127)),
                  _buildButton('VARIATION D', Colors.indigoAccent, () => _sendMidiCC(87, 127)),
                  _buildButton('TEMPO +', Colors.orange, () => _sendMidiCC(84, 127)),
                  _buildButton('TEMPO -', Colors.deepOrange, () => _sendMidiCC(85, 127)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton(String text, Color color, VoidCallback onPressed) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onPressed,
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
    );
  }
}