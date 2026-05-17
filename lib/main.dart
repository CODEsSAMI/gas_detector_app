import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'history_screen.dart';
import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial_ble.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';


final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Supabase.initialize(
    url: 'https://meevvocmfquedgepyjpl.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1lZXZ2b2NtZnF1ZWRnZXB5anBsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc1NzM5NTksImV4cCI6MjA5MzE0OTk1OX0.rIyCPZbWNwOPHHYO1qOCLbAM87lcS4pPMQTSmMK4PfA',
  );
  
  runApp(const GasDetectorApp());
}

class GasDetectorApp extends StatelessWidget {
  const GasDetectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gas Detector',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          elevation: 0,
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool isConnected = false;
  int currentGasLevel = 0; 
  BluetoothConnection? connection;
  String incomingDataBuffer = ""; 

  // Variables for Peak Hold and Database Throttle
  DateTime _lastSaveTime = DateTime.now();
  DateTime _lastCriticalSaveTime = DateTime.now();
  int peakGasInWindow = 0; 

  @override
  void initState() {
    super.initState();
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
    flutterLocalNotificationsPlugin.initialize(settings: initializationSettings);
  }

  Future<void> _connectToHardware() async {
    List<BluetoothDevice> devices = [];
    try {
      devices = await FlutterBluetoothSerial.instance.getBondedDevices();
    } catch (e) {
      print("Error: $e");
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('Select Sensor Module'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: devices.length,
              itemBuilder: (context, index) {
                return ListTile(
                  leading: const Icon(Icons.bluetooth, color: Colors.blueAccent),
                  title: Text(devices[index].name ?? "Unknown Device"),
                  subtitle: Text(devices[index].address),
                  onTap: () {
                    Navigator.pop(context); 
                    _startConnection(devices[index]); 
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _startConnection(BluetoothDevice server) async {
    try {
      connection = await BluetoothConnection.toAddress(server.address);
      setState(() => isConnected = true);

      connection!.input!.listen((Uint8List data) {
        String asciiString = ascii.decode(data);
        print("RAW DATA FROM HC-05: $asciiString"); 
        
        incomingDataBuffer += asciiString;

        if (incomingDataBuffer.contains('\n')) {
          List<String> lines = incomingDataBuffer.split('\n');
          String completeData = lines.first.trim();
          incomingDataBuffer = lines.length > 1 ? lines[1] : "";

          if (completeData.isNotEmpty) {
            int? parsedValue = int.tryParse(completeData);
            
            if (parsedValue != null) {
              setState(() {
                currentGasLevel = parsedValue; 
              });

              // Constantly update the peak value
              if (parsedValue > peakGasInWindow) {
                peakGasInWindow = parsedValue;
              }

              DateTime now = DateTime.now();

              // Immediate Critical Save (with a 5-second debounce)
              if (parsedValue > 250 && now.difference(_lastCriticalSaveTime).inSeconds > 5) {
                _saveToDatabase(parsedValue);
                _lastCriticalSaveTime = now;
                _triggerNotification(parsedValue); // Activated!
              } 
              // Routine 30-second Save (Saves the peak, not the current!)
              else if (now.difference(_lastSaveTime).inSeconds >= 30) {
                _saveToDatabase(peakGasInWindow);
                _lastSaveTime = now;
                peakGasInWindow = 0; // Reset for the next 30 seconds
              }
            }
          }
        }
      }).onDone(() {
        setState(() => isConnected = false);
      });
    } catch (e) {
      print('Cannot connect, exception occurred: $e');
    }
  }

  Future<void> _saveToDatabase(int level) async {
    try {
      await Supabase.instance.client.from('gas_logs').insert({'gas_level': level});
      print("✅ Successfully logged $level ppm to Supabase");
    } catch (e) {
      print('❌ Database Error: $e');
    }
  }

  Future<void> _triggerNotification(int gasLevel) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'gas_alerts', 'Gas Leaks',
      importance: Importance.max,
      priority: Priority.high,
      color: Colors.red,
      enableVibration: true,
    );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);
    
    await flutterLocalNotificationsPlugin.show(
      id: 0, 
      title: '⚠️ CRITICAL GAS WARNING', 
      body: 'Gas level reached $gasLevel ppm! Evacuate or check ventilation.', 
      notificationDetails: platformChannelSpecifics,
    );
  }


  // Generate CSV Report (Manual Method)
  Future<void> _generateReport() async {
    try {
      final response = await Supabase.instance.client
          .from('gas_logs')
          .select()
          .order('created_at', ascending: false);
          
      final List data = response as List;
      
      // 1. Build the CSV String manually (No package needed!)
      String csvContent = "Date & Time,Gas Level (ppm),Status\n";

      for (var row in data) {

        
        DateTime time = DateTime.parse(row['created_at']).toLocal(); 
        
        // This grabs the exact same text ('SAFE', 'WARNING', etc.) that your UI uses!
        String status = getStatusInfo(row['gas_level'])['text']; 
        
        csvContent += "${time.toString()},${row['gas_level']},$status\n";
      }

      // 2. Save it to the phone
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/gas_sensor_report.csv';
      final file = File(path);
      await file.writeAsString(csvContent);

      // 3. Open the Share menu
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path)],
          text: 'Gas Sensor Data Report',
        ),
      );
    } catch (e) {
      print("Error generating report: $e");
    }
  }



  Map<String, dynamic> getStatusInfo(int level) {
    if (level < 100) return {'text': 'SAFE', 'color': Colors.green, 'status': 'Normal air quality.'};
    if (level < 200) return {'text': 'MILD', 'color': Colors.yellow, 'status': 'Slight gas detected.'};
    if (level < 300) return {'text': 'WARNING', 'color': Colors.orange, 'status': 'Warning: Moderate leak.'};
    if (level < 400) return {'text': 'EXTREME', 'color': Colors.red, 'status': 'DANGER: High leak!'};
    return {'text': 'CRITICAL', 'color': Colors.purple, 'status': 'EVACUATE IMMEDIATELY'};
  }

  @override
  Widget build(BuildContext context) {
    final info = getStatusInfo(currentGasLevel);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sensor Dashboard'),
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Color(0xFF1E1E1E)),
              child: Text('Gas Detector Pro', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: Icon(isConnected ? Icons.bluetooth_connected : Icons.bluetooth, 
                            color: isConnected ? Colors.green : Colors.white),
              title: Text(isConnected ? 'Connected to HC-05' : 'Connect Hardware'),
              onTap: () {
                Navigator.pop(context); 
                if (!isConnected) {
                  _connectToHardware();
                } else {
                  connection?.dispose();
                  setState(() => isConnected = false);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Detection History'),
              onTap: () {
                Navigator.pop(context); 
                Navigator.push(context, MaterialPageRoute(builder: (context) => const HistoryScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.assessment),
              title: const Text('Generate Report'),
              onTap: () { 
                Navigator.pop(context);
                _generateReport(); // Export report triggered here!
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications_active),
              title: const Text('Alert Settings'),
              onTap: () {},
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.info),
              title: const Text('About'),
              onTap: () {},
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 40),
          Center(
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: info['color'], width: 8),
                boxShadow: [
                  BoxShadow(color: info['color'].withAlpha(100), blurRadius: 30, spreadRadius: 2)
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$currentGasLevel', style: const TextStyle(fontSize: 80, fontWeight: FontWeight.bold)),
                  const Text('ppm', style: TextStyle(fontSize: 24, color: Colors.grey)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 50),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: info['color'].withAlpha(40),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: info['color']),
            ),
            child: Column(
              children: [
                Text(info['text'], style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: info['color'])),
                const SizedBox(height: 10),
                Text(info['status'], textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}