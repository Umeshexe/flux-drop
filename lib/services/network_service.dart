import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkService {
  final Connectivity _connectivity;

  NetworkService({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  Future<bool> isLikelyMeteredConnection() async {
    final results = await _connectivity.checkConnectivity();
    return results.contains(ConnectivityResult.mobile) ||
        results.contains(ConnectivityResult.bluetooth) ||
        results.contains(ConnectivityResult.other);
  }
}
