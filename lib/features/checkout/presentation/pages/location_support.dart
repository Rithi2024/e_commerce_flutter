import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

typedef LocationMessageSink = void Function(String message);

class LocationAddressFormatter {
  static String coordinateText({
    required double latitude,
    required double longitude,
  }) {
    return '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
  }

  static ({String shortText, String fullText}) fromPlacemark(
    Placemark placemark, {
    required double latitude,
    required double longitude,
  }) {
    String pickFirst(Iterable<String?> values) {
      for (final value in values) {
        final normalized = (value ?? '').trim();
        if (normalized.isNotEmpty) return normalized;
      }
      return '';
    }

    String joinParts(List<String> parts) {
      return parts.where((part) => part.trim().isNotEmpty).join(', ');
    }

    final houseNo = pickFirst([placemark.subThoroughfare]);
    final road = pickFirst([placemark.thoroughfare]);
    final street = [
      houseNo,
      road,
    ].where((part) => part.isNotEmpty).join(' ').trim();

    final locality = pickFirst([
      placemark.subLocality,
      placemark.locality,
      placemark.subAdministrativeArea,
    ]);
    final city = pickFirst([
      placemark.locality,
      placemark.subAdministrativeArea,
      placemark.administrativeArea,
    ]);
    final state = pickFirst([placemark.administrativeArea]);
    final postal = pickFirst([placemark.postalCode]);
    final country = pickFirst([placemark.country]);
    final knownName = pickFirst([placemark.name]);

    final compact = joinParts([street, locality, city, state, postal, country]);

    final fallbackCoordinate = coordinateText(
      latitude: latitude,
      longitude: longitude,
    );
    final shortText = compact.isNotEmpty
        ? compact
        : (knownName.isNotEmpty ? knownName : fallbackCoordinate);

    final fullText = joinParts([
      knownName,
      street,
      locality,
      city,
      state,
      postal,
      country,
    ]);

    return (
      shortText: shortText,
      fullText: fullText.isNotEmpty ? fullText : shortText,
    );
  }
}

class LocationPermissionSupport {
  static Future<bool> ensureAccess({
    required BuildContext context,
    required LocationMessageSink showMessage,
  }) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!context.mounted) return false;
        showMessage('Location service is turned off');
        final openSettings = await _promptForSettings(
          context: context,
          title: 'Enable location service',
          message:
              'Turn on location service in your device settings to use current location.',
          actionLabel: 'Open settings',
        );
        if (openSettings) {
          await Geolocator.openLocationSettings();
        }
        return false;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        showMessage('Location permission denied');
        return false;
      }
      if (permission == LocationPermission.deniedForever) {
        if (!context.mounted) return false;
        showMessage('Location permission permanently denied');
        final openSettings = await _promptForSettings(
          context: context,
          title: 'Allow location permission',
          message:
              'Location access is permanently denied. Please allow it from app settings.',
          actionLabel: 'App settings',
        );
        if (openSettings) {
          await Geolocator.openAppSettings();
        }
        return false;
      }

      return true;
    } on MissingPluginException {
      showMessage('Location plugin not ready. Please fully restart the app.');
      return false;
    } on PlatformException {
      showMessage('Location service unavailable on this device now.');
      return false;
    }
  }

  static Future<bool> _promptForSettings({
    required BuildContext context,
    required String title,
    required String message,
    required String actionLabel,
  }) async {
    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    return shouldOpen == true;
  }
}
