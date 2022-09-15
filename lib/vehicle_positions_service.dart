import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'reseplaneraren.dart';

VehiclePositionsService vehiclePositionsService = VehiclePositionsService();

class VehiclePositionsService {
  String? _accessToken;

  final Dio _dio = Dio(BaseOptions(baseUrl: 'https://api.vasttrafik.se', connectTimeout: 5000, receiveTimeout: 3000));

  Future<T?> _callApi<T>(String path, Map<String, dynamic>? queryParameters, T Function(Response) generator,
      {bool secondTry = false}) async {
    try {
      _accessToken ??= await _authorize();
      if (_accessToken == null) return null;
      var result = await _dio.get(path,
          queryParameters: queryParameters, options: Options(headers: {'Authorization': 'Bearer $_accessToken'}));
      return generator(result);
    } catch (e) {
      if (e is DioError && !secondTry) {
        if (e.response?.statusCode == 401) {
          _accessToken = await _authorize();
          return _callApi(path, queryParameters, generator, secondTry: true);
        }
      }
      if (kDebugMode) {
        print(e);
      }
      return null;
    }
  }

  Future<String?> _authorize() async {
    try {
      var res = await _dio.post('/token',
          queryParameters: const {
            'grant_type': 'client_credentials',
            'client_id': String.fromEnvironment('CLIENT_ID'),
            'client_secret': String.fromEnvironment('CLIENT_SECRET'),
          },
          options: Options(contentType: Headers.formUrlEncodedContentType));

      return res.data['access_token'];
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }
      return null;
    }
  }

  Future<Iterable<VehiclePosition>?> getPositions(List<String> journeyIds) async {
    return await _callApi('/fpos/v1/positions', {'journeyIds': journeyIds}, (result) {
      return result.data.map<VehiclePosition>((d) => VehiclePosition(d));
    });
  }
}

class VehiclePosition {
  late String journeyId;
  late int? lastStopId;
  late bool atStop;
  late double lat;
  late double long;
  late double speed;
  late DateTime updatedAt;
  late bool dataStillRelevant;

  VehiclePosition(dynamic data) {
    journeyId = data['journeyId'];
    lastStopId = parseInt(data['lastStopId']);
    atStop = data['atStop'];
    lat = data['lat'];
    long = data['long'];
    speed = data['speed'];
    updatedAt = DateTime.parse(data['updatedAt']).toLocal();
    dataStillRelevant = data['dataStillRelevant'];
  }
}
