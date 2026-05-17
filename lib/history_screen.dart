import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _timeFrame = 'Day'; 
  List<FlSpot> _chartData = [];
  bool _isLoading = true;

  double _minX = 0;
  double _maxX = 0;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    setState(() => _isLoading = true);
    
    DateTime now = DateTime.now();
    DateTime filterDate;

    if (_timeFrame == 'Day') {
      filterDate = now.subtract(const Duration(days: 1));
    } else if (_timeFrame == 'Week') {
      filterDate = now.subtract(const Duration(days: 7));
    } else {
      filterDate = now.subtract(const Duration(days: 30));
    }

    _minX = filterDate.millisecondsSinceEpoch.toDouble();
    _maxX = now.millisecondsSinceEpoch.toDouble();

    try {
      final response = await Supabase.instance.client
          .from('gas_logs')
          .select('created_at, gas_level')
          .gte('created_at', filterDate.toIso8601String())
          .order('created_at', ascending: true);

      final List data = response as List;

      setState(() {
        _chartData = data.map((row) {
          DateTime time = DateTime.parse(row['created_at']).toLocal();
          return FlSpot(
            time.millisecondsSinceEpoch.toDouble(), 
            row['gas_level'].toDouble()
          );
        }).toList();
        
        _isLoading = false;
      });
    } catch (e) {
      print("Error fetching history: $e");
      setState(() => _isLoading = false);
    }
  }

  double _getXInterval() {
    if (_timeFrame == 'Day') {
      return 1000 * 60 * 60 * 4; 
    } else if (_timeFrame == 'Week') {
      return 1000 * 60 * 60 * 24; 
    } else {
      return 1000 * 60 * 60 * 24 * 5; 
    }
  }

  // --- THESE WERE THE MISSING FUNCTIONS ---
  Widget _bottomTitleWidgets(double value, TitleMeta meta) {
    DateTime date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
    String text = '';

    if (_timeFrame == 'Day') {
      text = '${date.hour}:00'; 
    } else if (_timeFrame == 'Week') {
      List<String> weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      text = weekdays[date.weekday - 1]; 
    } else {
      text = '${date.day}/${date.month}'; 
    }

    return SideTitleWidget(
      meta: meta, // Using the new fl_chart grammar!
      space: 10,
      child: Text(text, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  Widget _leftTitleWidgets(double value, TitleMeta meta) {
    if (value % 100 != 0) return Container();
    
    return SideTitleWidget(
      meta: meta, // Using the new fl_chart grammar!
      child: Text('${value.toInt()}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
    );
  }
  // --- END OF HELPER FUNCTIONS ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detection History')),
      body: Column(
        children: [
          const SizedBox(height: 20),
          
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Day', label: Text('24 Hours')),
              ButtonSegment(value: 'Week', label: Text('7 Days')),
              ButtonSegment(value: 'Month', label: Text('30 Days')),
            ],
            selected: {_timeFrame},
            onSelectionChanged: (Set<String> newSelection) {
              setState(() {
                _timeFrame = newSelection.first;
                _fetchHistory();
              });
            },
          ),
          
          const SizedBox(height: 40),
          
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 30.0, left: 10.0, top: 20, bottom: 20),
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator())
                : _chartData.isEmpty 
                  ? const Center(child: Text("No data for this time period.", style: TextStyle(color: Colors.grey)))
                  
                  // THE PINCH TO ZOOM WRAPPER
                  : InteractiveViewer(
                      panEnabled: true, 
                      scaleEnabled: true, 
                      minScale: 0.5, 
                      maxScale: 5.0, 
                      boundaryMargin: const EdgeInsets.all(20), 
                      
                      child: LineChart(
                        LineChartData(
                          minX: _minX, 
                          maxX: _maxX, 
                          minY: 0,     
                          
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: true,
                            horizontalInterval: 100,
                            verticalInterval: _getXInterval(),
                            getDrawingHorizontalLine: (value) {
                              if (value == 250) {
                                return const FlLine(color: Colors.redAccent, strokeWidth: 1, dashArray: [5, 5]);
                              }
                              return const FlLine(color: Colors.white10, strokeWidth: 1);
                            },
                            getDrawingVerticalLine: (value) => const FlLine(color: Colors.white10, strokeWidth: 1),
                          ),
                          
                          titlesData: FlTitlesData(
                            show: true,
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 40,
                                interval: _getXInterval(),
                                getTitlesWidget: _bottomTitleWidgets, // Reconnected!
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 40,
                                interval: 100,
                                getTitlesWidget: _leftTitleWidgets, // Reconnected!
                              ),
                            ),
                          ),
                          
                          borderData: FlBorderData(show: true, border: Border.all(color: Colors.white10)),
                          
                          lineBarsData: [
                            LineChartBarData(
                              spots: _chartData,
                              isCurved: true,
                              color: Colors.greenAccent,
                              barWidth: 3,
                              isStrokeCapRound: true,
                              dotData: const FlDotData(show: false), 
                              belowBarData: BarAreaData(
                                show: true,
                                color: Colors.greenAccent.withAlpha(30),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}