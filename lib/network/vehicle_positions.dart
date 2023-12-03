import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../utils.dart';

class VehiclePositions {
  static String? _accessToken;

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://ext-api.vasttrafik.se',
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));

  static Future<T?> _callApi<T>(String path, Json? queryParameters, T Function(Response) generator,
      {bool secondTry = false}) async {
    try {
      _accessToken ??= await _authorize();
      if (_accessToken == null) return null;
      var result = await _dio.get(path,
          queryParameters: queryParameters, options: Options(headers: {'Authorization': 'Bearer $_accessToken'}));
      return generator(result);
    } catch (error) {
      if (error is DioException && !secondTry) {
        if (error.response?.statusCode == 401) {
          _accessToken = await _authorize();
          return _callApi(path, queryParameters, generator, secondTry: true);
        }
      }
      if (kDebugMode) {
        print(error);
      }
      return null;
    }
  }

  static Future<String?> _authorize() async {
    try {
      var res = await _dio.post('/token',
          queryParameters: const {
            'grant_type': 'client_credentials',
            'client_id': String.fromEnvironment('CLIENT_ID'),
            'client_secret': String.fromEnvironment('CLIENT_SECRET'),
          },
          options: Options(contentType: Headers.formUrlEncodedContentType));

      return res.data['access_token'];
    } catch (error) {
      if (kDebugMode) {
        print(error);
      }
      return null;
    }
  }

  static Future<Iterable<LiveVehiclePosition>?> getPositions(List<String> journeyIds) async {
    return await _callApi('/fpos/v1/positions', {'journeyIds': journeyIds}, (result) {
      return result.data.map<LiveVehiclePosition>((d) => LiveVehiclePosition.fromJson(d));
    });
  }
}

abstract class VehiclePosition {
  late String journeyId;
  late LatLng position;
  late double? speed;
  late DateTime updatedAt;

  double get speedOrZero => speed ?? 0;

  VehiclePosition.fromJson(dynamic data) {
    journeyId = data['journeyId'];
    position = LatLng(data['lat'], data['long']);
    speed = data['speed'];
    updatedAt = DateTime.parse(data['updatedAt']).toLocal();
  }

  VehiclePosition();
}

class LiveVehiclePosition extends VehiclePosition {
  late String? lastStopId;
  late bool atStop;
  late bool dataStillRelevant;

  LiveVehiclePosition.fromJson(dynamic data) : super.fromJson(data) {
    lastStopId = data['lastStopId'];
    atStop = data['atStop'];
    dataStillRelevant = data['dataStillRelevant'];
  }
}
