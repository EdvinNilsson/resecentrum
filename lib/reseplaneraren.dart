import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'extensions.dart';
import 'utils.dart';

part 'reseplaneraren.g.dart';

Reseplaneraren reseplaneraren = Reseplaneraren();

class Reseplaneraren {
  String? _accessToken;
  final String _uuid = const Uuid().v4();

  final Dio _dio = Dio(
      BaseOptions(baseUrl: 'https://api.vasttrafik.se/bin/rest.exe/v2', connectTimeout: 10000, receiveTimeout: 10000));

  final Dio _tsDio =
      Dio(BaseOptions(baseUrl: 'https://api.vasttrafik.se/ts/v1', connectTimeout: 10000, receiveTimeout: 10000));

  Future<T?> _callApi<T>(String path, Map<String, dynamic>? queryParameters, T Function(Response) generator,
      {bool secondTry = false, Dio? altDio, Duration retry = const Duration(seconds: 1, milliseconds: 500)}) async {
    _accessToken ??= await _authorize();
    if (_accessToken == null) return null;
    var result = (altDio ?? _dio).get(path,
        queryParameters: queryParameters, options: Options(headers: {'Authorization': 'Bearer $_accessToken'}));
    if (secondTry) {
      return result.then<T?>(generator).catchError((_) => null);
    } else {
      return Future.any([
        result.then(generator),
        () async {
          bool complete = false;
          result.whenComplete(() => complete = true);
          await Future.delayed(retry);
          return !complete ? _callApi(path, queryParameters, generator, secondTry: true) : null;
        }()
      ]).catchError((e, stackTrace) async {
        if (e is DioError && !secondTry) {
          if (e.response?.statusCode == 401) {
            _accessToken = await _authorize();
            return _callApi(path, queryParameters, generator, secondTry: true);
          }
        }
        if (kDebugMode) {
          print(e);
          print(stackTrace);
        }
      });
    }
  }

