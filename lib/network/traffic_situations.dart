import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../extensions.dart';
import '../utils.dart';
import 'planera_resa.dart';

class TrafficSituations {
  static final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://ext-api.vasttrafik.se/ts/v1',
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));

  static Future<T> _callApi<T>(String path, Json? queryParameters, T Function(Response) generator) =>
      PlaneraResa.callApi(path, queryParameters, generator, dio: _dio);

  static Future<Iterable<TrafficSituation>> getTrafficSituationsForJourney(String journeyId) async {
    return await _callApi('/traffic-situations/journey/$journeyId', {}, (result) {
      var data = forceList(result.data);
      return data.map((t) => TrafficSituation(t));
    });
  }

  static Future<Iterable<TrafficSituation>> getTrafficSituationsForLine(String lineId) async {
    return await _callApi('/traffic-situations/line/$lineId', {}, (result) {
      var data = forceList(result.data);
      return data.map((t) => TrafficSituation(t));
    });
  }

  static Future<Iterable<TrafficSituation>> getTrafficSituationsForStopArea(String stopAreaGid) async {
    return await _callApi('/traffic-situations/stoparea/$stopAreaGid', {}, (result) {
      var data = forceList(result.data);
      return data.map((t) => TrafficSituation(t));
    });
  }
}

List<dynamic> forceList(dynamic a) {
  if (a == null) return [];
  return a is List ? a : [a];
}

class TrafficSituation implements TS {
  late DateTime startTime;
  late Iterable<TSLine> affectedLines;
  late String title;
  late String? description;
  late Severity severity;
  late DateTime creationTime;
  late DateTime? endTime;
  late Iterable<TSJourney> affectedJourneys;
  late String situationNumber;
  late Iterable<TSStop> affectedStopPoints;

  TrafficSituation(dynamic data) {
    startTime = DateTime.parse(data['startTime']);
    affectedLines = forceList(data['affectedLines']).map((l) => TSLine(l));
    title = removeToGoMentions(data['title'])!;
    description = removeToGoMentions(data['description']);
    severity = Severity.fromString(data['severity']);
    creationTime = DateTime.parse(data['creationTime']);
    endTime = DateTime.parse(data['endTime']);
    affectedJourneys = forceList(data['affectedJourneys']).map((j) => TSJourney(j));
    situationNumber = data['situationNumber'];
    affectedStopPoints = forceList(data['affectedStopPoints']).map((s) => TSStop(s));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrafficSituation &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          description == other.description &&
          severity == other.severity;

  @override
  int get hashCode => title.hashCode ^ description.hashCode ^ severity.hashCode;

  @override
  Widget display(BuildContext context, {bool boldTitle = false, bool showAffectedStop = false}) {
    showAffectedStop = showAffectedStop &&
        affectedStopPoints.map((s) => s.name).toSet().length == 1 &&
        !title.contains(affectedStopPoints.first.name);
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Row(
        children: [
          getNoteIcon(severity),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              children: [
                Align(
                    alignment: Alignment.centerLeft,
                    child: Text(showAffectedStop ? '${affectedStopPoints.first.name}: $title' : title,
                        style: boldTitle ? const TextStyle(fontWeight: FontWeight.bold) : null)),
                if (!description.isNullOrEmpty) const SizedBox(height: 5),
                if (!description.isNullOrEmpty)
                  Align(
                      alignment: Alignment.centerLeft,
                      child: Text(description!,
                          style: TextStyle(color: Theme.of(context).hintColor), textAlign: TextAlign.left)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TSLine {
  late Iterable<TSDirection> directions;
  late String? transportAuthorityName;
  late Color? textColor;
  late String? transportAuthorityCode;
  late String? defaultTransportModeCode;
  late int? technicalNumber;
  late Color? backgroundColor;
  late String? name;
  late String? designation;
  late String gid;

  TSLine(dynamic data) {
    directions = data['directions'].map<TSDirection>((d) => TSDirection(d));
    transportAuthorityName = data['transportAuthorityName'];
    textColor = tryFromHex(data['textColor']);
    transportAuthorityCode = data['transportAuthorityCode'];
    defaultTransportModeCode = data['defaultTransportModeCode'];
    technicalNumber = data['technicalNumber'];
    backgroundColor = tryFromHex(data['backgroundColor']);
    name = data['name'];
    designation = data['designation'];
    gid = data['gid'];
  }
}

class TSStop {
  late String? stopAreaShortName;
  late String? stopAreaName;
  late String? stopAreaGid;
  late String name;
  late String gid;
  late String? shortName;
  late int? municipalityNumber;
  late String? municipalityName;

  TSStop(dynamic data) {
    stopAreaShortName = data['stopAreaShortName'];
    stopAreaName = data['stopAreaName'];
    stopAreaGid = data['stopAreaGid'];
    name = data['name'];
    gid = data['gid'];
    shortName = data['shortName'];
    municipalityNumber = data['municipalityNumber'];
    municipalityName = data['municipalityName'];
  }
}

class TSDirection {
  late String? name;
  late String gid;
  late int? directionCode;

  TSDirection(dynamic data) {
    name = data['name'];
    gid = data['gid'];
    directionCode = data['directionCode'];
  }
}

class TSJourney {
  late String gid;
  late TSLine line;

  TSJourney(dynamic data) {
    gid = data['gid'];
    line = TSLine(data['line']);
  }
}
