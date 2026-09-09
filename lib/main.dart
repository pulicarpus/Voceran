import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Mengunci tampilan aplikasi ke Mode Landscape
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const VArrangerApp());
}

class VArrangerApp extends StatelessWidget {
  const VArrangerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'vArranger Pro Controller',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF181A1D),
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

  // State Kontrol LCD & vArranger
  int _tempo = 120;
  String _currentStyle = 'Indonesian 1';
  String _currentChord = 'C Major';
  String _activeTab = 'MAIN';

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
      Uint8List midiData = Uint8List.fromList([0xB0, controllerNumber, value]);
      _midiCommand.sendData(midiData, timestamp: 0, deviceId: _selectedDevice?.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF2C3036), Color(0xFF17191C)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            children: [
              // PANEL ATAS: Sliders, Main LCD Display, & Master Controls
              Expanded(
                flex: 5,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Kiri: Sliders / Fader Mini
                    _buildSliderPanel(),
                    const SizedBox(width: 6),

                    // Tengah: LCD Touch Display Utama vArranger2
                    Expanded(flex: 6, child: _buildLcdDisplay()),
                    const SizedBox(width: 6),

                    // Kanan: Master Volume & Menu Knobs
                    _buildRightControlPanel(),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              // PANEL TENGAH: Transport (Start/Stop, Synchro, Keyboard Sets)
              Expanded(
                flex: 2,
                child: _buildMiddleTransportBar(),
              ),
              const SizedBox(height: 6),

              // PANEL BAWAH: Section Buttons (Intro, Variation, Fill, Break, Ending)
              Expanded(
                flex: 3,
                child: _buildBottomArrangerBar(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // WIDGET LCD DISPLAY INTERAKTIF
  Widget _buildLcdDisplay() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F141C),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF4A525D), width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          // Navigasi Tab LCD
          Container(
            color: const Color(0xFF1E232B),
            child: Row(
              children: ['MAIN', 'EFFECT', 'LIVE STYLE', 'DRUM'].map((tab) {
                bool isSelected = _activeTab == tab;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _activeTab = tab),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFD96B27) : Colors.transparent,
                        border: const Border(right: BorderSide(color: Colors.black26)),
                      ),
                      child: Text(
                        tab,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Isi Layar Utama LCD
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(6.0),
              child: Row(
                children: [
                  // Info Style & Tempo
                  Expanded(
                    flex: 5,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B222C),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFD96B27).withAlpha(128)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('STYLE SELECT', style: TextStyle(color: Colors.orangeAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                          Text(_currentStyle, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                          const Divider(color: Colors.white24, height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('TEMPO: $_tempo BPM', style: const TextStyle(color: Colors.cyanAccent, fontSize: 10)),
                              Text('CHORD: $_currentChord', style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const Spacer(),
                          // Pemilih MIDI Device di dalam LCD
                          Row(
                            children: [
                              const Icon(Icons.usb, color: Colors.amber, size: 12),
                              const SizedBox(width: 4),
                              Expanded(
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<MidiDevice>(
                                    hint: const Text('Connect vArranger MIDI', style: TextStyle(color: Colors.grey, fontSize: 9)),
                                    value: _selectedDevice,
                                    isExpanded: true,
                                    dropdownColor: const Color(0xFF1F242D),
                                    style: const TextStyle(color: Colors.white, fontSize: 9),
                                    items: _devices.map((device) {
                                      return DropdownMenuItem<MidiDevice>(
                                        value: device,
                                        child: Text(device.name),
                                      );
                                    }).toList(),
                                    onChanged: (device) {
                                      setState(() {
                                        _selectedDevice = device;
                                        if (device != null) _midiCommand.connectToDevice(device);
                                      });
                                    },
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.refresh, color: Colors.amber, size: 14),
                                onPressed: _scanMidiDevices,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              )
                            ],
                          )
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Info Upper/Lower Tracks
                  Expanded(
                    flex: 4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141921),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildTrackRow('UP1', 'Jazz Flute DNC', Colors.redAccent),
                          _buildTrackRow('UP2', 'Violin DNC', Colors.blueAccent),
                          _buildTrackRow('UP3', 'Alto Sax DNC', Colors.greenAccent),
                          _buildTrackRow('LOW', 'Saw Muff DNC', Colors.orangeAccent),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildTrackRow(String label, String sound, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(2)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            color: color,
            child: Text(label, style: const TextStyle(fontSize: 8, color: Colors.black, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 4),
          Expanded(child: Text(sound, style: const TextStyle(fontSize: 9, color: Colors.white), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  // SLIDER PANEL (KIRI)
  Widget _buildSliderPanel() {
    return Container(
      width: 130,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF21252B),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black38),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildFader('ACC1'),
          _buildFader('ACC2'),
          _buildFader('BASS'),
          _buildFader('DRUM'),
        ],
      ),
    );
  }

  Widget _buildFader(String label) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 8, color: Colors.grey)),
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderThemeData(
                thumbColor: Colors.grey[300],
                activeTrackColor: Colors.amber,
                inactiveTrackColor: Colors.black,
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(value: 0.8, onChanged: (v) {}),
            ),
          ),
        ),
      ],
    );
  }

  // MASTER CONTROL PANEL (KANAN)
  Widget _buildRightControlPanel() {
    return Container(
      width: 110,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF21252B),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildHardwareButton('MENU', Colors.grey[700]!, () {}),
          _buildHardwareButton('EXIT', Colors.grey[800]!, () {}),
          const Divider(color: Colors.white24, height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildMiniKnob('TEMPO +', () => setState(() => _tempo++)),
              _buildMiniKnob('TEMPO -', () => setState(() => _tempo--)),
            ],
          ),
        ],
      ),
    );
  }

  // MIDDLE TRANSPORT BAR
  Widget _buildMiddleTransportBar() {
    return Row(
      children: [
        _buildHardwareButton('SYNCHRO\nSTART', Colors.grey[800]!, () => _sendMidiCC(88, 127)),
        const SizedBox(width: 4),
        _buildHardwareButton('SYNCHRO\nSTOP', Colors.grey[800]!, () => _sendMidiCC(89, 127)),
        const SizedBox(width: 6),
        Expanded(
          child: _buildHardwareButton('START / STOP', Colors.red[700]!, () => _sendMidiCC(80, 127), height: double.infinity, fontSize: 13),
        ),
        const SizedBox(width: 6),
        _buildHardwareButton('TAP TEMPO', Colors.amber[800]!, () => _sendMidiCC(90, 127)),
        const SizedBox(width: 4),
        _buildHardwareButton('FADE IN/OUT', Colors.grey[800]!, () => _sendMidiCC(91, 127)),
      ],
    );
  }

  // BOTTOM ARRANGER BAR
  Widget _buildBottomArrangerBar() {
    return Row(
      children: [
        // INTRO
        _buildGroupSection('INTRO', [
          _buildHardwareButton('1', Colors.indigo[600]!, () => _sendMidiCC(81, 127)),
          _buildHardwareButton('2', Colors.indigo[600]!, () => _sendMidiCC(81, 127)),
          _buildHardwareButton('3', Colors.indigo[600]!, () => _sendMidiCC(81, 127)),
        ]),
        const SizedBox(width: 4),

        // VARIATION
        Expanded(
          child: _buildGroupSection('VARIATION', [
            _buildHardwareButton('A', Colors.blue[700]!, () => _sendMidiCC(82, 127)),
            _buildHardwareButton('B', Colors.blue[700]!, () => _sendMidiCC(83, 127)),
            _buildHardwareButton('C', Colors.blue[700]!, () => _sendMidiCC(86, 127)),
            _buildHardwareButton('D', Colors.blue[700]!, () => _sendMidiCC(87, 127)),
          ]),
        ),
        const SizedBox(width: 4),

        // FILL / BREAK
        _buildGroupSection('AUTO FILL / BREAK', [
          _buildHardwareButton('FILL 1', Colors.teal[700]!, () => _sendMidiCC(84, 127)),
          _buildHardwareButton('BREAK', Colors.orange[800]!, () => _sendMidiCC(85, 127)),
        ]),
        const SizedBox(width: 4),

        // ENDING
        _buildGroupSection('ENDING', [
          _buildHardwareButton('1', Colors.deepOrange[700]!, () => _sendMidiCC(92, 127)),
          _buildHardwareButton('2', Colors.deepOrange[700]!, () => _sendMidiCC(93, 127)),
          _buildHardwareButton('3', Colors.deepOrange[700]!, () => _sendMidiCC(94, 127)),
        ]),
      ],
    );
  }

  // HELPER WIDGETS (DESAIN TOMBOL FISIK)
  Widget _buildGroupSection(String title, List<Widget> buttons) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2228),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(title, style: const TextStyle(fontSize: 8, color: Colors.amber, fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          Expanded(child: Row(children: buttons.map((b) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 1.5), child: b))).toList())),
        ],
      ),
    );
  }

  Widget _buildHardwareButton(String text, Color color, VoidCallback onPressed, {double? height, double fontSize = 9}) {
    return SizedBox(
      height: height,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: EdgeInsets.zero,
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          side: const BorderSide(color: Colors.white24, width: 0.5),
        ),
        onPressed: onPressed,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildMiniKnob(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF333842),
          boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 2)],
        ),
        child: Text(label, style: const TextStyle(fontSize: 7, color: Colors.amber, fontWeight: FontWeight.bold)),
      ),
    );
  }
}