  Future<String?> _authorize() async {
    try {
      var dio = Dio(BaseOptions(
        baseUrl: 'https://api.vasttrafik.se',
        connectTimeout: 5000,
        receiveTimeout: 5000,
      ));

      const base64 = Base64Codec();
      const utf8 = Utf8Codec();

      const String auth = '${const String.fromEnvironment('AUTH_KEY')}:${const String.fromEnvironment('AUTH_SECRET')}';
      String authHeader = 'Basic ${base64.encode(utf8.encode(auth))}';

      dio.options.contentType = 'application/x-www-form-urlencoded';
      dio.options.headers['Authorization'] = authHeader;

      var res =
          await dio.post('/token', queryParameters: {'grant_type': 'client_credentials', 'scope': 'device_$_uuid'});

      if (kDebugMode) {
        print(res.data['access_token']);
      }
      return res.data['access_token'];
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }
      return null;
    }
  }

  Future<Iterable<Trip>?> getTrip(
      {int? originId,
      double? originCoordLat,
      double? originCoordLong,
      String? originCoordName,
      int? destId,
      double? destCoordLat,
      double? destCoordLong,
      String? destCoordName,
      int? viaId,
      DateTime? dateTime,
      bool? searchForArrival,
      bool? useVas,
      bool? useLDTrain,
      bool? useRegTrain,
      bool? useBus,
      bool? useMedical,
      bool? originMedicalCon,
      bool? destMedicalCon,
      bool? wheelChairSpace,
      bool? strollerSpace,
      bool? lowFloor,
      bool? rampOrLift,
      bool? useBoat,
      bool? useTram,
      bool? usePT,
      bool? excludeDR,
      int? maxWalkDist,
      double? walkSpeed,
      bool? originWalk,
      bool? destWalk,
      bool? onlyWalk,
      bool? originBike,
      int? maxBikeDist,
      String? bikeCriterion,
      String? bikeProfile,
      bool? onlyBike,
      bool? originCar,
      String? originCarWithParking,
      int? maxCarDist,
      bool? onlyCar,
      int? maxChanges,
      int? additionalChangeTime,
      bool? disregardDefaultChangeMargin,
      bool? needJourneyDetail,
      bool? needGeo,
      bool? needItinerary,
      int? numTrips}) async {
    var param = {'format': 'json'};

    if (originId != null) param['originId'] = originId.toString();
    if (originCoordLat != null) param['originCoordLat'] = originCoordLat.toString();
    if (originCoordLong != null) param['originCoordLong'] = originCoordLong.toString();
    if (originCoordName != null) param['originCoordName'] = originCoordName;
    if (destId != null) param['destId'] = destId.toString();
    if (destCoordLat != null) param['destCoordLat'] = destCoordLat.toString();
    if (destCoordLong != null) param['destCoordLong'] = destCoordLong.toString();
    if (destCoordName != null) param['destCoordName'] = destCoordName;
    if (viaId != null) param['viaId'] = viaId.toString();
    if (dateTime != null) param['date'] = DateFormat('yyyy-MM-dd').format(dateTime);
    if (dateTime != null) param['time'] = DateFormat.Hm().format(dateTime);
    if (searchForArrival != null) param['searchForArrival'] = boolAsIntString(searchForArrival);
    if (useVas != null) param['useVas'] = boolAsIntString(useVas);
    if (useLDTrain != null) param['useLDTrain'] = boolAsIntString(useLDTrain);
    if (useRegTrain != null) param['useRegTrain'] = boolAsIntString(useRegTrain);
    if (useBus != null) param['useBus'] = boolAsIntString(useBus);
    if (useMedical != null) param['useMedical'] = boolAsIntString(useMedical);
    if (originMedicalCon != null) param['originMedicalCon'] = boolAsIntString(originMedicalCon);
    if (destMedicalCon != null) param['destMedicalCon'] = boolAsIntString(destMedicalCon);
    if (wheelChairSpace != null) param['wheelChairSpace'] = boolAsIntString(wheelChairSpace);
    if (strollerSpace != null) param['strollerSpace'] = boolAsIntString(strollerSpace);
    if (lowFloor != null) param['lowFloor'] = boolAsIntString(lowFloor);
    if (rampOrLift != null) param['rampOrLift'] = boolAsIntString(rampOrLift);
    if (useBoat != null) param['useBoat'] = boolAsIntString(useBoat);
    if (useTram != null) param['useTram'] = boolAsIntString(useTram);
    if (usePT != null) param['usePT'] = boolAsIntString(usePT);
    if (excludeDR != null) param['excludeDR'] = boolAsIntString(excludeDR);
    if (maxWalkDist != null) param['maxWalkDist'] = maxWalkDist.toString();
    if (walkSpeed != null) param['walkSpeed'] = walkSpeed.toString();
    if (originWalk != null) param['originWalk'] = boolAsIntString(originWalk);
    if (destWalk != null) param['destWalk'] = boolAsIntString(destWalk);
    if (onlyWalk != null) param['onlyWalk'] = boolAsIntString(onlyWalk);
    if (originBike != null) param['originBike'] = boolAsIntString(originBike);
    if (maxBikeDist != null) param['maxBikeDist'] = maxBikeDist.toString();
    if (bikeCriterion != null) param['bikeCriterion'] = bikeCriterion;
    if (bikeProfile != null) param['bikeProfile'] = bikeProfile;
    if (onlyBike != null) param['onlyBike'] = boolAsIntString(onlyBike);
    if (originCar != null) param['originCar'] = boolAsIntString(originCar);
    if (originCarWithParking != null) param['originCarWithParking'] = originCarWithParking;
    if (maxCarDist != null) param['maxCarDist'] = maxCarDist.toString();
    if (onlyCar != null) param['onlyCar'] = boolAsIntString(onlyCar);
    if (maxChanges != null) param['maxChanges'] = maxChanges.toString();
    if (additionalChangeTime != null) param['additionalChangeTime'] = additionalChangeTime.toString();
    if (needJourneyDetail != null) param['needJourneyDetail'] = boolAsIntString(needJourneyDetail);
    if (needGeo != null) param['needGeo'] = boolAsIntString(needGeo);
    if (needItinerary != null) param['needItinerary'] = boolAsIntString(needItinerary);
    if (numTrips != null) param['numTrips'] = numTrips.toString();
    if (disregardDefaultChangeMargin != null) {
      param['disregardDefaultChangeMargin'] = boolAsIntString(disregardDefaultChangeMargin);
    }

    return await _callApi('/trip', param, (result) {
      var data = result.data['TripList'];
      var trips = forceList(data['Trip']);
      return trips.map((trip) => Trip(trip));
    }, retry: const Duration(seconds: 5));
  }

  Future<Iterable<Location>?> getLocationByName(String input, {bool onlyStops = false}) async {
    return await _callApi('/location.name', {'input': input, 'format': 'json'}, (result) {
      var data = result.data['LocationList'];

      Iterable<StopLocation> stopLocations = forceList(data['StopLocation'])
          .map((stop) => StopLocation.fromJson(stop))
          .where((stop) => stop.id >= 900000000);
      if (onlyStops) return stopLocations;

      Iterable<CoordLocation> coordLocations =
          forceList(data['CoordLocation']).map((coord) => CoordLocation.fromJson(coord));

      return merge(stopLocations.toList(growable: false), coordLocations.toList(growable: false),
          (Location a, Location b) => a.idx.compareTo(b.idx));
    });
  }

  Future<CoordLocation?> getLocationNearbyAddress(double lat, double long) async {
    return await _callApi('/location.nearbyaddress', {'originCoordLat': lat, 'originCoordLong': long, 'format': 'json'},
        (result) {
      var data = result.data['LocationList'];
      return CoordLocation.fromJson(data['CoordLocation']);
    });
  }

  Future<Iterable<StopLocation>?> getLocationNearbyStops(double lat, double long, {int? maxNo, int? maxDist}) async {
    var param = {'originCoordLat': lat, 'originCoordLong': long, 'format': 'json'};

    if (maxNo != null) param['maxNo'] = maxNo;
    if (maxDist != null) param['maxDist'] = maxDist;

    return await _callApi('/location.nearbystops', param, (result) {
      var data = result.data['LocationList'];
      return forceList(data['StopLocation']).map((stop) => StopLocation.fromJson(stop));
    });
  }

  Future<Iterable<Departure>?> getDepartureBoard(int id,
      {DateTime? dateTime,
      int? direction,
      bool? useVas,
      bool? useLDTrain,
      bool? useRegTrain,
      bool? useBus,
      bool? useBoat,
      bool? useTram,
      int? timeSpan}) async {
    var param = {'id': id, 'format': 'json'};

    if (dateTime != null) param['date'] = DateFormat('yyyy-MM-dd').format(dateTime);
    if (dateTime != null) param['time'] = DateFormat.Hm().format(dateTime);
    if (direction != null) param['direction'] = direction;
    if (useVas != null) param['useVas'] = boolAsIntString(useVas);
    if (useLDTrain != null) param['useLDTrain'] = boolAsIntString(useLDTrain);
    if (useRegTrain != null) param['useRegTrain'] = boolAsIntString(useRegTrain);
    if (useBus != null) param['useBus'] = boolAsIntString(useBus);
    if (useBoat != null) param['useBoat'] = boolAsIntString(useBoat);
    if (useTram != null) param['useTram'] = boolAsIntString(useTram);
    if (timeSpan != null) param['timeSpan'] = timeSpan.toString();

    return await _callApi('/departureBoard', param, (result) {
      var data = result.data['DepartureBoard'];
      var departures = forceList(data['Departure']);
      return departures.map((d) => Departure(d));
    });
  }

  Future<Iterable<Departure>?> getArrivalBoard(int id,
      {DateTime? dateTime,
      int? direction,
      bool? useVas,
      bool? useLDTrain,
      bool? useRegTrain,
      bool? useBus,
      bool? useBoat,
      bool? useTram,
      int? timeSpan}) async {
    var param = {'id': id, 'format': 'json'};

    if (dateTime != null) param['date'] = DateFormat('yyyy-MM-dd').format(dateTime);
    if (dateTime != null) param['time'] = DateFormat.Hm().format(dateTime);
    if (direction != null) param['direction'] = direction;
    if (useVas != null) param['useVas'] = boolAsIntString(useVas);
    if (useLDTrain != null) param['useLDTrain'] = boolAsIntString(useLDTrain);
    if (useRegTrain != null) param['useRegTrain'] = boolAsIntString(useRegTrain);
    if (useBus != null) param['useBus'] = boolAsIntString(useBus);
    if (useBoat != null) param['useBoat'] = boolAsIntString(useBoat);
    if (useTram != null) param['useTram'] = boolAsIntString(useTram);
    if (timeSpan != null) param['timeSpan'] = timeSpan.toString();

    return await _callApi('/arrivalBoard', param, (result) {
      var data = result.data['ArrivalBoard'];
      var departures = forceList(data['Arrival']);
      return departures.map((d) => Departure(d, arrival: true));
    });
  }

  Future<JourneyDetail?> getJourneyDetail(String ref) async {
    return await _callApi('/journeyDetail', Uri.splitQueryString(ref.split('?').last), (result) {
      var data = result.data['JourneyDetail'];
      return JourneyDetail(data);
    });
  }

  Future<Iterable<Iterable<Point>>?> getGeometry(String ref) async {
    return await _callApi('/geometry', Uri.splitQueryString(ref.split('?').last), (result) {
      var data = forceList(result.data['Geometry']['Points']);
      return data.map<Iterable<Point>>((points) => points['Point'].map<Point>((point) => Point(point)).toList());
    });
  }

  Future<TimetableInfo?> getSystemInfo() async {
    return await _callApi('/systeminfo', {'format': 'json'}, (result) {
      var data = result.data['SystemInfo']['TimetableInfo'];
      return TimetableInfo(data);
    });
  }

  Future<Iterable<TrafficSituation>?> getTrafficSituationsByJourneyId(String journeyId) async {
    return await _callApi('/traffic-situations/journey/$journeyId', {}, (result) {
      var data = forceList(result.data);
      return data.map((t) => TrafficSituation(t));
    }, altDio: _tsDio);
  }

  Future<Iterable<TrafficSituation>?> getTrafficSituationsByLineId(String lineId) async {
    return await _callApi('/traffic-situations/line/$lineId', {}, (result) {
      var data = forceList(result.data);
      return data.map((t) => TrafficSituation(t));
    }, altDio: _tsDio);
  }

  Future<Iterable<TrafficSituation>?> getTrafficSituationsByStopId(int stopId) async {
    return await _callApi('/traffic-situations/stoparea/$stopId', {}, (result) {
      var data = forceList(result.data);
      return data.map((t) => TrafficSituation(t));
    }, altDio: _tsDio);
  }
}

