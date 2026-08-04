import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

class LocationException implements Exception {
  const LocationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Device location, behind an interface so widget tests supply a fake.
abstract interface class LocationService {
  Future<({double lat, double lng})> current();
}

class GeolocatorLocationService implements LocationService {
  @override
  Future<({double lat, double lng})> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException('Turn on location services to use GPS.');
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      throw const LocationException('Location permission denied.');
    }
    // A TIME LIMIT, because getCurrentPosition with no LocationSettings waits
    // forever for a fresh fix (review #2, finding 44). Indoors, in a stadium
    // basement or on a cold-start GPS the future simply never completed: the
    // button became a disabled spinner with no cancel and no error, until the
    // screen was popped. The iOS simulator answers instantly with a canned
    // location, which is why every pass on the sim looked fine.
    //
    // 15s is long enough for a real cold fix outdoors and short enough that a
    // person indoors gets an answer rather than a spinner.
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return (lat: pos.latitude, lng: pos.longitude);
    } on TimeoutException {
      throw const LocationException(
          'Could not get a GPS fix. Move somewhere with a clearer view of the '
          'sky, or type your area instead.');
    }
  }
}

final locationServiceProvider =
    Provider<LocationService>((ref) => GeolocatorLocationService());
