import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'location_support.dart';

class MapAddressSelection {
  final String address;
  final double latitude;
  final double longitude;

  const MapAddressSelection({
    required this.address,
    required this.latitude,
    required this.longitude,
  });
}

class AddressMapPickerScreen extends StatefulWidget {
  const AddressMapPickerScreen({super.key});

  @override
  State<AddressMapPickerScreen> createState() => _AddressMapPickerScreenState();
}

class _AddressMapPickerScreenState extends State<AddressMapPickerScreen> {
  static const LatLng _defaultCenter = LatLng(40.7128, -74.0060);

  GoogleMapController? _mapController;
  LatLng _selected = _defaultCenter;
  LatLng _cameraTarget = _defaultCenter;
  String _resolvedAddress = '';
  String _shortAddress = '';
  bool _loadingAddress = true;
  bool _locating = false;
  int _resolveToken = 0;
  LatLng? _lastResolvedPoint;
  bool _skipNextCameraIdle = false;
  Timer? _resolveDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeLocationOnOpen();
    });
  }

  @override
  void dispose() {
    _resolveDebounce?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _initializeLocationOnOpen() async {
    await _moveToCurrentLocation();
    if (!mounted) return;
    if (_shortAddress.trim().isEmpty && _resolvedAddress.trim().isEmpty) {
      await _resolveAddressForSelected(force: true);
    }
  }

  bool _hasUsefulAddress(Placemark placemark) {
    return [
      placemark.thoroughfare,
      placemark.subThoroughfare,
      placemark.name,
      placemark.locality,
      placemark.subLocality,
      placemark.administrativeArea,
    ].any((value) => (value ?? '').trim().isNotEmpty);
  }

  void _onCameraMove(CameraPosition position) {
    _cameraTarget = position.target;
  }

  void _onCameraIdle() {
    if (_skipNextCameraIdle) {
      _skipNextCameraIdle = false;
      return;
    }
    final movedMeters = Geolocator.distanceBetween(
      _selected.latitude,
      _selected.longitude,
      _cameraTarget.latitude,
      _cameraTarget.longitude,
    );
    if (movedMeters < 6) return;
    setState(() {
      _selected = _cameraTarget;
    });
    _scheduleResolveForSelected();
  }

  void _scheduleResolveForSelected() {
    _resolveDebounce?.cancel();
    _resolveDebounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      await _resolveAddressForSelected();
    });
  }

  Future<void> _setSelectedPoint(
    LatLng point, {
    required bool moveMap,
    required bool resolveAddress,
  }) async {
    if (!mounted) return;
    setState(() {
      _selected = point;
      _cameraTarget = point;
    });
    if (moveMap && _mapController != null) {
      final zoom = await _mapController!.getZoomLevel();
      _skipNextCameraIdle = true;
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(point, zoom < 17 ? 18 : zoom),
      );
    }
    if (resolveAddress) {
      await _resolveAddressForSelected(force: true);
    }
  }

  Future<void> _moveToCurrentLocation() async {
    if (_locating) return;

    setState(() => _locating = true);
    try {
      final granted = await LocationPermissionSupport.ensureAccess(
        context: context,
        showMessage: _showMessage,
      );
      if (!granted) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final point = LatLng(position.latitude, position.longitude);
      if (!mounted) return;

      await _setSelectedPoint(point, moveMap: true, resolveAddress: true);
    } catch (_) {
      _showMessage('Could not fetch current location');
    } finally {
      if (mounted) {
        setState(() => _locating = false);
      }
    }
  }

  Future<void> _resolveAddressForSelected({bool force = false}) async {
    final point = _selected;
    if (!force && _lastResolvedPoint != null) {
      final movedMeters = Geolocator.distanceBetween(
        _lastResolvedPoint!.latitude,
        _lastResolvedPoint!.longitude,
        point.latitude,
        point.longitude,
      );
      if (movedMeters < 3) {
        return;
      }
    }

    final token = ++_resolveToken;
    setState(() {
      _loadingAddress = true;
    });

    try {
      final placemarks = await placemarkFromCoordinates(
        point.latitude,
        point.longitude,
      );
      if (placemarks.isNotEmpty) {
        final best = placemarks.firstWhere(
          _hasUsefulAddress,
          orElse: () => placemarks.first,
        );
        final addressText = LocationAddressFormatter.fromPlacemark(
          best,
          latitude: point.latitude,
          longitude: point.longitude,
        );
        if (!mounted || token != _resolveToken) return;
        setState(() {
          _shortAddress = addressText.shortText;
          _resolvedAddress = addressText.fullText;
          _lastResolvedPoint = point;
          _loadingAddress = false;
        });
        return;
      }
    } catch (_) {}

    if (!mounted || token != _resolveToken) return;
    setState(() {
      final fallback = _resolvedAddress.trim().isNotEmpty
          ? _resolvedAddress
          : LocationAddressFormatter.coordinateText(
              latitude: point.latitude,
              longitude: point.longitude,
            );
      _shortAddress = fallback;
      _resolvedAddress = fallback;
      _lastResolvedPoint = point;
      _loadingAddress = false;
    });
  }

  Future<void> _chooseThisLocation() async {
    if (_loadingAddress) {
      _showMessage('Please wait, still getting address');
      return;
    }

    if (_resolvedAddress.trim().isEmpty && _shortAddress.trim().isEmpty) {
      await _resolveAddressForSelected(force: true);
      if (!mounted) return;
    }

    final address = _resolvedAddress.trim().isNotEmpty
        ? _resolvedAddress.trim()
        : (_shortAddress.trim().isNotEmpty
              ? _shortAddress.trim()
              : LocationAddressFormatter.coordinateText(
                  latitude: _selected.latitude,
                  longitude: _selected.longitude,
                ));

    Navigator.pop(
      context,
      MapAddressSelection(
        address: address,
        latitude: _selected.latitude,
        longitude: _selected.longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Search location')),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _selected,
              zoom: 17.5,
            ),
            mapType: MapType.normal,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            onMapCreated: (controller) {
              _mapController = controller;
            },
            onCameraMove: _onCameraMove,
            onCameraIdle: _onCameraIdle,
          ),
          const IgnorePointer(
            child: Center(
              child: Icon(
                Icons.location_on,
                size: 44,
                color: Color(0xFFD13D3D),
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 232,
            child: FloatingActionButton.small(
              heroTag: 'map_current_location_btn',
              onPressed: _locating ? null : _moveToCurrentLocation,
              child: _locating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x24000000),
                    blurRadius: 14,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Move map to choose address',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    LocationAddressFormatter.coordinateText(
                      latitude: _selected.latitude,
                      longitude: _selected.longitude,
                    ),
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  if (_loadingAddress)
                    const Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Expanded(child: Text('Getting address...')),
                      ],
                    )
                  else
                    Text(
                      (_shortAddress.isEmpty ? _resolvedAddress : _shortAddress)
                          .trim(),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 13,
                      ),
                    ),
                  if (!_loadingAddress &&
                      _resolvedAddress.isNotEmpty &&
                      _resolvedAddress != _shortAddress) ...[
                    const SizedBox(height: 6),
                    Text(
                      _resolvedAddress,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _loadingAddress ? null : _chooseThisLocation,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Use This Address'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