List<dynamic> forceList(dynamic a) {
  if (a == null) return [];
  return a is List ? a : [a];
}

double? parseDouble(String? input) {
  if (input == null) return null;
  return double.tryParse(input);
}

int? parseInt(String? input) {
  if (input == null) return null;
  return int.tryParse(input);
}

DateTime? parseDateTime(String? date, String? time) {
  if (date == null || time == null) return null;
  return DateTime.parse('$date $time');
}

String boolAsIntString(bool state) => state ? '1' : '0';

abstract class Location {
  @HiveField(0)
  late double lon;
  @HiveField(1)
  late double lat;
  @HiveField(2)
  late String name;
  late int idx;

  Location() {
    idx = 0;
  }

  Location.fromJson(dynamic data) {
    lon = double.parse(data['lon']);
    idx = parseInt(data['idx']) ?? 0;
    name = data['name'];
    lat = double.parse(data['lat']);
  }

  Location.fromStop(Stop stop) {
    lon = stop.lon;
    lat = stop.lat;
    name = stop.name;
    idx = 0;
  }

  @override
  bool operator ==(Object other) => (other is Location) && name == other.name;

  @override
  int get hashCode => name.hashCode;
}

@HiveType(typeId: 0)
class StopLocation extends Location {
  @HiveField(3)
  late int id;
  late String? weight;
  late String? track;

