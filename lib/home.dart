import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
// Video and image imports - ready for future use
// import 'package:video_player/video_player.dart';
// import 'package:cached_network_image/cached_network_image.dart';
import 'dart:ui';
import 'dart:math' as math;

// Helper function to get a reference to the Realtime Database (RTDB)
DatabaseReference getRTDBRef(String path) {
  return FirebaseDatabase.instance.ref(path);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late stt.SpeechToText _speech;
  late FlutterTts _flutterTts;
  bool _isListening = false;
  String _lastWords = '';
  bool _speechAvailable = false;
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    // Clear any leftover snackbars from login page
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
      }
    });
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    
    // Initialize speech recognition
    _speech = stt.SpeechToText();
    _initializeSpeech();
    
    // Initialize text-to-speech (non-blocking)
    _flutterTts = FlutterTts();
    _initializeTts().catchError((e) {
      debugPrint('TTS initialization error: $e');
    });
  }

  Future<void> _initializeTts() async {
    try {
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.5); // Normal speech rate
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
    } catch (e) {
      debugPrint('TTS setup error: $e');
    }
  }

  Future<void> _speak(String text) async {
    try {
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint('TTS error: $e');
    }
  }

  Future<void> _initializeSpeech() async {
    bool available = await _speech.initialize(
      onStatus: (status) {
        if (mounted) {
          setState(() {
            if (status == 'done' || status == 'notListening') {
              _isListening = false;
            }
          });
        }
      },
      onError: (error) {
        if (mounted) {
          debugPrint('Speech recognition error: $error');
          setState(() {
            _isListening = false;
          });
        }
      },
    );
    if (mounted) {
      setState(() {
        _speechAvailable = available;
      });
    }
  }

  void _startListening() async {
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Speech recognition not available'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    _playSound('click');
    setState(() {
      _isListening = true;
      _lastWords = '';
    });

    await _speech.listen(
      onResult: (result) {
        if (mounted) {
          setState(() {
            _lastWords = result.recognizedWords;
          });
          
          if (result.finalResult) {
            _processVoiceCommand(_lastWords);
            setState(() {
              _isListening = false;
            });
          }
        }
      },
      listenFor: const Duration(seconds: 5),
      pauseFor: const Duration(seconds: 3),
      localeId: 'en_US',
    );
  }

  void _stopListening() {
    _speech.stop();
    setState(() {
      _isListening = false;
    });
  }

  void _processVoiceCommand(String command) {
    final lowerCommand = command.toLowerCase().trim();
    debugPrint('Voice command received: $lowerCommand');

    // Parse commands like:
    // "Turn on relay 1", "Turn off relay 1"
    // "Turn on relay 2", "Turn off relay 2"
    // "Relay 1 on", "Relay 1 off", etc.

    bool turnOn = lowerCommand.contains('turn on') || 
                  lowerCommand.contains('on') && !lowerCommand.contains('turn off') && !lowerCommand.contains('off');
    bool turnOff = lowerCommand.contains('turn off') || 
                   lowerCommand.contains('off') && !lowerCommand.contains('on');
    
    String? relayId;
    if (lowerCommand.contains('relay 1') || lowerCommand.contains('relay one') || lowerCommand.contains('one')) {
      relayId = 'relay1';
    } else if (lowerCommand.contains('relay 2') || lowerCommand.contains('relay two') || lowerCommand.contains('two')) {
      relayId = 'relay2';
    }

    if (relayId != null && (turnOn || turnOff)) {
      final status = turnOn ? 1 : 0;
      final relayName = relayId == "relay1" ? "Relay 1" : "Relay 2";
      
      _controlRelay(relayId, status);
      _playSound('success');
      
      // Voice response
      final response = turnOn 
          ? "Yes sir, I turned on $relayName"
          : "Yes sir, I turned off $relayName";
      _speak(response);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${turnOn ? "Turning ON" : "Turning OFF"} $relayName',
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: turnOn ? Colors.green : Colors.red,
        ),
      );
    } else {
      _playSound('error');
      _speak("Sorry sir, I didn't understand that command. Please try again.");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Command not recognized. Try: "Turn on relay 1" or "Turn off relay 2"'),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _controlRelay(String relayId, int status) async {
    try {
      // First, set mode to manual
      await getRTDBRef('Mode/$relayId').set(1);
      // Then set the status
      await getRTDBRef('RelayControl/$relayId').set(status);
    } catch (e) {
      debugPrint('Error controlling relay: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _playSound(String soundType) async {
    try {
      // Using system sounds - you can replace with actual audio files
      // For now, we'll use a simple beep pattern
      if (soundType == 'success') {
        // Success sound - can be replaced with actual audio file
        await _audioPlayer.play(AssetSource('sounds/success.mp3'));
      } else if (soundType == 'error') {
        // Error sound
        await _audioPlayer.play(AssetSource('sounds/error.mp3'));
      } else if (soundType == 'click') {
        // Click sound
        await _audioPlayer.play(AssetSource('sounds/click.mp3'));
      }
    } catch (e) {
      // Silently fail if audio files don't exist
      debugPrint('Audio playback error: $e');
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _speech.stop();
    _flutterTts.stop();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);
    final primary = const Color(0xFF6366F1);
    final secondary = const Color(0xFF8B5CF6);
    final accent = const Color(0xFF06B6D4);

    debugPrint('HomePage build - User: ${user?.email}');

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primary, secondary],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.home, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'Smart Home',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 20,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: IconButton(
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
              },
              tooltip: 'Logout',
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Animated background gradient
          AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color.lerp(primary, secondary, math.sin(_animationController.value * 2 * math.pi) * 0.5 + 0.5)!,
                        Color.lerp(secondary, accent, math.cos(_animationController.value * 2 * math.pi) * 0.5 + 0.5)!,
                        const Color(0xFFF8FAFC),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      color: Colors.white.withValues(alpha: 0.1),
                      child: CustomPaint(
                        painter: _BackgroundPatternPainter(_animationController.value),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // main content
          SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                // Trigger refresh by rebuilding
                setState(() {});
                await Future.delayed(const Duration(milliseconds: 500));
              },
              color: primary,
              backgroundColor: Colors.white.withValues(alpha: 0.9),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Enhanced header card with glassmorphism and image
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                            BoxShadow(
                              color: primary.withValues(alpha: 0.1),
                              blurRadius: 20,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Row(
                              children: [
                                // Image/Icon with enhanced animation
                                _AnimatedImageIcon(
                                  primary: primary,
                                  secondary: secondary,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Welcome Back!',
                                        style: theme.textTheme.titleLarge!.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          fontSize: 24,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.email_outlined,
                                            size: 16,
                                            color: Colors.white.withValues(alpha: 0.8),
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              user?.email ?? 'Unknown user',
                                              style: theme.textTheme.bodyMedium!.copyWith(
                                                color: Colors.white.withValues(alpha: 0.9),
                                                fontWeight: FontWeight.w500,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.eco,
                                    color: Colors.green.shade300,
                                    size: 28,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Enhanced section title
                      Row(
                        children: [
                          Container(
                            width: 4,
                            height: 24,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [primary, secondary],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 12),
                          _MultimediaText(
                            text: 'Current Sensor Readings',
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            animated: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // sensors grid (existing StreamBuilder kept)
                      StreamBuilder<DatabaseEvent>(
                        stream: getRTDBRef('Sensors').onValue,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            debugPrint('Sensor StreamBuilder error: ${snapshot.error}');
                            // Show default values instead of error to keep UI functional
                            return GridView.count(
                              shrinkWrap: true,
                              crossAxisCount:
                                  MediaQuery.of(context).size.width > 900
                                  ? 4
                                  : MediaQuery.of(context).size.width > 600
                                  ? 3
                                  : 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              physics: const NeverScrollableScrollPhysics(),
                              childAspectRatio: 1.2,
                              children: [
                                AnimatedSensorCard(
                                  icon: Icons.thermostat_outlined,
                                  label: 'Temperature',
                                  value: '0.0 °C',
                                  color: Colors.red.shade400,
                                  index: 0,
                                ),
                                AnimatedSensorCard(
                                  icon: Icons.water_drop,
                                  label: 'Humidity',
                                  value: '0.0 %',
                                  color: Colors.blue.shade400,
                                  index: 1,
                                ),
                                AnimatedSensorCard(
                                  icon: Icons.light_mode,
                                  label: 'Light (LDR)',
                                  value: "N/A",
                                  color: Colors.yellow.shade700,
                                  index: 2,
                                ),
                                AnimatedSensorCard(
                                  icon: Icons.waves,
                                  label: 'Ultrasonic',
                                  value: '0.0 cm',
                                  color: Colors.green.shade400,
                                  index: 3,
                                ),
                              ],
                            );
                          }
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return GridView.count(
                              shrinkWrap: true,
                              crossAxisCount:
                                  MediaQuery.of(context).size.width > 900
                                  ? 4
                                  : MediaQuery.of(context).size.width > 600
                                  ? 3
                                  : 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              physics: const NeverScrollableScrollPhysics(),
                              childAspectRatio: 1.2,
                              children: List.generate(4, (index) => _SkeletonCard()),
                            );
                          }
                          if (!snapshot.hasData ||
                              snapshot.data!.snapshot.value == null) {
                            // Show skeleton loaders if no data
                            return GridView.count(
                              shrinkWrap: true,
                              crossAxisCount:
                                  MediaQuery.of(context).size.width > 900
                                  ? 4
                                  : MediaQuery.of(context).size.width > 600
                                  ? 3
                                  : 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              physics: const NeverScrollableScrollPhysics(),
                              childAspectRatio: 1.2,
                              children: List.generate(4, (index) => _SkeletonCard()),
                            );
                          }

                          // Handle case where data might not be a Map
                          Map<dynamic, dynamic> data;
                          try {
                            data = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
                          } catch (e) {
                            debugPrint('Error parsing sensor data: $e');
                            // Show default values if data format is unexpected
                            data = {};
                          }
                          
                          final temp =
                              (data['Temperature'] as num?)?.toDouble() ?? 0.0;
                          final hum =
                              (data['Humidity'] as num?)?.toDouble() ?? 0.0;
                          final ldr = (data['LDR'] as int?) ?? 0;
                          final dist =
                              (data['Distance'] as num?)?.toDouble() ?? 0.0;

                          return GridView.count(
                            shrinkWrap: true,
                            crossAxisCount:
                                MediaQuery.of(context).size.width > 900
                                ? 4
                                : MediaQuery.of(context).size.width > 600
                                ? 3
                                : 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            physics: const NeverScrollableScrollPhysics(),
                            childAspectRatio: 1.2,
                            children: [
                              AnimatedSensorCard(
                                icon: Icons.thermostat_outlined,
                                label: 'Temperature',
                                value: '${temp.toStringAsFixed(1)} °C',
                                color: Colors.red.shade400,
                                index: 0,
                              ),
                              AnimatedSensorCard(
                                icon: Icons.water_drop,
                                label: 'Humidity',
                                value: '${hum.toStringAsFixed(1)} %',
                                color: Colors.blue.shade400,
                                index: 1,
                              ),
                              AnimatedSensorCard(
                                icon: Icons.light_mode,
                                label: 'Light (LDR)',
                                value: ldr == 0 ? "Bright" : "Dark",
                                color: ldr == 0
                                    ? Colors.yellow.shade700
                                    : Colors.white,
                                bgColor: ldr == 0
                                    ? Colors.yellow.shade100
                                    : Colors.blueGrey[900]!,
                                index: 2,
                              ),
                              AnimatedSensorCard(
                                icon: Icons.waves,
                                label: 'Ultrasonic',
                                value: '${dist.toStringAsFixed(1)} cm',
                                color: Colors.green.shade400,
                                index: 3,
                              ),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 32),

                      // Enhanced Relay title
                      Row(
                        children: [
                          Container(
                            width: 4,
                            height: 24,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [primary, secondary],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 12),
                          _MultimediaText(
                            text: 'Relay Control',
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            animated: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // relay controls (existing StreamBuilders kept)
                      StreamBuilder<DatabaseEvent>(
                        stream: getRTDBRef('Mode').onValue,
                        builder: (context, modeSnap) {
                          // Handle errors and loading states gracefully
                          int relay1Mode = 0;
                          int relay2Mode = 0;
                          
                          if (modeSnap.hasError) {
                            debugPrint('Mode StreamBuilder error: ${modeSnap.error}');
                            // Use default values (AUTO mode)
                            relay1Mode = 0;
                            relay2Mode = 0;
                          } else if (modeSnap.connectionState == ConnectionState.waiting ||
                              !modeSnap.hasData ||
                              modeSnap.data!.snapshot.value == null) {
                            // Use default values while loading
                            relay1Mode = 0;
                            relay2Mode = 0;
                          } else {
                            // Parse data safely
                            try {
                              final modeData = modeSnap.data!.snapshot.value as Map<dynamic, dynamic>;
                              relay1Mode = modeData['relay1'] as int? ?? 0;
                              relay2Mode = modeData['relay2'] as int? ?? 0;
                            } catch (e) {
                              debugPrint('Error parsing mode data: $e');
                              relay1Mode = 0;
                              relay2Mode = 0;
                            }
                          }

                          return StreamBuilder<DatabaseEvent>(
                            stream: getRTDBRef('RelayStatus').onValue,
                            builder: (context, statusSnap) {
                              // Handle errors and loading states gracefully
                              int relay1Status = 0;
                              int relay2Status = 0;
                              
                              if (statusSnap.hasError) {
                                debugPrint('RelayStatus StreamBuilder error: ${statusSnap.error}');
                                // Use default values (OFF)
                                relay1Status = 0;
                                relay2Status = 0;
                              } else if (statusSnap.connectionState == ConnectionState.waiting ||
                                  !statusSnap.hasData ||
                                  statusSnap.data!.snapshot.value == null) {
                                // Use default values while loading
                                relay1Status = 0;
                                relay2Status = 0;
                              } else {
                                // Parse data safely
                                try {
                                  final statusData = statusSnap.data!.snapshot.value as Map<dynamic, dynamic>;
                                  relay1Status = statusData['relay1'] as int? ?? 0;
                                  relay2Status = statusData['relay2'] as int? ?? 0;
                                } catch (e) {
                                  debugPrint('Error parsing status data: $e');
                                  relay1Status = 0;
                                  relay2Status = 0;
                                }
                              }

                              return Column(
                                children: [
                                  RelayControlCard(
                                    relayId: "relay1",
                                    label: "Relay 1 (Fan/Heater)",
                                    mode: relay1Mode,
                                    status: relay1Status,
                                  ),
                                  const SizedBox(height: 14),
                                  RelayControlCard(
                                    relayId: "relay2",
                                    label: "Relay 2 (Light)",
                                    mode: relay2Mode,
                                    status: relay2Status,
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ),
          ),
        ],
      ),
      floatingActionButton: _VoiceCommandButton(
        isListening: _isListening,
        onPressed: _isListening ? _stopListening : _startListening,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

// ===================================================================
// SENSOR CARD - Reusable UI Component
// ===================================================================
class SensorCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color bgColor;

  const SensorCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.bgColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = bgColor == Colors.white ? Colors.black : Colors.white;

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: bgColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: color.withValues(alpha: 0.2),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 10),
            Text(label, style: TextStyle(color: textColor.withValues(alpha: 0.7))),
            const SizedBox(height: 5),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===================================================================
// RELAY CONTROL CARD - UI Component for Mode and Status Control
// ===================================================================
class RelayControlCard extends StatelessWidget {
  final String relayId;
  final String label;
  final int mode; // 0 auto, 1 manual
  final int status; // 0 off, 1 on

  const RelayControlCard({
    super.key,
    required this.relayId,
    required this.label,
    required this.mode,
    required this.status,
  });

  Future<void> _toggleMode(bool isManual) async {
    try {
      await getRTDBRef('Mode/$relayId').set(isManual ? 1 : 0);
    } catch (e) {
      // keep console debugging short
      debugPrint('toggleMode error: $e');
    }
  }

  Future<void> _setManualStatus(int newStatus) async {
    try {
      await getRTDBRef('RelayControl/$relayId').set(newStatus);
    } catch (e) {
      debugPrint('setManualStatus error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Enhanced header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.2),
                      Colors.white.withValues(alpha: 0.1),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.white.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        relayId == "relay1" ? Icons.ac_unit : Icons.lightbulb,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, anim) => ScaleTransition(
                        scale: anim,
                        child: FadeTransition(opacity: anim, child: child),
                      ),
                      child: Container(
                        key: ValueKey(status),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: status == 1
                                ? [Colors.green.shade400, Colors.green.shade600]
                                : [Colors.red.shade400, Colors.red.shade600],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: (status == 1
                                      ? Colors.green
                                      : Colors.red)
                                  .withValues(alpha: 0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                            if (status == 1)
                              BoxShadow(
                                color: Colors.green.withValues(alpha: 0.6),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _PulsingStatusDot(
                              isActive: status == 1,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              status == 1 ? 'ON' : 'OFF',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Enhanced body
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            "Control Mode:",
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: mode == 1
                                ? Colors.blue.withValues(alpha: 0.3)
                                : Colors.grey.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: mode == 1
                                  ? Colors.blue.shade300
                                  : Colors.grey.shade300,
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            mode == 1 ? "MANUAL" : "AUTO",
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: mode == 1
                                  ? Colors.blue.shade200
                                  : Colors.grey.shade200,
                              fontSize: 13,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Switch(
                          value: mode == 1,
                          activeColor: Colors.blue.shade400,
                          activeTrackColor: Colors.blue.shade300,
                          inactiveThumbColor: Colors.grey.shade300,
                          inactiveTrackColor: Colors.grey.shade600,
                          onChanged: (v) async => await _toggleMode(v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (mode == 1)
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.green.shade400,
                                    Colors.green.shade600,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.green.withValues(alpha: 0.4),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () async => await _setManualStatus(1),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: const [
                                        Icon(
                                          Icons.power,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Turn ON',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.red.shade300,
                                  width: 2,
                                ),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () async => await _setManualStatus(0),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.power_off,
                                          color: Colors.red.shade300,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Turn OFF',
                                          style: TextStyle(
                                            color: Colors.red.shade300,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    if (mode == 0) const SizedBox(height: 8),
                    if (mode == 0)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.orange.shade700,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                "Relay is controlled automatically by ESP32 based on sensor readings (AUTO Mode).",
                                style: TextStyle(
                                  color: Colors.orange.shade900,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Interactive card with scale animation on tap
class _InteractiveCard extends StatefulWidget {
  final Widget child;

  const _InteractiveCard({required this.child});

  @override
  State<_InteractiveCard> createState() => _InteractiveCardState();
}

class _InteractiveCardState extends State<_InteractiveCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: widget.child,
      ),
    );
  }
}

// AnimatedSensorCard — Enhanced glassmorphism design
class AnimatedSensorCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color bgColor;
  final int index;

  const AnimatedSensorCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.bgColor = Colors.white,
    this.index = 0,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = bgColor != Colors.white;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 500 + (index * 100)),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) {
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - v)),
            child: Transform.scale(
              scale: 0.9 + (0.1 * v),
              child: child,
            ),
          ),
        );
      },
      child: _InteractiveCard(
        child: Container(
          decoration: BoxDecoration(
            color: isDark 
                ? bgColor.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: color.withValues(alpha: 0.1),
                blurRadius: 15,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            color.withValues(alpha: 0.3),
                            color.withValues(alpha: 0.1),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        icon,
                        color: isDark ? Colors.white : color,
                        size: 22,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      style: TextStyle(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.8)
                            : Colors.white.withValues(alpha: 0.9),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : Colors.white,
                          letterSpacing: 0.5,
                        ),
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Background pattern painter for animated decorative elements
class _BackgroundPatternPainter extends CustomPainter {
  final double animationValue;

  _BackgroundPatternPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;

    // Draw animated circles
    for (int i = 0; i < 5; i++) {
      final radius = (100.0 + (i * 50.0));
      final x = size.width * (0.2 + (i * 0.15));
      final y = size.height * (0.3 + (i * 0.1));
      final offset = Offset(
        x + math.sin(animationValue * 2 * math.pi + i) * 30,
        y + math.cos(animationValue * 2 * math.pi + i) * 30,
      );

      canvas.drawCircle(offset, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Voice command floating action button
class _VoiceCommandButton extends StatefulWidget {
  final bool isListening;
  final VoidCallback onPressed;

  const _VoiceCommandButton({
    required this.isListening,
    required this.onPressed,
  });

  @override
  State<_VoiceCommandButton> createState() => _VoiceCommandButtonState();
}

class _VoiceCommandButtonState extends State<_VoiceCommandButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: widget.isListening
                  ? [Colors.red.shade400, Colors.red.shade600]
                  : [const Color(0xFF6366F1), const Color(0xFF8B5CF6)],
            ),
            boxShadow: widget.isListening
                ? [
                    BoxShadow(
                      color: Colors.red.withValues(alpha: 0.4 + (_pulseController.value * 0.3)),
                      blurRadius: 20 + (_pulseController.value * 10),
                      spreadRadius: 2 + (_pulseController.value * 3),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onPressed,
              borderRadius: BorderRadius.circular(32),
              child: Center(
                child: widget.isListening
                    ? const Icon(
                        Icons.mic,
                        color: Colors.white,
                        size: 28,
                      )
                    : const Icon(
                        Icons.mic_none,
                        color: Colors.white,
                        size: 28,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// Animated image/icon component with multimedia effects
class _AnimatedImageIcon extends StatefulWidget {
  final Color primary;
  final Color secondary;

  const _AnimatedImageIcon({
    required this.primary,
    required this.secondary,
  });

  @override
  State<_AnimatedImageIcon> createState() => _AnimatedImageIconState();
}

class _AnimatedImageIconState extends State<_AnimatedImageIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [widget.primary, widget.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.primary.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.sensors,
              color: Colors.white,
              size: 32,
            ),
          ),
        );
      },
    );
  }
}

// Enhanced text with multimedia styling
class _MultimediaText extends StatelessWidget {
  final String text;
  final double fontSize;
  final FontWeight fontWeight;
  final Color color;
  final bool animated;

  const _MultimediaText({
    required this.text,
    this.fontSize = 16,
    this.fontWeight = FontWeight.normal,
    this.color = Colors.white,
    this.animated = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget textWidget = Text(
      text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: 0.3,
        shadows: [
          Shadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );

    if (animated) {
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 800),
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, 10 * (1 - value)),
              child: child,
            ),
          );
        },
        child: textWidget,
      );
    }

    return textWidget;
  }
}

// Pulsing status dot for active states
class _PulsingStatusDot extends StatefulWidget {
  final bool isActive;
  final Color color;

  const _PulsingStatusDot({
    required this.isActive,
    required this.color,
  });

  @override
  State<_PulsingStatusDot> createState() => _PulsingStatusDotState();
}

class _PulsingStatusDotState extends State<_PulsingStatusDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _opacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Pulsing ring
            Transform.scale(
              scale: _scaleAnimation.value,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: _opacityAnimation.value * 0.5),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            // Solid dot
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.8),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// Skeleton loader card
class _SkeletonCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Shimmer(
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _Shimmer(
                  child: Container(
                    width: 80,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                _Shimmer(
                  child: Container(
                    width: 60,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Shimmer effect for skeleton loaders
class _Shimmer extends StatefulWidget {
  final Widget child;

  const _Shimmer({required this.child});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: 0.3 + (math.sin(_controller.value * 2 * math.pi) * 0.5 + 0.5) * 0.4,
          child: widget.child,
        );
      },
    );
  }
}
