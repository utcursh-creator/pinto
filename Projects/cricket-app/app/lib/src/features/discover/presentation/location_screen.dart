import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/platform/adaptive_scaffold.dart';
import '../data/discover_providers.dart';
import '../data/discover_repository.dart';
import '../data/location_service.dart';

/// Sets the geo anchor the feed searches around: device GPS (one tap) or a
/// manual lat/lng + radius (defaults to the current anchor). Saving also
/// persists the point as the user's home base (so the feed re-centres here
/// next launch).
class LocationScreen extends ConsumerStatefulWidget {
  const LocationScreen({super.key});

  @override
  ConsumerState<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends ConsumerState<LocationScreen> {
  late final TextEditingController _lat;
  late final TextEditingController _lng;
  final _label = TextEditingController();
  double _radiusKm = 25;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    final a = ref.read(anchorProvider);
    _lat = TextEditingController(text: a.lat.toString());
    _lng = TextEditingController(text: a.lng.toString());
    _radiusKm = a.radiusM / 1000;
    // DISC-4: prefill the saved home label so it doesn't read "Saved location".
    final home = ref.read(homeLocationProvider).value;
    if (home?.label != null) _label.text = home!.label!;
  }

  @override
  void dispose() {
    _lat.dispose();
    _lng.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final lat = double.tryParse(_lat.text.trim());
    final lng = double.tryParse(_lng.text.trim());
    if (lat == null || lng == null) return;
    ref.read(anchorProvider.notifier).set(
          (lat: lat, lng: lng, radiusM: _radiusKm * 1000),
        );
    // Persist as the home base so the feed re-centres here next launch.
    // Anonymous viewers have no home base (the RPC is authenticated-only).
    final session = ref.read(currentSessionProvider);
    if (session != null && !session.user.isAnonymous) {
      try {
        // DISC-4: persist the human place label too, so "home" has a name.
        await ref.read(discoverRepositoryProvider).setMyLocation(
              lat,
              lng,
              label: _label.text.trim(),
            );
        ref.invalidate(homeLocationProvider);
      } catch (_) {/* non-fatal: the session anchor is still set */}
    }
    if (mounted) context.pop();
  }

  Future<void> _useGps() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final pos = await ref.read(locationServiceProvider).current();
      if (!mounted) return;
      setState(() {
        _lat.text = pos.lat.toStringAsFixed(5);
        _lng.text = pos.lng.toStringAsFixed(5);
      });
    } on LocationException catch (e) {
      setState(() => _message = e.message);
    } catch (e) {
      setState(() => _message = 'Could not get your location.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      title: 'Location',
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Set the area to search for games.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _busy ? null : _useGps,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location),
            label: const Text('Use my current location'),
          ),
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(_message!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          // DISC-4: a human place name instead of raw coordinates in the UI.
          TextField(
            controller: _label,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Area name',
              hintText: 'e.g. Dadar, Mumbai',
            ),
          ),
          const SizedBox(height: 8),
          // Raw coordinates are an expert affordance, not the primary UI.
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Advanced: exact coordinates',
                style: Theme.of(context).textTheme.labelLarge),
            children: [
              TextField(
                controller: _lat,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: const InputDecoration(labelText: 'Latitude'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _lng,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: const InputDecoration(labelText: 'Longitude'),
              ),
              const SizedBox(height: 12),
            ],
          ),
          const SizedBox(height: 12),
          Text('Radius: ${_radiusKm.round()} km'),
          Slider(
            value: _radiusKm,
            min: 1,
            max: 100,
            divisions: 99,
            label: '${_radiusKm.round()} km',
            onChanged: (v) => setState(() => _radiusKm = v),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }
}