  StopLocation();

  StopLocation.fromJson(dynamic data) : super.fromJson(data) {
    id = int.parse(data['id']);
    weight = data['weight'];
    track = data['track'];
  }

  StopLocation.fromStop(Stop stop) : super.fromStop(stop) {
    id = stop.id;
    track = stop.rtTrack ?? stop.track;
  }

  bool get isStopArea => id >= 900000000 && id < 9022000000000000;

  @override
  bool operator ==(Object other) => (other is StopLocation) && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

@HiveType(typeId: 1)
class CoordLocation extends Location {
  @HiveField(3)
  late String type;

  CoordLocation();

  CoordLocation.fromJson(dynamic data) : super.fromJson(data) {
    type = data['type'];
  }

  bool get isValid => name != 'noAddressAvailableWithinTheGivenRadius';
}

class Departure {
  late Color fgColor;
  late String stop;
  late bool? booking;
  late String journeyDetailRef;
  late String direction;
  late String? track;
  late String? rtTrack;
  late String sname;
  late String type;
  late DateTime dateTime;
  late Color bgColor;
  late String stroke;
  late DateTime? rtDateTime;
  late String name;
  late bool? night;
  late int stopId;
  late String journeyId;
  late String? accessibility;
  late bool cancelled;
  late int journeyNumber;
  late bool arrival;

