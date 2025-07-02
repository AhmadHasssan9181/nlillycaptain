import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/history_service.dart';
import '../passenger_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final historyServiceProvider = Provider<HistoryService>((ref) => HistoryService());
final selectedDateRangeProvider = StateProvider<DateTimeRange?>((ref) => null);

class RideHistoryScreen extends ConsumerStatefulWidget {
  final Function() onBackPressed;

  const RideHistoryScreen({Key? key, required this.onBackPressed}) : super(key: key);

  @override
  ConsumerState<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends ConsumerState<RideHistoryScreen> {
  bool _isLoading = true;
  List<PassengerRequest> _rides = [];
  String _filterStatus = 'All';
  String _errorMessage = '';
  final List<String> _statusFilters = ['All', 'Completed', 'Cancelled'];

  @override
  void initState() {
    super.initState();
    _loadRideHistory();
  }

  Future<void> _loadRideHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final historyService = ref.read(historyServiceProvider);
      final dateRange = ref.read(selectedDateRangeProvider);

      final rides = await historyService.getCompletedRides(
        startDate: dateRange?.start,
        endDate: dateRange?.end,
      );

      // Apply status filter if not 'All'
      final filteredRides = _filterStatus == 'All'
          ? rides
          : rides.where((ride) =>
      ride.status.toLowerCase() == _filterStatus.toLowerCase()).toList();

      setState(() {
        _rides = filteredRides;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load ride history: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _selectDateRange() async {
    final initialDateRange = ref.read(selectedDateRangeProvider) ??
        DateTimeRange(
          start: DateTime.now().subtract(Duration(days: 30)),
          end: DateTime.now(),
        );

    final newDateRange = await showDateRangePicker(
      context: context,
      initialDateRange: initialDateRange,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(
              primary: Color(0xFFFF4B6C),
              onPrimary: Colors.white,
              surface: Color(0xFF333333),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: Color(0xFF222222),
          ),
          child: child!,
        );
      },
    );

    if (newDateRange != null) {
      ref.read(selectedDateRangeProvider.notifier).state = newDateRange;
      _loadRideHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateRange = ref.watch(selectedDateRangeProvider);
    String dateRangeText = 'All Time';

    if (dateRange != null) {
      final start = DateFormat('MMM d, y').format(dateRange.start);
      final end = DateFormat('MMM d, y').format(dateRange.end);
      dateRangeText = '$start - $end';
    }

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
          'Ride History',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadRideHistory,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Section
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Color(0xFF1A1A1A),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filters',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    // Date Range Filter
                    Expanded(
                      child: GestureDetector(
                        onTap: _selectDateRange,
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          decoration: BoxDecoration(
                            color: Color(0xFF2A2A2A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Color(0xFF444444)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.date_range, color: Color(0xFFFF4B6C), size: 16),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  dateRangeText,
                                  style: TextStyle(color: Colors.white),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    // Status Filter
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Color(0xFF444444)),
                      ),
                      child: DropdownButton<String>(
                        value: _filterStatus,
                        icon: Icon(Icons.arrow_drop_down, color: Colors.white),
                        dropdownColor: Color(0xFF2A2A2A),
                        underline: SizedBox(),
                        style: TextStyle(color: Colors.white),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            setState(() {
                              _filterStatus = newValue;
                            });
                            _loadRideHistory();
                          }
                        },
                        items: _statusFilters.map<DropdownMenuItem<String>>((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Results Count
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Color(0xFF222222),
            child: Row(
              children: [
                Text(
                  'Results: ${_rides.length}',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Spacer(),
                if (!_isLoading && _rides.isNotEmpty)
                  Text(
                    'Total: ${_calculateTotal()} PKR',
                    style: TextStyle(
                      color: Color(0xFFFF4B6C),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),

          // Ride List
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: Color(0xFFFF4B6C)))
                : _errorMessage.isNotEmpty
                ? Center(
              child: Text(
                _errorMessage,
                style: TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            )
                : _rides.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history,
                    color: Colors.grey,
                    size: 64,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No rides found',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 18,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Try adjusting your filters',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: EdgeInsets.all(16),
              itemCount: _rides.length,
              itemBuilder: (context, index) {
                return _buildRideCard(_rides[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  int _calculateTotal() {
    return _rides.fold(0, (sum, ride) => sum + ride.fare);
  }

  Widget _buildRideCard(PassengerRequest ride) {
    // Format date
    final rideDate = ride.timestamp;
    final formattedDate = DateFormat('MMM d, y').format(rideDate);
    final formattedTime = DateFormat('h:mm a').format(rideDate);

    // Determine status color
    Color statusColor;
    IconData statusIcon;

    switch (ride.status.toLowerCase()) {
      case 'completed':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'cancelled':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = Colors.orange;
        statusIcon = Icons.pending;
    }

    return Card(
      margin: EdgeInsets.only(bottom: 16),
      color: Color(0xFF2A2A2A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Color(0xFF444444),
          width: 1,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header - Date, Time, Status, Fare
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date and Time
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formattedDate,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      formattedTime,
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                Spacer(),
                // Status
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        statusIcon,
                        color: statusColor,
                        size: 12,
                      ),
                      SizedBox(width: 4),
                      Text(
                        ride.status,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                // Fare
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Color(0xFFFF4B6C).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Color(0xFFFF4B6C).withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '${ride.fare} PKR',
                    style: TextStyle(
                      color: Color(0xFFFF4B6C),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Divider(color: Color(0xFF444444)),
            SizedBox(height: 12),

            // Passenger info
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundImage: NetworkImage(ride.passengerImage),
                ),
                SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ride.passengerName,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: [
                        Icon(
                          Icons.star,
                          color: Colors.amber,
                          size: 12,
                        ),
                        SizedBox(width: 2),
                        Text(
                          ride.passengerRating.toStringAsFixed(1),
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Color(0xFF333333),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${ride.distanceKm.toStringAsFixed(1)} km',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),

            // Location details
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Pickup location
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.location_on,
                            color: Color(0xFFFF4B6C),
                            size: 16,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Pickup',
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  ride.pickupAddress,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      // Destination location
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.flag,
                            color: Colors.green,
                            size: 16,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Destination',
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  ride.destinationAddress,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}