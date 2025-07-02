import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/history_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Create providers
final historyServiceProvider = Provider<HistoryService>((ref) => HistoryService());
final selectedPeriodProvider = StateProvider<String>((ref) => 'month');

// Brand new class with different name
class DriverEarningsScreen extends ConsumerStatefulWidget {
  final Function() onBackPressed;

  const DriverEarningsScreen({Key? key, required this.onBackPressed}) : super(key: key);

  @override
  ConsumerState<DriverEarningsScreen> createState() => _DriverEarningsScreenState();
}

class _DriverEarningsScreenState extends ConsumerState<DriverEarningsScreen> {
  bool _isLoading = true;
  String _errorMessage = '';
  Map<String, dynamic> _earningsSummary = {};
  List<Map<String, dynamic>> _chartData = [];

  @override
  void initState() {
    super.initState();
    _loadEarningsData();
  }

  Future<void> _loadEarningsData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final historyService = ref.read(historyServiceProvider);
      final selectedPeriod = ref.read(selectedPeriodProvider);

      // Load summary data
      final summary = await historyService.getEarningsSummary(period: selectedPeriod);

      // Load chart data
      final chartData = await historyService.getEarningsChartData(period: selectedPeriod);

      setState(() {
        _earningsSummary = summary;
        _chartData = chartData;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load earnings data: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF111111),
      appBar: AppBar(
        backgroundColor: Color(0xFF1A1A1A),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: widget.onBackPressed,
        ),
        title: Text(
          'Earnings',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadEarningsData,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: Color(0xFFFF4B6C)))
          : _errorMessage.isNotEmpty
          ? Center(
        child: Text(
          _errorMessage,
          style: TextStyle(color: Colors.red),
          textAlign: TextAlign.center,
        ),
      )
          : SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Period selector
            _buildPeriodSelector(),

            SizedBox(height: 24),

            // Summary Stats
            _buildStatCards(),

            SizedBox(height: 24),

            // Chart
            _buildChartSection(),

            SizedBox(height: 24),

