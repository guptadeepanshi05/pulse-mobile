import 'dart:math';

const String siteNotInRadiusMessage = 'You are not in the radius of site.';

/// True when both coordinates are present and not the null-island placeholder (0, 0).
bool hasValidSiteCoordinates(double? latitude, double? longitude) {
  if (latitude == null || longitude == null) return false;
  return latitude != 0.0 || longitude != 0.0;
}

double calculateDistance(
  double currentLatitude,
  double currentLongitude,
  double targetLatitude,
  double targetLongitude,
) {
  const double earthRadius = 6371; // in kilometers

  double dLat = _toRadians(targetLatitude - currentLatitude);
  double dLon = _toRadians(targetLongitude - currentLongitude);

  double a =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(_toRadians(currentLatitude)) *
          cos(_toRadians(targetLatitude)) *
          sin(dLon / 2) *
          sin(dLon / 2);

  double c = 2 * atan2(sqrt(a), sqrt(1 - a));

  return earthRadius * c; // distance in km
}

double _toRadians(double degree) {
  return degree * pi / 180;
}