  Departure(dynamic data, {this.arrival = false}) {
    fgColor = fromHex(data['fgColor']);
    stop = data['stop'];
    booking = data['booking'] == 'true';
    journeyDetailRef = data['JourneyDetailRef']['ref'];
    direction = arrival ? stop.firstPart() : data['direction'];
    track = data['track'];
    rtTrack = data['rtTrack'];
    sname = data['sname'];
    type = data['type'];
    dateTime = parseDateTime(data['date'], data['time'])!;
    bgColor = fromHex(data['bgColor']);
    stroke = data['stroke'];
    rtDateTime = parseDateTime(data['rtDate'], data['rtTime']);
    name = data['name'].replaceFirst(' TÅG', '');
    night = data['night'] == 'true';
    stopId = int.parse(data['stopid']);
    journeyId = data['journeyid'];
    accessibility = data['accessibility'];
    cancelled = data['cancelled'] == 'true';
    journeyNumber = int.parse(data['journeyNumber']);
  }

  DateTime getDateTime() => rtDateTime ?? dateTime;
}

class JourneyDetail {
  late Iterable<JourneyType> journeyType;
  late String? errorText;
  late String? error;
  late Iterable<JourneyId> journeyId;
  late Iterable<Direction> direction;
  late Iterable<Stop> stop;
  late Iterable<JourneyName> journeyName;
  late String geometryRef;
  late Color fgColor;
  late Color bgColor;
  late String stroke;

  JourneyDetail(dynamic data) {
    journeyType = forceList(data['JourneyType']).map((jt) => JourneyType(jt));
    errorText = data['errorText'];
    error = data['error'];
    journeyId = forceList(data['JourneyId']).map((jt) => JourneyId(jt));
    direction = forceList(data['Direction']).map((jt) => Direction(jt));
    stop = forceList(data['Stop']).map((s) => Stop(s));
    journeyName = forceList(data['JourneyName']).map((jt) => JourneyName(jt));
    geometryRef = data['GeometryRef']['ref'];
    fgColor = fromHex(data['Color']['fgColor']);
    bgColor = fromHex(data['Color']['bgColor']);
    stroke = data['Color']['stroke'];
  }
}

class Stop {
  late int routeIdx;
  late DateTime? arrDateTime;
  late DateTime? depDateTime;
  late double lon;
  late String? track;
  late String? rtTrack;
  late int id;
  late DateTime? rtArrTime;
  late DateTime? rtDepTime;
  late String name;
  late double lat;

