import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/app_strings.dart';

/// Subtle "Offline mode" strip shown while the phone has no connection.
///
/// The connectivity plugin alone misreports on the iOS simulator (it can
/// say "none" at startup and never correct itself), so "offline" is only
/// shown after a real reachability probe agrees — and while shown, it
/// re-probes so the banner clears itself as soon as the network is back.
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  bool _isOffline = false;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _recheck;

  @override
  void initState() {
    super.initState();
    _subscription = Connectivity().onConnectivityChanged.listen(
      (_) => _evaluate(),
    );
    _evaluate();
  }

  Future<void> _evaluate() async {
    final results = await Connectivity().checkConnectivity();
    var offline = results.every((r) => r == ConnectivityResult.none);

    // "No connection" per the OS: distrust it until a probe agrees.
    if (offline) offline = await _unreachable();

    if (!mounted) return;
    if (offline != _isOffline) setState(() => _isOffline = offline);

    // While offline, keep re-checking: the connectivity stream can stay
    // silent even after the network returns (seen on the simulator).
    _recheck?.cancel();
    if (offline) {
      _recheck = Timer(const Duration(seconds: 10), _evaluate);
    }
  }

  /// True only when Firestore's host genuinely cannot be resolved.
  Future<bool> _unreachable() async {
    if (kIsWeb) return true; // no dart:io on web; trust the plugin there
    try {
      final result = await InternetAddress.lookup(
        'firestore.googleapis.com',
      ).timeout(const Duration(seconds: 4));
      return result.isEmpty;
    } catch (_) {
      return true;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _recheck?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppStrings.watch(context);
    if (!_isOffline) return const SizedBox.shrink();

    // Informational only: clock in/out keeps working offline and syncs
    // automatically when the connection returns.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 16),
      color: Colors.grey[200],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off, color: Colors.grey[700], size: 14),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              AppStrings.offlineMode,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700], fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
