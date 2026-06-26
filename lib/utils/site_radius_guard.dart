import 'package:app/constants/api_codes.dart';
import 'package:app/services/location_service.dart';
import 'package:app/utils/calculate_distance.dart';
import 'package:app/utils/logger.dart';
import 'package:app/utils/toastbar.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// Returns true when the user may open a site/activity at [siteLat]/[siteLng].
Future<bool> ensureUserWithinSiteRadius(
  BuildContext context, {
  required double? siteLat,
  required double? siteLng,
}) async {
  if (!hasValidSiteCoordinates(siteLat, siteLng)) {
    Toastbar.showErrorToastbar(siteNotInRadiusMessage, context);
    return false;
  }

  try {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        Toastbar.showErrorToastbar(
          "Location permission is required to access this site.",
          context,
        );
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      final shouldOpenSettings = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Location Permission Denied'),
            content: const Text(
              'Location permission is permanently denied. '
              'Please enable location permission in app settings to access this site.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Open Settings'),
              ),
            ],
          );
        },
      );

      if (shouldOpenSettings == true) {
        await openAppSettings();
      }
      return false;
    }

    final currentLocation = await LocationService.getCurrentLocation();

    final distanceInKm = calculateDistance(
      currentLocation.latitude,
      currentLocation.longitude,
      siteLat!,
      siteLng!,
    );

    final maxDistanceKm = double.parse(ApiCodes.distanceFromLocation);
    if (distanceInKm > maxDistanceKm) {
      Toastbar.showErrorToastbar(
        "You are not in the radius of site. Your distance from the site is: ${distanceInKm.toStringAsFixed(2)} km",
        context,
      );
      return false;
    }

    return true;
  } catch (e) {
    Logger.errorLog('Error calculating distance: $e');
    Toastbar.showErrorToastbar(
      "Unable to get your location. Please ensure location services are enabled.",
      context,
    );
    return false;
  }
}