  Stop(dynamic s) {
    routeIdx = int.parse(s['routeIdx']);
    arrDateTime = parseDateTime(s['arrDate'], s['arrTime']);
    depDateTime = parseDateTime(s['depDate'], s['depTime']);
    lon = double.parse(s['lon']);
    track = s['track'];
    rtTrack = s['rtTrack'];
    id = int.parse(s['id']);
    rtArrTime = parseDateTime(s['rtArrDate'], s['rtArrTime']);
    rtDepTime = parseDateTime(s['rtDepDate'], s['rtDepTime']);
    name = s['name'];
    lat = double.parse(s['lat']);
  }

  DateTime? getArrDateTime() => rtArrTime ?? arrDateTime;

  DateTime? getDepDateTime() => rtDepTime ?? depDateTime;

  DateTime getDateTime() => getDepDateTime() ?? getArrDateTime()!;
}

abstract class RouteIdx {
  late int routeIdxTo;
  late int routeIdxFrom;

  RouteIdx(dynamic data) {
    routeIdxTo = int.parse(data['routeIdxTo']);
    routeIdxFrom = int.parse(data['routeIdxFrom']);
  }
}

T getValueAtRouteIdx<T extends RouteIdx>(Iterable<T> routeIdxs, int routeIdx) {
  return routeIdxs.firstWhere((r) => routeIdx >= r.routeIdxFrom && routeIdx < r.routeIdxTo);
}

class JourneyId extends RouteIdx {
  late String id;

  JourneyId(dynamic data) : super(data) {
    id = data['id'];
  }
}

class JourneyName extends RouteIdx {
  late String name;

  JourneyName(dynamic data) : super(data) {
    name = data['name'];
  }
}

class Direction extends RouteIdx {
  late String direction;

  Direction(dynamic data) : super(data) {
    direction = data['\$'];
  }
}

class JourneyType extends RouteIdx {
  late String type;

  JourneyType(dynamic data) : super(data) {
    type = data['type'];
  }
}

class Point {
  late double lon;
  late double lat;

  Point(dynamic data) {
    lon = double.parse(data['lon']);
    lat = double.parse(data['lat']);
  }
}

class Trip {
  late List<Leg> leg;
  late bool travelWarranty;
  late bool valid;
  late bool alternative;
  late String? type;

  Trip(dynamic data) {
    leg = forceList(data['Leg']).map((l) => Leg(l)).toList(growable: false);
    travelWarranty = data['travelWarranty'] != 'false';
    valid = data['valid'] != 'false';
    alternative = data['alternative'] == 'true';
    type = data['Type'];
  }
}

class Leg {
  late Color? fgColor;
  late bool? booking;
  late String? direction;
  late String? journeyDetailRef;
  late bool cancelled;
  late double? kcal;
  late TripLocation origin;
  late String? sname;
  late String type;
  late String? geometryRef;
  late Color? bgColor;
  late Iterable<Note> notes;
  late String? journeyId;
  late String? stroke;
  late bool? reachable;
  late String name;
  late bool? night;
  late TripLocation destination;
  late double? percentBikeRoad;
  late String? accessibility;
  late int? journeyNumber;

  Iterable<Iterable<Point>>? cachedGeometry;

  Future<Iterable<Iterable<Point>>?> geometry() async {
    if (geometryRef == null) return null;
    cachedGeometry ??= await reseplaneraren.getGeometry(geometryRef!);
    return cachedGeometry;
  }

  Leg(dynamic data) {
    fgColor = tryFromHex(data['fgColor']);
    booking = data['booking'] == 'true';
    direction = data['direction'];
    journeyDetailRef = data['JourneyDetailRef'] != null ? data['JourneyDetailRef']['ref'] : null;
    cancelled = data['cancelled'] == 'true';
    kcal = parseDouble(data['kcal']);
    origin = TripLocation(data['Origin']);
    sname = data['sname'];
    type = data['type'];
    geometryRef = data['GeometryRef'] != null ? data['GeometryRef']['ref'] : null;
    bgColor = tryFromHex(data['bgColor']);
    notes = data['Notes'] != null ? forceList(data['Notes']['Note']).map((n) => Note(n)) : [];
    journeyId = data['id'];
    stroke = data['stroke'];
    reachable = data['reachable'] == 'true';
    name = data['name'];
    night = data['night'] == 'true';
    destination = TripLocation(data['Destination']);
    percentBikeRoad = parseDouble(data['percentBikeRoad']);
    accessibility = data['accessibility'];
    journeyNumber = parseInt(data['journeyNumber']);
  }
}

class TripLocation {
  late int? routeIdx;
  late bool cancelled;
  late String? track;
  late String? rtTrack;
  late String type;
  late DateTime dateTime;
  late Iterable<Note> notes;
  late int? id;
  late DateTime? rtDateTime;
  late String name;
  late DateTime? directDateTime;

