import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:epic_tracker/services/firestore_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Epic's neighborhood: Costa Mesa, CA.
  const site = GeoPoint(33.6461, -117.9187);

  group('distanceFeet', () {
    test('zero when standing on the pin', () {
      expect(distanceFeet(site, site), 0);
    });

    test('about 365 ft for 0.001° of latitude', () {
      // 0.001° lat ≈ 111 m ≈ 365 ft anywhere on Earth.
      final d = distanceFeet(site, const GeoPoint(33.6471, -117.9187));
      expect(d, closeTo(365, 5));
    });

    test('a worker clocking in from Santa Ana is miles away', () {
      final d = distanceFeet(site, const GeoPoint(33.7455, -117.8677));
      expect(d, greaterThan(5 * 5280));
      expect(d > FirestoreService.defaultSiteRadiusFt, isTrue);
    });
  });

  group('formatDistanceFt', () {
    test('feet under a quarter mile', () {
      expect(formatDistanceFt(350), '350 ft');
      expect(formatDistanceFt(1319.6), '1320 ft');
    });

    test('miles with one decimal beyond that', () {
      expect(formatDistanceFt(1320), '0.3 mi');
      expect(formatDistanceFt(9504), '1.8 mi');
    });

    test('null reads as 0 ft', () {
      expect(formatDistanceFt(null), '0 ft');
    });
  });
}