            // Performance Stats
            _buildStatsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    final selectedPeriod = ref.watch(selectedPeriodProvider);

    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color(0xFF222222),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color(0xFF333333)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildPeriodButton('today', 'Today', selectedPeriod),
          _buildPeriodButton('week', 'This Week', selectedPeriod),
          _buildPeriodButton('month', 'This Month', selectedPeriod),
          _buildPeriodButton('all', 'All Time', selectedPeriod),
        ],
      ),
    );
  }

  Widget _buildPeriodButton(String value, String label, String selectedValue) {
    final isSelected = selectedValue == value;

    return GestureDetector(
      onTap: () {
        ref.read(selectedPeriodProvider.notifier).state = value;
        _loadEarningsData();
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Color(0xFFFF4B6C) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildStatCards() {
    final totalEarnings = _earningsSummary['totalEarnings'] ?? 0;
    final periodEarnings = _earningsSummary['periodEarnings'] ?? 0;
    final totalRides = _earningsSummary['totalRides'] ?? 0;
    final periodRides = _earningsSummary['periodRides'] ?? 0;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Period Earnings',
                '$periodEarnings PKR',
                Icons.payments,
                Color(0xFFFF4B6C),
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: _buildStatCard(
                'Total Earnings',
                '$totalEarnings PKR',
                Icons.account_balance_wallet,
                Colors.green,
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Period Rides',
                periodRides.toString(),
                Icons.directions_car,
                Colors.blue,
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: _buildStatCard(
                'Total Rides',
                totalRides.toString(),
                Icons.timeline,
                Colors.amber,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(
      String title,
      String value,
      IconData icon,
      Color iconColor,
      ) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFF222222),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color(0xFF333333)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 16,
                ),
              ),
              SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartSection() {
    if (_chartData.isEmpty) {
      return Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Color(0xFF222222),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Color(0xFF333333)),
        ),
        child: Center(
          child: Text(
            'No earnings data available for selected period',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final labels = _chartData.map((data) => data['date'] as String).toList();
    final values = _chartData.map((data) => data['earnings'] as int).toList();
    final maxValue = values.isEmpty ? 0 : values.reduce((a, b) => a > b ? a : b);

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFF222222),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color(0xFF333333)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Earnings Trend',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 24),

          // Custom chart implementation
          SizedBox(
            height: 240,
            child: _buildCustomBarChart(labels, values, maxValue),
          ),
        ],
      ),
    );
  }

  // Custom bar chart implementation
  Widget _buildCustomBarChart(List<String> labels, List<int> values, int maxValue) {
    return Column(
      children: [
        // Chart container
        Expanded(
          child: Container(
            padding: EdgeInsets.only(top: 20, right: 20),
            child: LayoutBuilder(
                builder: (context, constraints) {
                  // Calculate bar width based on available space
                  final availableWidth = constraints.maxWidth;
                  final barCount = values.length;
                  final barWidth = (availableWidth / barCount) * 0.6; // 60% of available width per bar
                  final spacing = (availableWidth / barCount) * 0.4; // 40% spacing

                  // Render y-axis scale
                  return Stack(
                    children: [
                      // Y-axis lines
                      ..._buildYAxisLines(maxValue, constraints.maxHeight),

                      // Y-axis labels
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: 30,
                        child: _buildYAxisLabels(maxValue, constraints.maxHeight),
                      ),

                      // Bars
                      Positioned(
                        left: 30, // Give space for y-axis labels
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(values.length, (index) {
                            final double barHeight = maxValue > 0
                                ? (values[index] / maxValue) * (constraints.maxHeight - 30)
                                : 0;

                            return _buildBar(
                                barWidth,
                                barHeight,
                                labels[index],
                                values[index]
                            );
                          }),
                        ),
                      ),
                    ],
                  );
                }
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildYAxisLines(int maxValue, double height) {
    final divisions = 5; // Number of horizontal lines
    final List<Widget> lines = [];

    for (int i = 0; i <= divisions; i++) {
      final lineY = height - ((height / divisions) * i);

      lines.add(
          Positioned(
            left: 30, // Start after y-axis labels
            right: 0,
            top: lineY,
            child: Container(
              height: 1,
              color: Color(0xFF333333), // Subtle grid line
            ),
          )
      );
    }

    return lines;
  }

  Widget _buildYAxisLabels(int maxValue, double height) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(6, (index) {
        final value = (maxValue / 5 * index).toInt();
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(
            value.toString(),
            style: TextStyle(color: Colors.grey, fontSize: 10),
          ),
        );
      }).reversed.toList(), // Reverse to show in ascending order from bottom
    );
  }

  Widget _buildBar(double width, double height, String label, int value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Value tooltip
        Container(
          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Color(0xFF333333),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            value.toString(),
            style: TextStyle(
              color: Color(0xFFFF4B6C),
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        SizedBox(height: 4),

        // The bar itself
        Container(
          width: width,
          height: height > 0 ? height : 1, // Minimum height for empty bars
          decoration: BoxDecoration(
            color: Color(0xFFFF4B6C),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(4),
            ),
            // Add gradient for nicer appearance
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFFF4B6C),
                Color(0xFFFF6B8C),
              ],
            ),
          ),
        ),

        SizedBox(height: 8),

        // Date label
        Text(
          label,
          style: TextStyle(color: Colors.grey, fontSize: 10),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildStatsSection() {
    final averageFare = _earningsSummary['averageFare'] ?? 0;
    final periodRides = _earningsSummary['periodRides'] ?? 0;
    final totalRides = _earningsSummary['totalRides'] ?? 0;

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFF222222),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color(0xFF333333)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Performance Stats',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 16),

          // Average fare
          _buildStatRow(
            Icons.trending_up,
            Colors.green,
            'Average Fare:',
            '${averageFare.toStringAsFixed(0)} PKR',
          ),

          SizedBox(height: 12),

          // Percentage
          _buildStatRow(
            Icons.pie_chart,
            Color(0xFFFF4B6C),
            'Percentage of Total Rides:',
            totalRides > 0 ? '${((periodRides / totalRides) * 100).toStringAsFixed(1)}%' : '0%',
          ),

          SizedBox(height: 12),

          // Daily average
          _buildStatRow(
            Icons.date_range,
            Colors.blue,
            'Daily Average (Period):',
            _calculateDailyAverage(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(IconData icon, Color iconColor, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 16),
        SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(color: Colors.grey),
        ),
        Spacer(),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  String _calculateDailyAverage() {
    final selectedPeriod = ref.read(selectedPeriodProvider);
    final periodRides = _earningsSummary['periodRides'] ?? 0;

    int days = 1;

    switch (selectedPeriod) {
      case 'today':
        days = 1;
        break;
      case 'week':
        days = 7;
        break;
      case 'month':
        days = 30;
        break;
      case 'all':
        days = 90;
        break;
    }

    final average = periodRides / days;
    return '${average.toStringAsFixed(1)} rides/day';
  }
}