  TripLocation(dynamic data) {
    routeIdx = parseInt(data['routeIdx']);
    cancelled = data['cancelled'] == 'true';
    track = data['track'];
    rtTrack = data['rtTrack'];
    type = data['type'];
    dateTime = parseDateTime(data['date'], data['time'])!;
    notes = data['Notes'] != null ? forceList(data['Notes']['Note']).map((n) => Note(n)) : [];
    id = parseInt(data['id']);
    rtDateTime = parseDateTime(data['rtDate'], data['rtTime']);
    name = data['name'];
    directDateTime = parseDateTime(data['directdate'], data['directtime']);
  }

  DateTime getDateTime() => rtDateTime ?? dateTime;
}

class Note {
  late int priority;
  late String severity;
  late String? key;
  late String? text;

  Note(dynamic data) {
    priority = int.parse(data['priority']);
    severity = data['severity'];
    key = data['key'];
    text = data['\$'];
  }

  @override
  bool operator ==(Object other) => (other is Note) && severity == other.severity && text == other.text;

  @override
  int get hashCode => severity.hashCode + text.hashCode;
}

class TimetableInfo {
  late DateTime creationDate;
  late DateTime dateBegin;
  late DateTime dateEnd;

  TimetableInfo(dynamic data) {
    creationDate = DateTime.parse(data['TimeTableData']['CreationDate']['\$']);
    dateBegin = DateTime.parse(data['TimeTablePeriod']['DateBegin']['\$']);
    dateEnd = DateTime.parse(data['TimeTablePeriod']['DateEnd']['\$']);
  }
}

class TrafficSituation {
  late DateTime startTime;
  late Iterable<TSLine> affectedLines;
  late String title;
  late String? description;
  late String severity;
  late DateTime creationTime;
  late DateTime? endTime;
  late Iterable<TSJourney> affectedJourneys;
  late String situationNumber;
  late Iterable<TSStop> affectedStopPoints;

  TrafficSituation(dynamic data) {
    startTime = DateTime.parse(data['startTime']);
    affectedLines = forceList(data['affectedLines']).map((l) => TSLine(l));
    title = data['title'];
    description = data['description'];
    severity = data['severity'];
    creationTime = DateTime.parse(data['creationTime']);
    endTime = DateTime.parse(data['endTime']);
    affectedJourneys = forceList(data['affectedJourneys']).map((j) => TSJourney(j));
    situationNumber = data['situationNumber'];
    affectedStopPoints = forceList(data['affectedStopPoints']).map((s) => TSStop(s));
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
  late int gid;
  late String? shortName;
  late int? municipalityNumber;
  late String? municipalityName;

  TSStop(dynamic data) {
    stopAreaShortName = data['stopAreaShortName'];
    stopAreaName = data['stopAreaName'];
    stopAreaGid = data['stopAreaGid'];
    name = data['name'];
    gid = int.parse(data['gid']);
    shortName = data['shortName'];
    municipalityNumber = data['municipalityNumber'];
    municipalityName = data['municipalityName'];
  }
}

class TSDirection {
  late String? name;
  late int gid;
  late int? directionCode;

  TSDirection(dynamic data) {
    name = data['name'];
    gid = int.parse(data['gid']);
    directionCode = data['directionCode'];
  }
}

class TSJourney {
  late int gid;
  late TSLine line;

  TSJourney(dynamic data) {
    gid = int.parse(data['gid']);
    line = data['line'].map((l) => TSLine(l));
  }
}
