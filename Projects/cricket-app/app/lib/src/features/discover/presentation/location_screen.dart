import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../data/discover_providers.dart';

/// Sets the geo anchor the feed searches around. Device GPS is a later
/// refinement; v1 takes a lat/lng + radius (defaults to the current anchor).
class LocationScreen extends ConsumerStatefulWidget {
  const LocationScreen({super.key});

  @override
  ConsumerState<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends ConsumerState<LocationScreen> {
  late final TextEditingController _lat;
  late final TextEditingController _lng;
  double _radiusKm = 25;

  @override
  void initState() {
    super.initState();
    final a = ref.read(anchorProvider);
    _lat = TextEditingController(text: a.lat.toString());
    _lng = TextEditingController(text: a.lng.toString());
    _radiusKm = a.radiusM / 1000;
  }

  @override
  void dispose() {
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  void _save() {
    final lat = double.tryParse(_lat.text.trim());
    final lng = double.tryParse(_lng.text.trim());
    if (lat == null || lng == null) return;
    ref.read(anchorProvider.notifier).set(
          (lat: lat, lng: lng, radiusM: _radiusKm * 1000),
        );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      title: 'Location',
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Set the area to search for games. (Live GPS coming soon.)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _lat,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(labelText: 'Latitude'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _lng,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(labelText: 'Longitude'),
          ),
          const SizedBox(height: 20),
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
