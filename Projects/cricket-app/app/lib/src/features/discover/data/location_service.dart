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
    final pos = await Geolocator.getCurrentPosition();
    return (lat: pos.latitude, lng: pos.longitude);
  }
}

final locationServiceProvider =
    Provider<LocationService>((ref) => GeolocatorLocationService());
