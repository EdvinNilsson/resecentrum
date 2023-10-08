import 'package:dio/dio.dart';
import 'package:maplibre_gl/mapbox_gl.dart';

import 'planera_resa.dart';

class MGate {
  static final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://rrp.vasttrafik.se/bin/mgate.exe',
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));

  static Future<CoordLocation?> getLocationNearbyAddress(LatLng position) async {
    var locMatch = await _dio.post('/', queryParameters: {
      'rnd': DateTime.now().millisecondsSinceEpoch
    }, data: {
      'ver': '1.60',
      'lang': 'swe',
      'auth': {'type': 'AID', 'aid': 'webwf4h674678g4fh'},
      'client': {'id': 'VASTTRAFIK', 'type': 'WEB'},
      'svcReqL': [
        {
          'req': {
            'input': {
              'field': 'S',
              'loc': {
                'type': 'C',
                'name': '${(position.longitude * 1000000).round()} ${(position.latitude * 1000000).round()}'
              },
              'maxLoc': 1,
            }
          },
          'meth': 'LocMatch',
        }
      ]
    });

    var match = locMatch.data['svcResL'][0]['res']['match'];
    if (match.isEmpty) return null;
    var locL = match['locL'][0];

    return CoordLocation(
      locL['name'],
      locL['crd']['y'] / 1000000.0,
      locL['crd']['x'] / 1000000.0,
      'ADR',
    );
  }
}
