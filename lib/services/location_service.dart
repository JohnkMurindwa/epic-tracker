import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'app_strings.dart';

/// Gets the phone's location for clocking in, asking for permission if
/// needed.
///
/// Throws a user-facing message if location is off or permission is denied.
/// Returns null (after offering to open Settings) if permission was
/// permanently denied — callers should abort silently in that case.
Future<Position?> getClockInLocation(BuildContext context) async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    throw tr(
      'Location services are disabled. Please enable them in Settings.',
      'La ubicación está desactivada. Actívala en Configuración.',
    );
  }

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      throw tr(
        'Location permission denied. Please allow location access to clock in.',
        'Permiso de ubicación denegado. Permite el acceso a la ubicación para registrar tu entrada.',
      );
    }
  }

  if (permission == LocationPermission.deniedForever) {
    if (context.mounted) {
      await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            tr('Location Access Required', 'Se necesita acceso a la ubicación'),
          ),
          content: Text(
            tr(
              'You previously denied location access. Epic Stone needs your location to verify you\'re on the job site.\n\nPlease open Settings and enable location for this app.',
              'Antes negaste el acceso a la ubicación. Epic Stone necesita tu ubicación para confirmar que estás en la obra.\n\nAbre Configuración y activa la ubicación para esta app.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(AppStrings.cancel),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                Geolocator.openAppSettings();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black87,
                foregroundColor: Colors.white,
              ),
              child: Text(tr('Open Settings', 'Abrir Configuración')),
            ),
          ],
        ),
      );
    }
    return null; // Silently abort — no error message
  }

  return await Geolocator.getCurrentPosition();
}

/// Current position for a clock-out, or null if it can't be had quickly.
/// Never prompts and never throws: an off-site clock-out is flagged for the
/// supervisor, not blocked.
Future<GeoPoint?> getLocationQuietly() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    final position = await Geolocator.getCurrentPosition().timeout(
      const Duration(seconds: 10),
    );
    return GeoPoint(position.latitude, position.longitude);
  } catch (_) {
    return null;
  }
}
