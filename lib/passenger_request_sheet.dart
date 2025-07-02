import 'package:flutter/material.dart';
import 'passenger_model.dart';

class PassengerRequestSheet extends StatefulWidget {
  final List<PassengerRequest> nearbyRequests;
  final Function(PassengerRequest) onRequestAccepted;
  final Function() onClosePressed;

  const PassengerRequestSheet({
    Key? key,
    required this.nearbyRequests,
    required this.onRequestAccepted,
    required this.onClosePressed,
  }) : super(key: key);

  @override
  State<PassengerRequestSheet> createState() => _PassengerRequestSheetState();
}

class _PassengerRequestSheetState extends State<PassengerRequestSheet> {
  int _currentRequestIndex = 0;
  bool _isAccepting = false;

  void _showNextRequest() {
    if (_currentRequestIndex < widget.nearbyRequests.length - 1) {
      setState(() {
        _currentRequestIndex++;
      });
    } else {
      // If we've gone through all requests, show a message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No more passenger requests available'),
          backgroundColor: Color(0xFF333333),
          behavior: SnackBarBehavior.floating,
        ),
      );
      widget.onClosePressed();
    }
  }

  void _acceptRequest(PassengerRequest request) async {
    setState(() {
      _isAccepting = true;
    });

    try {
      await widget.onRequestAccepted(request);
    } finally {
      if (mounted) {
        setState(() {
          _isAccepting = false;
        });
      }
    }
  }

  // Get the estimated time for a ride based on distance
  String _getEstimatedTime(PassengerRequest request) {
    final double distance = request.additionalData?['calculatedDistanceKm'] ?? request.distanceKm;
    // Assume average speed of 20 km/h in city traffic = 1 min per 0.33 km
    final int minutes = (distance * 3).round();

    if (minutes < 60) {
      return '$minutes min';
    } else {
      final int hours = minutes ~/ 60;
      final int remainingMinutes = minutes % 60;
      return '$hours h ${remainingMinutes > 0 ? '$remainingMinutes min' : ''}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF222222),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              const Text(
                'Passenger Request',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              Positioned(
                right: 0,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: widget.onClosePressed,
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          widget.nearbyRequests.isEmpty
              ? const Center(
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: Text(
                'No passenger requests at the moment',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          )
              : Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.4,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildPassengerRequestCard(
                  widget.nearbyRequests[_currentRequestIndex],
                ),
                const SizedBox(height: 20),
                if (widget.nearbyRequests.length > 1)
                  Text(
                    'Request ${_currentRequestIndex + 1} of ${widget.nearbyRequests.length}',
                    style: const TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                if (widget.nearbyRequests[_currentRequestIndex].additionalData?['isMockData'] == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '(This is mock data for demonstration)',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPassengerRequestCard(PassengerRequest request) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: const Color(0xFF333333),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(25),
                  child: Image.network(
                    request.passengerImage,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, error, _) => Container(
                      width: 60,
                      height: 60,
                      color: Colors.grey[700],
                      child: const Icon(Icons.person, color: Colors.white, size: 30),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.passengerName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 16),
                          Text(
                            ' ${request.passengerRating.toStringAsFixed(1)}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${request.timestamp.day}/${request.timestamp.month}/${request.timestamp.year} ${request.timestamp.hour}:${request.timestamp.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF4B6C).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${request.fare} PKR',
                    style: const TextStyle(
                      color: Color(0xFFFF4B6C),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Pickup location
            Row(
              children: [
                const Icon(
                  Icons.location_on,
                  size: 18,
                  color: Color(0xFFFF4B6C),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    request.pickupAddress,
                    style: const TextStyle(
                      color: Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Destination location
            Row(
              children: [
                const Icon(
                  Icons.flag,
                  size: 18,
                  color: Colors.green,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    request.destinationAddress,
                    style: const TextStyle(
                      color: Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Ride details
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Distance',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '${request.distanceKm.toStringAsFixed(1)} km',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Est. Time',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        _getEstimatedTime(request),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Action buttons row
            Row(
              children: [
                // Decline button
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isAccepting ? null : _showNextRequest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[800],
                      disabledBackgroundColor: Colors.grey[900],
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Decline',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _isAccepting ? Colors.grey : Colors.white70,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Accept button
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isAccepting ? null : () => _acceptRequest(request),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF4B6C),
                      disabledBackgroundColor: const Color(0xFFFF4B6C).withOpacity(0.5),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isAccepting
                        ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                        : const Text(
                      'Accept',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
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