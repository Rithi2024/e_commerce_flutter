import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import 'address_map_picker_screen.dart';
import 'location_support.dart';

class CheckoutAddressSelectionResult {
  final String address;

  const CheckoutAddressSelectionResult({required this.address});
}

class CheckoutAddressSelectionScreen extends StatefulWidget {
  const CheckoutAddressSelectionScreen({
    super.key,
    required this.selectedAddress,
    required this.historyAddresses,
    this.contactName = '',
    this.contactPhone = '',
  });

  final String selectedAddress;
  final List<String> historyAddresses;
  final String contactName;
  final String contactPhone;

  @override
  State<CheckoutAddressSelectionScreen> createState() =>
      _CheckoutAddressSelectionScreenState();
}

class _CheckoutAddressSelectionScreenState
    extends State<CheckoutAddressSelectionScreen> {
  final TextEditingController _searchController = TextEditingController();
  late List<String> _historyAddresses;
  late String _selectedAddress;
  bool _locating = false;

  static const Color _accent = Color(0xFFF6234A);

  @override
  void initState() {
    super.initState();
    _historyAddresses = widget.historyAddresses
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    _selectedAddress = widget.selectedAddress.trim();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> _filterAddresses(List<String> source) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return source;
    return source.where((item) => item.toLowerCase().contains(query)).toList();
  }

  void _confirmSelection(String address) {
    final normalized = address.trim();
    if (normalized.isEmpty) return;
    Navigator.pop(context, CheckoutAddressSelectionResult(address: normalized));
  }

  Future<void> _selectFromMap() async {
    final result = await Navigator.push<MapAddressSelection>(
      context,
      MaterialPageRoute(builder: (_) => const AddressMapPickerScreen()),
    );
    if (result == null || !mounted) return;
    _confirmSelection(result.address);
  }

  Future<void> _useCurrentLocation() async {
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
      final address = await _reverseGeocode(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (!mounted) return;
      _confirmSelection(address);
    } catch (_) {
      _showMessage('Could not get current location');
    } finally {
      if (mounted) {
        setState(() => _locating = false);
      }
    }
  }

  Future<String> _reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        final addressText = LocationAddressFormatter.fromPlacemark(
          placemark,
          latitude: latitude,
          longitude: longitude,
        );
        if (addressText.fullText.trim().isNotEmpty) return addressText.fullText;
      }
    } catch (_) {}
    return LocationAddressFormatter.coordinateText(
      latitude: latitude,
      longitude: longitude,
    );
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _sectionTitle(
    String text, {
    Widget trailing = const SizedBox.shrink(),
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
        trailing,
      ],
    );
  }

  Widget _lineAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool loading = false,
  }) {
    return InkWell(
      onTap: loading ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: _accent, size: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (loading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }

  Widget _addressRow(String address, {bool selectable = true}) {
    final selected = _selectedAddress == address;
    return InkWell(
      onTap: selectable ? () => _confirmSelection(address) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? _accent : Colors.grey.shade600,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    address,
                    style: const TextStyle(fontSize: 15, height: 1.25),
                  ),
                  if (widget.contactName.trim().isNotEmpty ||
                      widget.contactPhone.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      '${widget.contactName} ${widget.contactPhone}'.trim(),
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compactHeader = MediaQuery.sizeOf(context).width < 390;
    final selectedAddress = _selectedAddress.trim();
    final myAddresses = selectedAddress.isEmpty
        ? const <String>[]
        : <String>[selectedAddress];
    final historyAddresses = _historyAddresses.where((address) {
      if (selectedAddress.isEmpty) return true;
      return address.trim().toLowerCase() != selectedAddress.toLowerCase();
    }).toList();

    final filteredHistory = _filterAddresses(historyAddresses);
    final filteredMyAddress = _filterAddresses(myAddresses);

    return Scaffold(
      appBar: AppBar(title: const Text('Choose Address')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        children: [
          if (compactHeader)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Phnom Penh',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Icon(Icons.keyboard_arrow_down_rounded),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: 'Search location',
                    filled: true,
                    fillColor: const Color(0xFFF5F6FA),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: const BorderSide(color: Color(0xFFE8E9EF)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: const BorderSide(color: Color(0xFFE8E9EF)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: const BorderSide(color: Color(0xFFE8E9EF)),
                    ),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                const Text(
                  'Phnom Penh',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                const Icon(Icons.keyboard_arrow_down_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: 'Search location',
                      filled: true,
                      fillColor: const Color(0xFFF5F6FA),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: const BorderSide(color: Color(0xFFE8E9EF)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: const BorderSide(color: Color(0xFFE8E9EF)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: const BorderSide(color: Color(0xFFE8E9EF)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 18),
          _lineAction(
            icon: Icons.my_location_outlined,
            label: 'Use current location',
            loading: _locating,
            onTap: _useCurrentLocation,
          ),
          const Divider(height: 1),
          _lineAction(
            icon: Icons.location_searching_outlined,
            label: 'Select in map',
            onTap: _selectFromMap,
          ),
          const Divider(height: 30),
          _sectionTitle(
            'History address',
            trailing: IconButton(
              onPressed: _historyAddresses.isEmpty
                  ? null
                  : () => setState(() => _historyAddresses.clear()),
              icon: const Icon(Icons.delete_outline),
            ),
          ),
          if (filteredHistory.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No history address',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            )
          else
            ...filteredHistory.map(
              (address) => Column(
                children: [
                  InkWell(
                    onTap: () => _confirmSelection(address),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          address,
                          style: const TextStyle(fontSize: 15, height: 1.25),
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                ],
              ),
            ),
          const SizedBox(height: 18),
          _sectionTitle('My address'),
          if (filteredMyAddress.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No saved address',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            )
          else
            ...filteredMyAddress.map(
              (address) => Column(
                children: [_addressRow(address), const Divider(height: 1)],
              ),
            ),
        ],
      ),
    );
  }
}
