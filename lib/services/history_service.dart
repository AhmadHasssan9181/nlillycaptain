import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../passenger_model.dart';

class HistoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get driver's completed rides history
  Future<List<PassengerRequest>> getCompletedRides({
    DateTime? startDate,
    DateTime? endDate,
    int limit = 50,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        print('No authenticated user found');
        return [];
      }

      print('Fetching ride history for driver ${currentUser.uid}');

      // Create base query for completed rides
      Query query = _firestore.collection('PassengerRequests')
          .where('confirmedDriverId', isEqualTo: currentUser.uid)
          .where('status', isEqualTo: 'completed')
          .orderBy('completedAt', descending: true);

      // Apply date filters if specified
      if (startDate != null) {
        query = query.where('completedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
      }

      if (endDate != null) {
        // Add one day to include the entire end date
        final nextDay = DateTime(endDate.year, endDate.month, endDate.day + 1);
        query = query.where('completedAt', isLessThan: Timestamp.fromDate(nextDay));
      }

      // Limit the number of results
      query = query.limit(limit);

      // Execute query
      final snapshot = await query.get();
      print('Found ${snapshot.docs.length} completed rides');

      // Convert documents to PassengerRequest objects
      List<PassengerRequest> rides = [];
      for (var doc in snapshot.docs) {
        try {
          final request = PassengerRequest.fromFirestore(doc);
          rides.add(request);
        } catch (e) {
          print('Error processing ride ${doc.id}: $e');
        }
      }

      return rides;
    } catch (e) {
      print('Error fetching ride history: $e');
      return [];
    }
  }

  // Get earnings summary for a specific period
  Future<Map<String, dynamic>> getEarningsSummary({
    String period = 'all', // 'today', 'week', 'month', 'all'
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        return {'error': 'No authenticated user'};
      }

      // Get driver profile for total earnings
      final driverDoc = await _firestore.collection('Taxis').doc(currentUser.uid).get();
      if (!driverDoc.exists) {
        return {'error': 'Driver profile not found'};
      }

      final driverData = driverDoc.data() as Map<String, dynamic>;
      final totalEarnings = driverData['earnings'] ?? 0;
      final totalRides = driverData['totalRides'] ?? 0;

      // Define date range based on period
      DateTime? startDate;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      switch (period) {
        case 'today':
          startDate = today;
          break;
        case 'week':
        // Start from the beginning of the current week (Sunday)
          startDate = today.subtract(Duration(days: today.weekday % 7));
          break;
        case 'month':
        // Start from the beginning of the current month
          startDate = DateTime(now.year, now.month, 1);
          break;
        case 'all':
        default:
          startDate = null;
      }

      // Get rides for the period to calculate period-specific earnings
      Query query = _firestore.collection('PassengerRequests')
          .where('confirmedDriverId', isEqualTo: currentUser.uid)
          .where('status', isEqualTo: 'completed');

      if (startDate != null) {
        query = query.where('completedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
      }

      final snapshot = await query.get();

      // Calculate period earnings
      int periodEarnings = 0;
      int periodRides = 0;
      List<Map<String, dynamic>> dailyEarnings = [];
      Map<String, int> dailyEarningsMap = {};

      for (var doc in snapshot.docs) {
        try {
          final data = doc.data() as Map<String, dynamic>;
          final int fare = (data['rideFare'] ?? 0) is int ? data['rideFare'] : (data['rideFare'] ?? 0).toInt();
          periodEarnings += fare;
          periodRides++;

          // Collect daily earnings data for chart
          if (data['completedAt'] != null) {
            final DateTime completedDate = (data['completedAt'] as Timestamp).toDate();
            final String dateKey = DateFormat('yyyy-MM-dd').format(completedDate);

            dailyEarningsMap[dateKey] = (dailyEarningsMap[dateKey] ?? 0) + fare;
          }
        } catch (e) {
          print('Error processing ride data: $e');
        }
      }

      // Convert daily earnings map to sorted list for chart display
      dailyEarningsMap.forEach((date, earnings) {
        dailyEarnings.add({
          'date': date,
          'earnings': earnings,
        });
      });

      // Sort by date
      dailyEarnings.sort((a, b) => a['date'].compareTo(b['date']));

      // Calculate average fare
      double averageFare = periodRides > 0 ? periodEarnings / periodRides : 0;

      return {
        'totalEarnings': totalEarnings,
        'totalRides': totalRides,
        'periodEarnings': periodEarnings,
        'periodRides': periodRides,
        'averageFare': averageFare,
        'dailyEarnings': dailyEarnings,
        'period': period,
      };
    } catch (e) {
      print('Error fetching earnings summary: $e');
      return {'error': e.toString()};
    }
  }

  // Get detailed earnings data for chart
  Future<List<Map<String, dynamic>>> getEarningsChartData({
    String period = 'month', // 'week', 'month', 'year'
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        return [];
      }

      // Define date range based on period
      final now = DateTime.now();
      DateTime startDate;

      switch (period) {
        case 'week':
        // Last 7 days
          startDate = now.subtract(Duration(days: 7));
          break;
        case 'month':
        // Last 30 days
          startDate = now.subtract(Duration(days: 30));
          break;
        case 'year':
        // Last 365 days
          startDate = now.subtract(Duration(days: 365));
          break;
        default:
        // Default to month
          startDate = now.subtract(Duration(days: 30));
      }

      // Get completed rides in the date range
      final snapshot = await _firestore.collection('PassengerRequests')
          .where('confirmedDriverId', isEqualTo: currentUser.uid)
          .where('status', isEqualTo: 'completed')
          .where('completedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .orderBy('completedAt', descending: false)
          .get();

      // Organize earnings by date
      Map<String, int> dailyEarnings = {};
      for (var doc in snapshot.docs) {
        try {
          final data = doc.data() as Map<String, dynamic>;
          if (data['completedAt'] != null && data['rideFare'] != null) {
            final DateTime completedDate = (data['completedAt'] as Timestamp).toDate();
            String dateKey;

            // Format date key based on period
            if (period == 'week') {
              dateKey = DateFormat('E').format(completedDate); // Day of week (Mon, Tue, etc.)
            } else if (period == 'month') {
              dateKey = DateFormat('MM-dd').format(completedDate); // Month-day
            } else {
              dateKey = DateFormat('MM').format(completedDate); // Month only
            }

            final int fare = (data['rideFare'] ?? 0) is int ? data['rideFare'] : (data['rideFare'] ?? 0).toInt();
            dailyEarnings[dateKey] = (dailyEarnings[dateKey] ?? 0) + fare;
          }
        } catch (e) {
          print('Error processing chart data: $e');
        }
      }

      // Convert map to list of chart data points
      List<Map<String, dynamic>> chartData = [];
      dailyEarnings.forEach((date, earnings) {
        chartData.add({
          'date': date,
          'earnings': earnings,
        });
      });

      // Sort data chronologically
      chartData.sort((a, b) => a['date'].compareTo(b['date']));

      return chartData;
    } catch (e) {
      print('Error fetching earnings chart data: $e');
      return [];
    }
  }
}