import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:maplibre_gl/maplibre_gl.dart' hide Error;
import 'package:uuid/uuid.dart';

import '../extensions.dart';
import '../utils.dart';

part 'planera_resa.g.dart';

class PlaneraResa {
  static String? accessToken;
  static final String _uuid = const Uuid().v4();

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://ext-api.vasttrafik.se/pr/v4',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  static Future<T> callApi<T>(String path, Json? queryParameters, T Function(Response) generator,
      {bool secondTry = false, Dio? dio}) async {
    try {
      accessToken ??= await authorize();

      var response = await (dio ?? _dio).get(path,
          queryParameters: queryParameters,
          options: Options(headers: {'Authorization': 'Bearer $accessToken', 'Accept-Language': 'sv-SE'}));
      return generator(response);
    } on DioException catch (error) {
      if (!secondTry && (error.response?.statusCode == 401 || error.response?.statusCode == 403)) {
        accessToken = await authorize();
        return callApi(path, queryParameters, generator, secondTry: true, dio: dio);
      }
      if (error.response != null) checkError(error.response!);
      return Future.error(NoInternetError(error));
    } catch (error, stackTrace) {
      if (kDebugMode) {
        print(error);
        print(stackTrace);
      }
      return Future.error(error);
    }
  }

  static Future<String> authorize() async {
    const base64 = Base64Codec();
    const utf8 = Utf8Codec();

    const String auth = '${const String.fromEnvironment('AUTH_KEY')}:${const String.fromEnvironment('AUTH_SECRET')}';

    var dio = Dio(BaseOptions(
        baseUrl: 'https://ext-api.vasttrafik.se',
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        contentType: Headers.formUrlEncodedContentType,
        headers: {'Authorization': 'Basic ${base64.encode(utf8.encode(auth))}'}));

    try {
      var res =
          await dio.post('/token', queryParameters: {'grant_type': 'client_credentials', 'scope': 'device_$_uuid'});

      return res.data['access_token'];
    } catch (error) {
      if (error is DioException && (error.response?.statusCode == 401 || error.response?.statusCode == 403)) {
        throw DisplayableError('Autentisering misslyckades');
      }
      throw NoInternetError(error);
    }
  }

  static Future<Journeys> journeys({
    String? originGid,
    String? originName,
    LatLng? originCoord,
    String? destinationGid,
    String? destinationName,
    LatLng? destinationCoord,
    DateTime? dateTime,
    DateTimeRelatesToType? dateTimeRelatesTo,
    String? paginationReference,
    int? limit,
    Set<TransportMode>? transportModes,
    Set<TransportSubMode>? transportSubModes,
    bool? onlyDirectConnections,
    bool? includeNearbyStopAreas,
    String? viaGid,
    String? originWalk,
    String? destWalk,
    String? originBike,
    String? destBike,
    String? totalBike,
    String? originCar,
    String? destCar,
    String? originPark,
    String? destPark,
    int? interchangeDurationInMinutes,
    bool? includeOccupancy,
    String? url,
  }) async {
    if (url != null) {
      return await callApi('/$url', {}, (result) {
        return Journeys.fromJson(result.data);
      });
    }

    var params = <String, dynamic>{};

    if (originGid != null) params['originGid'] = originGid;
    if (originName != null) params['originName'] = originName;
    if (originCoord != null) {
      params['originLatitude'] = originCoord.latitude;
      params['originLongitude'] = originCoord.longitude;
    }
    if (destinationGid != null) params['destinationGid'] = destinationGid;
    if (destinationName != null) params['destinationName'] = destinationName;
    if (destinationCoord != null) {
      params['destinationLatitude'] = destinationCoord.latitude;
      params['destinationLongitude'] = destinationCoord.longitude;
    }
    if (dateTime != null) params['dateTime'] = dateTime.toRfc3339String();
    if (dateTimeRelatesTo != null) params['dateTimeRelatesTo'] = dateTimeRelatesTo.name;
    if (paginationReference != null) params['paginationReference'] = paginationReference;
    if (limit != null) params['limit'] = limit;
    if (transportModes != null) {
      params['transportModes'] = transportModes.map((mode) => mode.name).toList(growable: false);
    }
    if (transportSubModes != null) {
      params['transportSubModes'] = transportSubModes.map((mode) => mode.name).toList(growable: false);
    }
    if (onlyDirectConnections != null) params['onlyDirectConnections'] = onlyDirectConnections;
    if (includeNearbyStopAreas != null) params['includeNearbyStopAreas'] = includeNearbyStopAreas;
    if (viaGid != null) params['viaGid'] = viaGid;
    if (originWalk != null) params['originWalk'] = originWalk;
    if (destWalk != null) params['destWalk'] = destWalk;
    if (originBike != null) params['originBike'] = originBike;
    if (destBike != null) params['destBike'] = destBike;
    if (totalBike != null) params['totalBike'] = totalBike;
    if (originCar != null) params['originCar'] = originCar;
    if (destCar != null) params['destCar'] = destCar;
    if (originPark != null) params['originPark'] = originPark;
    if (destPark != null) params['destPark'] = destPark;
    if (interchangeDurationInMinutes != null) params['interchangeDurationInMinutes'] = interchangeDurationInMinutes;
    if (includeOccupancy != null) params['includeOccupancy'] = includeOccupancy;

    return await callApi('/journeys', params, (result) {
      return Journeys.fromJson(result.data);
    });
  }

  static Future<Journey> reconstructJourney(String reconstructionReference, {bool? includeOccupancy}) async {
    var params = <String, dynamic>{'ref': reconstructionReference};

    if (includeOccupancy != null) params['includeOccupancy'] = includeOccupancy;

    return await callApi('/journeys/reconstruct', params, (result) {
      return Journey.fromJson(result.data);
    });
  }

  static Future<JourneyDetails> journeyDetails(String detailsReference, Set<JourneyDetailsIncludeType> includes) async {
    var params = <String, dynamic>{'includes': includes.map((i) => i.name).toList(growable: false)};

    return await callApi('/journeys/$detailsReference/details', params, (result) {
      return JourneyDetails.fromJson(result.data);
    });
  }

  static Future<Iterable<Departure>> departures(String stopAreaGid,
      {DateTime? startDateTime, int? limit, int? timeSpanInMinutes, String? directionGid}) async {
    var params = <String, dynamic>{
      'maxDeparturesPerLineAndDirection': 0,
      'limit': limit ?? 20,
    };

    if (startDateTime != null) params['startDateTime'] = startDateTime.toRfc3339String();
    if (timeSpanInMinutes != null) params['timeSpanInMinutes'] = timeSpanInMinutes;
    if (directionGid != null) params['directionGid'] = directionGid;

    return await callApi('/stop-areas/$stopAreaGid/departures', params, (result) {
      var results = result.data['results'];

      return results.map<Departure>((json) => Departure.fromJson(json));
    });
  }

  static Future<Iterable<Departure>> arrivals(String stopAreaGid,
      {DateTime? startDateTime, int? limit, int? timeSpanInMinutes}) async {
    var params = <String, dynamic>{
      'maxArrivalsPerLineAndDirection': 0,
      'limit': limit ?? 20,
    };

    if (startDateTime != null) params['startDateTime'] = startDateTime.toRfc3339String();
    if (timeSpanInMinutes != null) params['timeSpanInMinutes'] = timeSpanInMinutes;

    return await callApi('/stop-areas/$stopAreaGid/arrivals', params, (result) {
      var results = result.data['results'];
      return cleanUpArrivals(results.map<Departure>((json) => Departure.fromJson(json, arrival: true)));
    });
  }

  static Future<ServiceJourneyDetails> details(DetailsRef ref, Set<DepartureDetailsIncludeType> includes) async {
    Json params = {'includes': includes.map((i) => i.name).toList(growable: false)};

    return switch (ref) {
      DepartureDetailsRef ref =>
        await callApi('/stop-areas/${ref.stopAreaGid}/departures/${ref.detailsReference}/details', params, (result) {
          return ServiceJourneyDetails.fromJson(result.data);
        }),
      TripLegDetailsRef ref => await callApi('/journeys/${ref.detailsReference}/details', params, (result) {
          return ServiceJourneyDetails.fromJson(result.data['tripLegs'][ref.tripLegIndex]);
        }),
    };
  }

  static Future<Iterable<Location>> locationsByText(String query, {Set<LocationType>? types, int? limit}) async {
    var params = <String, dynamic>{
      'q': query.isNotEmpty ? query : '.',
      'types': types?.map((i) => i.name).toList(growable: false),
      'limit': limit ?? 20,
    }..removeWhere((key, value) => value == null);

    return await callApi('/locations/by-text', params, (result) {
      Iterable<LocationInfo> results = result.data['results'].map<LocationInfo>((json) => LocationInfo.fromJson(json));
      return results.map((result) => result.toLocation());
    });
  }

  static Future<Iterable<Location>> locationsByCoordinates(LatLng position,
      {Set<LocationType>? types, int? limit, int? radiusInMeters}) async {
    var params = <String, dynamic>{
      'latitude': position.latitude,
      'longitude': position.longitude,
      'types': types?.map((i) => i.name).toList(growable: false),
      'limit': limit,
      'radiusInMeters': radiusInMeters,
    }..removeWhere((key, value) => value == null);

    return await callApi('/locations/by-coordinates', params, (result) {
      Iterable<LocationInfo> results = result.data['results'].map<LocationInfo>((json) => LocationInfo.fromJson(json));
      return results.map((result) => result.toLocation());
    });
  }

  static Future<Iterable<StopLocation>> nearbyStops(LatLng position, {int? limit, int? radiusInMeters}) async =>
      locationsByCoordinates(position, types: {LocationType.stoparea}, limit: limit, radiusInMeters: radiusInMeters)
          .then((location) => location.cast());

  static Future<ValidTimeInterval> validTimeInterval() async {
    return await callApi('/journeys/valid-time-interval', {}, (result) {
      return ValidTimeInterval.fromJson(result.data);
    });
  }
}

Iterable<Departure> cleanUpArrivals(Iterable<Departure> arrivals) sync* {
  Departure? secondLastArrival;
  Departure? lastArrival;
  for (var arrival in arrivals) {
    if ((arrival.serviceJourney.gid != lastArrival?.serviceJourney.gid ||
            arrival.plannedTime != lastArrival?.plannedTime) &&
        (arrival.serviceJourney.gid != secondLastArrival?.serviceJourney.gid ||
            arrival.plannedTime != secondLastArrival?.plannedTime)) {
      yield arrival;
    }
    secondLastArrival = lastArrival;
    lastArrival = arrival;
  }
}

int? parseInt(String? input) {
  if (input == null) return null;
  return int.tryParse(input);
}

double? parseDouble(String? input) {
  if (input == null) return null;
  return double.tryParse(input);
}

DateTime? parseDateTime(String? input) {
  if (input == null) return null;
  return DateTime.tryParse(input)?.toLocal();
}

enum DepartureDetailsIncludeType { serviceJourneyCalls, serviceJourneyCoordinates, occupancy }

enum JourneyDetailsIncludeType {
  ticketSuggestions,
  tripLegCoordinates,
  validZones,
  serviceJourneyCalls,
  serviceJourneyCoordinates,
  links,
  occupancy
}

enum LocationType { unknown, stoparea, stoppoint, address, pointofinterest, metastation }

enum TransportMode { tram, bus, ferry, train, taxi, walk, bike, car }

enum TransportSubMode { unknown, none, vasttagen, longdistancetrain, regionaltrain }

enum OccupancyLevel { low, medium, high, incomplete, missing, notpublictransport }

enum OccupancyInformationSource { prediction, realtime }

enum Severity implements Comparable<Severity> {
  unknown,
  low,
  normal,
  high;

  static Severity fromString(String severity) {
    switch (severity) {
      case 'slight':
      case 'low':
        return Severity.low;
      case 'normal':
        return Severity.normal;
      case 'severe':
      case 'high':
        return Severity.high;
      default:
        return Severity.unknown;
    }
  }

  @override
  int compareTo(Severity other) => Enum.compareByIndex(this, other);
}

enum DateTimeRelatesToType { departure, arrival }

void checkError(Response<dynamic> response) {
  switch (response.statusCode) {
    case 400:
      throw PlaneraResaError.fromJson(response.data);
    case 404:
      throw DisplayableError('Innehållet kunde inte hittas');
    case 500:
      throw DisplayableError('Internt serverfel');
    case 503:
      throw DisplayableError('Tjänsten är inte tillgänglig för tillfället');
  }
}

sealed class DetailsRef {
  late final ServiceJourney serviceJourney;
}

class DepartureDetailsRef extends DetailsRef {
  late final String detailsReference;
  late final String stopAreaGid;

  DepartureDetailsRef(this.detailsReference, ServiceJourney serviceJourney, this.stopAreaGid) {
    this.serviceJourney = serviceJourney;
  }

  DepartureDetailsRef.fromDeparture(Departure departure) {
    detailsReference = departure.detailsReference;
    serviceJourney = departure.serviceJourney;
    stopAreaGid = stopAreaFromStopPoint(departure.stopPoint.gid);
  }
}

class TripLegDetailsRef extends DetailsRef {
  late final String detailsReference;
  late final int tripLegIndex;

  TripLegDetailsRef(Journey journey, ServiceJourney serviceJourney, this.tripLegIndex) {
    detailsReference = journey.detailsReference;
    this.serviceJourney = serviceJourney;
  }
}

class Pagination {
  late int limit;
  late int offset;
  late int size;

  Pagination.fromJson(Json json) {
    limit = json['limit'];
    offset = json['offset'];
    size = json['size'];
  }
}

class Departure with DepartureStateMixin {
  late String detailsReference;
  late ServiceJourney serviceJourney;
  late StopPoint stopPoint;
  late DateTime plannedTime;
  late DateTime? estimatedTime;
  late bool isCancelled;
  late bool isPartCancelled;
  Occupancy? occupancy;

  bool arrival;
  Iterable<String>? deviation;

  DateTime get time => estimatedTime ?? plannedTime;

  int? get delay => getDelay(plannedTime, estimatedTime);

  bool get isTrain => serviceJourney.isTrain;

  int? get trainNumber => serviceJourney.line.trainNumber;

  String getDirection({bool showOrigin = false}) {
    return isTrain
        ? [
            showOrigin && serviceJourney.origin != null
                ? 'Från ${shortStationName(serviceJourney.origin!.firstPart(), useAcronyms: false)}'
                : serviceJourney.direction
          ].followedBy(deviation ?? []).join(', ')
        : serviceJourney.direction;
  }

  Departure.fromJson(Json json, {this.arrival = false}) {
    detailsReference = json['detailsReference'];
    serviceJourney = ServiceJourney.fromJson(json['serviceJourney']);
    stopPoint = StopPoint.fromJson(json['stopPoint']);
    plannedTime = DateTime.parse(json['plannedTime']).toLocal();
    estimatedTime = parseDateTime(json['estimatedTime']);
    isCancelled = json['isCancelled'];
    isPartCancelled = json['isPartCancelled'];
    if (json.containsKey('occupancy')) occupancy = Occupancy.fromJson(json['occupancy']);

    if (arrival) {
      serviceJourney.direction =
          isTrain ? shortStationName(stopPoint.name.firstPart(), useAcronyms: false) : stopPoint.name.firstPart();
    }
  }
}

class ServiceJourney {
  late String gid;
  late String? origin;
  late String direction;
  late Line line;
  late List<LatLng>? serviceJourneyCoordinates;
  late List<Call>? callsOnServiceJourney;

  bool get isTrain => line.isTrain;

  ServiceJourney.fromJson(Json json) {
    gid = json['gid'];
    origin = json['origin'];
    direction = json['direction'] ?? '';
    line = Line.fromJson(json['line']);
    if (json.containsKey('serviceJourneyCoordinates')) {
      serviceJourneyCoordinates = List.from(json['serviceJourneyCoordinates'])
          .map((coord) => LatLng(coord['latitude'], coord['longitude']))
          .toList(growable: false);
    }
    if (json.containsKey('callsOnServiceJourney')) {
      callsOnServiceJourney = List.from(json['callsOnServiceJourney']).map((e) => Call.fromJson(e)).toList();
    }
  }
}

class Line {
  late String? gid;
  late String name;
  late String shortName;
  late String designation;
  late Color backgroundColor;
  late Color foregroundColor;
  late TransportMode transportMode;
  late TransportSubMode transportSubMode;
  late bool isWheelchairAccessible;

  bool get isTrain => transportMode == TransportMode.train;

  int? get trainNumber => isTrain ? int.tryParse(designation) : null;

  Line.fromJson(Json json) {
    gid = json['gid'];
    name = json['name'];
    shortName = json['shortName'] ?? name;
    designation = json['designation'] ?? shortName;
    backgroundColor = fromHex(json['backgroundColor']);
    foregroundColor = fromHex(json['foregroundColor']);
    transportMode = TransportMode.values.asNameMap()[json['transportMode']]!;
    transportSubMode = TransportSubMode.values.asNameMap()[json['transportSubMode']]!;
    isWheelchairAccessible = json['isWheelchairAccessible'] ?? false;
  }
}

class StopPoint {
  late String gid;
  late String name;
  late String? plannedPlatform;
  late LatLng position;
  late StopArea? stopArea;

  String? estimatedPlatform;

  String? get platform => estimatedPlatform ?? plannedPlatform;

  StopPoint.fromJson(Json json) {
    gid = json['gid'];
    name = json['name'];
    plannedPlatform = json['platform'];
    position = LatLng(json['latitude'] ?? 0, json['longitude'] ?? 0);
    if (json.containsKey('stopArea')) stopArea = StopArea.fromJson(json['stopArea']);
  }
}

class Occupancy {
  late OccupancyLevel level;
  late OccupancyInformationSource source;

  Occupancy.fromJson(Json json) {
    level = OccupancyLevel.values.asNameMap()[json['level']]!;
    source = OccupancyInformationSource.values.asNameMap()[json['source']]!;
  }
}

class ServiceJourneyDetails {
  late List<ServiceJourney> serviceJourneys;
  late Occupancy? occupancy;

  Call? get firstCall => serviceJourneys.first.callsOnServiceJourney?.first;

  Call? get lastCall => serviceJourneys.last.callsOnServiceJourney?.last;

  Iterable<Call> get allCalls {
    Iterable<Call> calls = serviceJourneys.first.callsOnServiceJourney!;
    for (var serviceJourney in serviceJourneys.skip(1)) {
      bool skipFirst = calls.last.index == serviceJourney.callsOnServiceJourney!.first.index;
      calls = calls.followedBy(serviceJourney.callsOnServiceJourney!.skip(skipFirst ? 1 : 0));
    }
    return calls;
  }

  ServiceJourneyDetails.fromJson(Json json) {
    serviceJourneys = List.from(json['serviceJourneys']).map((e) => ServiceJourney.fromJson(e)).toList();
    cleanUpServiceJourneys(serviceJourneys);
    if (json.containsKey('occupancy')) occupancy = Occupancy.fromJson(json['occupancy']);
  }

  ServiceJourneyDetails.fromTripLegDetails(TripLegDetails leg) {
    serviceJourneys = leg.serviceJourneys;
    occupancy = leg.occupancy;
  }

  static void cleanUpServiceJourneys(List<ServiceJourney> serviceJourneys) {
    serviceJourneys.removeWhere((serviceJourney) => serviceJourney.gid.length != 16);

    var firstCallsOnServiceJourney = serviceJourneys.first.callsOnServiceJourney!;

    if (firstCallsOnServiceJourney.first.stopPoint.stopArea?.gid ==
            firstCallsOnServiceJourney.elementAt(1).stopPoint.stopArea?.gid ||
        (firstCallsOnServiceJourney.first.plannedDepartureTime ??
                firstCallsOnServiceJourney.first.plannedArrivalTime) ==
            null) {
      firstCallsOnServiceJourney.removeAt(0);
    }

    firstCallsOnServiceJourney.first.plannedArrivalTime = null;
    firstCallsOnServiceJourney.first.estimatedArrivalTime = null;

    var lastCallsOnServiceJourney = serviceJourneys.last.callsOnServiceJourney!;

    if (lastCallsOnServiceJourney.last.stopPoint.stopArea?.gid ==
            lastCallsOnServiceJourney.elementAt(lastCallsOnServiceJourney.length - 2).stopPoint.stopArea?.gid ||
        (lastCallsOnServiceJourney.last.plannedDepartureTime ?? lastCallsOnServiceJourney.last.plannedArrivalTime) ==
            null) {
      lastCallsOnServiceJourney.removeLast();
    }

    lastCallsOnServiceJourney.last.plannedDepartureTime = null;
    lastCallsOnServiceJourney.last.estimatedDepartureTime = null;
  }
}

class Call {
  late StopPoint stopPoint;
  late DateTime? plannedArrivalTime;
  late DateTime? plannedDepartureTime;
  late DateTime? estimatedArrivalTime;
  late DateTime? estimatedDepartureTime;
  late String plannedPlatform;
  late String? estimatedPlatform;
  late LatLng position;
  late int index;
  late Occupancy? occupancy;
  late bool isCancelled;
  late bool isDepartureCancelled;
  late bool isArrivalCancelled;
  late bool? isOnTripLeg;
  late bool? isTripLegStart;
  late bool? isTripLegStop;
  late List<TariffZone>? tariffZones;

  DepartureStateMixin depState = StopDepartureState();
  DepartureStateMixin arrState = StopDepartureState();

  DateTime? get arrivalTime => estimatedArrivalTime ?? plannedArrivalTime;

  DateTime? get departureTime => estimatedDepartureTime ?? plannedDepartureTime;

  String get platform => estimatedPlatform ?? plannedPlatform;

  int? get arrivalDelay => getDelay(plannedArrivalTime!, estimatedArrivalTime);

  int? get departureDelay => getDelay(plannedDepartureTime!, estimatedDepartureTime);

  DateTime get time => estimatedDepartureTime ?? estimatedArrivalTime ?? plannedDepartureTime ?? plannedArrivalTime!;

  DateTime get improvedArrivalTimeEstimation => estimatedArrivalTime == plannedArrivalTime
      ? time
      : estimatedArrivalTime ?? estimatedDepartureTime ?? plannedArrivalTime ?? plannedDepartureTime!;

  Call.fromJson(Json json) {
    stopPoint = StopPoint.fromJson(json['stopPoint']);
    plannedArrivalTime = parseDateTime(json['plannedArrivalTime']);
    plannedDepartureTime = parseDateTime(json['plannedDepartureTime']);
    estimatedArrivalTime = parseDateTime(json['estimatedArrivalTime']);
    estimatedDepartureTime = parseDateTime(json['estimatedDepartureTime']);
    plannedPlatform = json['plannedPlatform'];
    estimatedPlatform = json['estimatedPlatform'];
    position = LatLng(json['latitude'], json['longitude']);
    index = int.parse(json['index']);
    if (json.containsKey('occupancy')) occupancy = Occupancy.fromJson(json['occupancy']);
    isCancelled = json['isCancelled'];
    isDepartureCancelled = json['isDepartureCancelled'] ?? false;
    isArrivalCancelled = json['isArrivalCancelled'] ?? false;
    isOnTripLeg = json['isOnTripLeg'];
    isTripLegStart = json['isTripLegStart'];
    isTripLegStop = json['isTripLegStop'];
    if (json.containsKey('tariffZones')) {
      tariffZones = List.from(json['tariffZones']).map((e) => TariffZone.fromJson(e)).toList(growable: false);
    }
  }
}

class StopArea {
  late String gid;
  late String name;
  late LatLng position;
  late TariffZone tariffZone1;
  late TariffZone? tariffZone2;

  StopArea.fromJson(Json json) {
    gid = json['gid'];
    name = json['name'];
    position = LatLng(json['latitude'], json['longitude']);
    tariffZone1 = TariffZone.fromJson(json['tariffZone1']);
    if (json.containsKey('tariffZone2')) tariffZone2 = TariffZone.fromJson(json['tariffZone2']);
  }
}

class TariffZone {
  late String gid;
  late String name;
  late int number;
  late String shortName;

  TariffZone.fromJson(Json json) {
    gid = json['gid'];
    name = json['name'];
    number = json['number'];
    shortName = json['shortName'];
  }
}

class Journeys {
  late final List<Journey> results;
  late final Pagination? pagination;
  late final Links links;

  Journeys.fromJson(Json json) {
    results = List.from(json['results']).map((e) => Journey.fromJson(e)).toList();
    if (json.containsKey('pagination')) pagination = Pagination.fromJson(json['pagination']);
    links = Links.fromJson(json['links']);
  }
}

class Journey {
  late String reconstructionReference;
  late String detailsReference;
  DepartureAccessLink? departureAccessLink;
  List<TripLeg> tripLegs = [];
  List<ConnectionLink> connectionLinks = [];
  ArrivalAccessLink? arrivalAccessLink;
  DestinationLink? destinationLink;
  late bool isDeparted;
  late Occupancy? occupancy;

  Journey.fromJson(Json json) {
    reconstructionReference = json['reconstructionReference'];
    detailsReference = json['detailsReference'];
    if (json.containsKey('departureAccessLink')) {
      departureAccessLink = DepartureAccessLink.fromJson(json['departureAccessLink']);
    }
    if (json.containsKey('tripLegs')) {
      tripLegs = List.from(json['tripLegs']).map((e) => TripLeg.fromJson(e)).toList(growable: false);
    }
    if (json.containsKey('connectionLinks')) {
      connectionLinks =
          List.from(json['connectionLinks']).map((e) => ConnectionLink.fromJson(e)).toList(growable: false);
    }
    if (json.containsKey('arrivalAccessLink')) {
      arrivalAccessLink = ArrivalAccessLink.fromJson(json['arrivalAccessLink']);
    }
    if (json.containsKey('destinationLink')) destinationLink = DestinationLink.fromJson(json['destinationLink']);
    isDeparted = json['isDeparted'] == true;
    if (json.containsKey('occupancy')) occupancy = Occupancy.fromJson(json['occupancy']);
  }

  Duration get travelTime => lastJourneyLeg.arrivalTime.difference(firstJourneyLeg.departureTime);

  JourneyLeg get firstJourneyLeg => departureAccessLink ?? tripLegs.firstOrNull ?? destinationLink!;

  JourneyLeg get lastJourneyLeg => arrivalAccessLink ?? tripLegs.lastOrNull ?? destinationLink!;

  Iterable<JourneyLeg> get allJourneyLegs => [
        destinationLink,
        departureAccessLink,
        ...[...tripLegs, ...connectionLinks]..sort(),
        arrivalAccessLink
      ].whereType<JourneyLeg>();

  Iterable<(JourneyLeg?, JourneyLeg, JourneyLeg?)> get journeyLegTriplets {
    var legs = allJourneyLegs.toList(growable: false);
    return [
      for (var i = 0; i < legs.length; i++)
        (
          legs.tryElementAt(i - 1),
          legs.elementAt(i),
          legs.tryElementAt(i + 1),
        )
    ];
  }
}

class LinkEndpoint {
  late final String gid;
  late final String name;
  late final LocationType locationType;
  late final LatLng position;
  late final DateTime plannedTime;
  late final DateTime? estimatedTime;
  late final List<Note> notes;

  LinkEndpoint.fromJson(Json json) {
    gid = json['gid'];
    name = json['name'];
    locationType = LocationType.values.asNameMap()[json['locationType']]!;
    position = LatLng(json['latitude'], json['longitude']);
    plannedTime = DateTime.parse(json['plannedTime']).toLocal();
    estimatedTime = parseDateTime(json['estimatedTime']);
    notes = List.from(json['notes']).map((e) => Note.fromJson(e)).toList(growable: false);
  }
}

class LegCall {
  late final StopPoint stopPoint;
  late Iterable<Note> notes;

  bool isCancelled = false;

  LegCall.fromJson(Json json) {
    stopPoint = StopPoint.fromJson(json['stopPoint']);
    notes = List.from(json['notes']).map((e) => Note.fromJson(e)).toList(growable: false);
  }
}

class Note implements TS {
  late final String type;
  late final Severity severity;
  late final String text;

  bool get booking => type == 'booking';

  Note(this.text, [this.severity = Severity.low]) {
    type = '';
  }

  Note.fromJson(Json json) {
    type = json['type'];
    severity = Severity.values.asNameMap()[json['severity']]!;
    text = removeToGoMentions(json['text'])!;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Note &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          severity == other.severity &&
          text == other.text;

  @override
  int get hashCode => type.hashCode ^ severity.hashCode ^ text.hashCode;

  @override
  Widget display(BuildContext context, {bool boldTitle = false, bool showAffectedStop = false}) {
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Row(
        children: [
          booking ? const Icon(Icons.phone) : getNoteIcon(severity),
          const SizedBox(width: 20),
          Expanded(
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(text, style: TextStyle(color: Theme.of(context).hintColor)))),
        ],
      ),
    );
  }
}

class Segment {
  late final String? name;
  late final String maneuver;
  late final String orientation;
  late final String maneuverDescription;
  late final int? distanceInMeters;

  Segment.fromJson(Json json) {
    name = json['name'];
    maneuver = json['maneuver'];
    orientation = json['orientation'];
    maneuverDescription = json['maneuverDescription'];
    distanceInMeters = json['distanceInMeters'];
  }
}

sealed class Leg {}

sealed class JourneyLeg extends Leg {
  late Iterable<Note> notes;
  late final int? distanceInMeters;
  late final DateTime plannedDepartureTime;
  late final DateTime plannedArrivalTime;
  late final int plannedDurationInMinutes;
  late DateTime? estimatedDepartureTime;
  late DateTime? estimatedArrivalTime;
  late final int? estimatedDurationInMinutes;

  DepartureStateMixin depState = StopDepartureState();
  DepartureStateMixin arrState = StopDepartureState();

  DateTime get departureTime => estimatedDepartureTime ?? plannedDepartureTime;

  DateTime get arrivalTime => estimatedArrivalTime ?? plannedArrivalTime;

  Duration get duration => arrivalTime.difference(departureTime);

  int? get departureDelay => getDelay(plannedDepartureTime, estimatedDepartureTime);

  int? get arrivalDelay => getDelay(plannedArrivalTime, estimatedArrivalTime);

  LegCall? get originCall => switch (this) {
        TripLeg leg => leg.origin,
        ConnectionLink link => link.origin,
        ArrivalAccessLink link => link.origin,
        _ => null,
      };

  LegCall? get destinationCall => switch (this) {
        TripLeg leg => leg.destination,
        ConnectionLink link => link.destination,
        DepartureAccessLink link => link.destination,
        _ => null,
      };

  LinkEndpoint? get originEndpoint => switch (this) {
        DepartureAccessLink link => link.origin,
        DestinationLink link => link.origin,
        _ => null,
      };

  LinkEndpoint? get destinationEndpoint => switch (this) {
        ArrivalAccessLink link => link.destination,
        DestinationLink link => link.destination,
        _ => null,
      };

  String get originName => originCall?.stopPoint.name ?? originEndpoint!.name;

  String get destinationName => destinationCall?.stopPoint.name ?? destinationEndpoint!.name;

  JourneyLeg.fromJson(Json json) {
    notes = List.from(json['notes'])
        .map((e) => Note.fromJson(e))
        .where((n) => n.text != 'Risk att missa bytet.' && !n.text.contains(': Inställd'))
        .toList(growable: false);
    distanceInMeters = json['distanceInMeters'] ?? json['estimatedDistanceInMeters'];
    plannedDepartureTime = DateTime.parse(json['plannedDepartureTime']).toLocal();
    plannedArrivalTime = DateTime.parse(json['plannedArrivalTime']).toLocal();
    plannedDurationInMinutes = json['plannedDurationInMinutes'];
    estimatedDepartureTime = parseDateTime(json['estimatedDepartureTime']);
    estimatedArrivalTime = parseDateTime(json['estimatedArrivalTime']);
    estimatedDurationInMinutes = json['estimatedDurationInMinutes'];
  }
}

mixin JourneyLegOrder implements Comparable<JourneyLegOrder> {
  late final int journeyLegIndex;

  @override
  int compareTo(JourneyLegOrder other) => journeyLegIndex.compareTo(other.journeyLegIndex);
}

class TripLeg extends JourneyLeg with JourneyLegOrder {
  late LegCall origin;
  late LegCall destination;
  late bool isCancelled;
  late bool isPartCancelled;
  late ServiceJourney serviceJourney;
  late int? plannedConnectingTimeInMinutes;
  late int? estimatedConnectingTimeInMinutes;
  late bool isRiskOfMissingConnection;
  late Occupancy? occupancy;

  late bool riskOfMissingConnectionNote;

  bool get isDepartureCancelled =>
      origin.isCancelled ||
      isCancelled ||
      (isPartCancelled && origin.stopPoint.platform == null && estimatedDepartureTime == null);

  bool get isArrivalCancelled =>
      destination.isCancelled ||
      isCancelled ||
      (isPartCancelled && destination.stopPoint.platform == null && estimatedArrivalTime == null);

  TripLeg.fromJson(Json json) : super.fromJson(json) {
    origin = LegCall.fromJson(json['origin']);
    destination = LegCall.fromJson(json['destination']);
    isCancelled = json['isCancelled'];
    isPartCancelled = json['isPartCancelled'];
    serviceJourney = ServiceJourney.fromJson(json['serviceJourney']);
    plannedConnectingTimeInMinutes = json['plannedConnectingTimeInMinutes'];
    estimatedConnectingTimeInMinutes = json['estimatedConnectingTimeInMinutes'];
    isRiskOfMissingConnection = json['isRiskOfMissingConnection'] == true;
    if (json.containsKey('occupancy')) occupancy = Occupancy.fromJson(json['occupancy']);
    journeyLegIndex = json['journeyLegIndex'];
    riskOfMissingConnectionNote = json['notes'].any((note) => note['text'] == 'Risk att missa bytet.');
  }
}

abstract class Link extends JourneyLeg {
  late final TransportMode transportMode;
  late final TransportSubMode transportSubMode;
  late final int? estimatedNumberOfSteps;
  late final List<LatLng> linkCoordinates;

  Link.fromJson(Json json) : super.fromJson(json) {
    transportMode = TransportMode.values.asNameMap()[json['transportMode']]!;
    transportSubMode = TransportSubMode.values.asNameMap()[json['transportSubMode']]!;
    estimatedNumberOfSteps = json['estimatedNumberOfSteps'];
    linkCoordinates = List.from(json['linkCoordinates'])
        .map((coord) => LatLng(coord['latitude'], coord['longitude']))
        .toList(growable: false);
  }
}

class ConnectionLink extends Link with JourneyLegOrder {
  late final LegCall origin;
  late final LegCall destination;
  late final List<Segment>? segments;

  ConnectionLink.fromJson(Json json) : super.fromJson(json) {
    origin = LegCall.fromJson(json['origin']);
    destination = LegCall.fromJson(json['destination']);
    if (json.containsKey('segments')) {
      segments = List.from(json['segments']).map((e) => Segment.fromJson(e)).toList(growable: false);
    }
    journeyLegIndex = json['journeyLegIndex'];
  }
}

class ArrivalAccessLink extends Link {
  late final LegCall origin;
  late final LinkEndpoint destination;
  late final List<Segment>? segments;

  ArrivalAccessLink.fromJson(Json json) : super.fromJson(json) {
    origin = LegCall.fromJson(json['origin']);
    destination = LinkEndpoint.fromJson(json['destination']);
    if (json.containsKey('segments')) {
      segments = List.from(json['segments']).map((e) => Segment.fromJson(e)).toList(growable: false);
    }
  }
}

class DepartureAccessLink extends Link {
  late final LinkEndpoint origin;
  late final LegCall destination;
  late final List<Segment>? segments;

  DepartureAccessLink.fromJson(Json json) : super.fromJson(json) {
    origin = LinkEndpoint.fromJson(json['origin']);
    destination = LegCall.fromJson(json['destination']);
    if (json.containsKey('segments')) {
      segments = List.from(json['segments']).map((e) => Segment.fromJson(e)).toList(growable: false);
    }
  }
}

class DestinationLink extends Link {
  late final LinkEndpoint origin;
  late final LinkEndpoint destination;
  late final List<Segment>? segments;

  DestinationLink.fromJson(Json json) : super.fromJson(json) {
    origin = LinkEndpoint.fromJson(json['origin']);
    destination = LinkEndpoint.fromJson(json['destination']);
    if (json.containsKey('segments')) {
      segments = List.from(json['segments']).map((e) => Segment.fromJson(e)).toList(growable: false);
    }
  }
}

class Links {
  String? previous;
  String? next;
  late String current;

  Links.fromJson(Json json) {
    previous = json['previous'];
    next = json['next'];
    current = json['current'];
  }
}

class JourneyDetails {
  DepartureAccessLink? departureAccessLink;
  List<TripLegDetails> tripLegs = [];
  List<ConnectionLink> connectionLinks = [];
  ArrivalAccessLink? arrivalAccessLink;
  DestinationLink? destinationLink;
  TicketSuggestionsResult? ticketSuggestionsResult;
  late List<TariffZone> tariffZones;
  Occupancy? occupancy;

  Iterable<Leg> get allJourneyLegs => [
        destinationLink,
        departureAccessLink,
        ...[...tripLegs, ...connectionLinks]..sort(),
        arrivalAccessLink
      ].whereType<Leg>();

  JourneyDetails.fromJson(Json json) {
    if (json.containsKey('departureAccessLink')) {
      departureAccessLink = DepartureAccessLink.fromJson(json['departureAccessLink']);
    }
    if (json.containsKey('tripLegs')) {
      tripLegs = List.from(json['tripLegs']).map((e) => TripLegDetails.fromJson(e)).toList(growable: false);
    }
    if (json.containsKey('connectionLinks')) {
      connectionLinks =
          List.from(json['connectionLinks']).map((e) => ConnectionLink.fromJson(e)).toList(growable: false);
    }
    if (json.containsKey('arrivalAccessLink')) {
      arrivalAccessLink = ArrivalAccessLink.fromJson(json['arrivalAccessLink']);
    }
    if (json.containsKey('destinationLink')) destinationLink = DestinationLink.fromJson(json['destinationLink']);
    if (json.containsKey('ticketSuggestionsResult')) {
      ticketSuggestionsResult = TicketSuggestionsResult.fromJson(json['ticketSuggestionsResult']);
    }
    tariffZones = List.from(json['tariffZones']).map((e) => TariffZone.fromJson(e)).toList(growable: false);
    if (json.containsKey('occupancy')) occupancy = Occupancy.fromJson(json['occupancy']);
  }
}

class TripLegDetails extends Leg with JourneyLegOrder {
  late final List<ServiceJourney> serviceJourneys;
  late final List<Call> callsOnTripLeg;
  List<LatLng>? tripLegCoordinates;
  late final List<TariffZone> tariffZones;
  late final bool isCancelled;
  late final bool isPartCancelled;
  Occupancy? occupancy;

  Call get origin => callsOnTripLeg.first;

  Call get destination => callsOnTripLeg.last;

  TripLegDetails.fromJson(Json json) {
    serviceJourneys = List.from(json['serviceJourneys']).map((e) => ServiceJourney.fromJson(e)).toList();
    ServiceJourneyDetails.cleanUpServiceJourneys(serviceJourneys);
    callsOnTripLeg = List.from(json['callsOnTripLeg']).map((e) => Call.fromJson(e)).toList(growable: false);
    if (json.containsKey('tripLegCoordinates')) {
      tripLegCoordinates = List.from(json['tripLegCoordinates'])
          .map((coord) => LatLng(coord['latitude'], coord['longitude']))
          .toList(growable: false);
    }
    tariffZones = List.from(json['tariffZones']).map((e) => TariffZone.fromJson(e)).toList(growable: false);
    isCancelled = json['isCancelled'];
    isPartCancelled = json['isPartCancelled'];
    if (json.containsKey('occupancy')) occupancy = Occupancy.fromJson(json['occupancy']);
    journeyLegIndex = json['journeyLegIndex'];
  }
}

class TicketSuggestionsResult {
  late final bool hasError;
  late final List<TicketSuggestions> ticketSuggestions;

  TicketSuggestionsResult.fromJson(Json json) {
    hasError = json['hasError'];
    ticketSuggestions =
        List.from(json['ticketSuggestions']).map((e) => TicketSuggestions.fromJson(e)).toList(growable: false);
  }
}

class TicketSuggestions {
  late final int productId;
  late final String productName;
  late final int productType;
  late final String travellerCategory;
  late final int priceInSek;
  late final TimeValidity timeValidity;
  late final String timeLimitation;
  late final List<SaleChannel> saleChannels;
  late final List<ValidZone> validZones;
  late final String productInstanceType;
  PunchConfiguration? punchConfiguration;
  late final String offerSpecification;

  TicketSuggestions.fromJson(Json json) {
    productId = json['productId'];
    productName = json['productName'];
    productType = json['productType'];
    travellerCategory = json['travellerCategory'];
    priceInSek = json['priceInSek'];
    timeValidity = TimeValidity.fromJson(json['timeValidity']);
    timeLimitation = json['timeLimitation'];
    saleChannels = List.from(json['saleChannels']).map((e) => SaleChannel.fromJson(e)).toList(growable: false);
    validZones = List.from(json['validZones']).map((e) => ValidZone.fromJson(e)).toList(growable: false);
    productInstanceType = json['productInstanceType'];
    if (json.containsKey('punchConfiguration')) {
      punchConfiguration = PunchConfiguration.fromJson(json['punchConfiguration']);
    }
    offerSpecification = json['offerSpecification'];
  }
}

class TimeValidity {
  late final String type;
  late final int? amount;
  late final String unit;
  late final String? fromDate;
  late final String? toDate;
  late final String? fromDateTime;
  late final String? toDateTime;

  TimeValidity.fromJson(Json json) {
    type = json['type'];
    amount = json['amount'];
    unit = json['unit'];
    fromDate = json['fromDate'];
    toDate = json['toDate'];
    fromDateTime = json['fromDateTime'];
    toDateTime = json['toDateTime'];
  }
}

class SaleChannel {
  late final int id;
  late final String? ticketName;

  SaleChannel.fromJson(Json json) {
    id = json['id'];
    ticketName = json['ticketName'];
  }
}

class ValidZone {
  late final int id;

  ValidZone.fromJson(Json json) {
    id = json['id'];
  }
}

class PunchConfiguration {
  late final int quota;
  late final Duration duration;

  PunchConfiguration.fromJson(Json json) {
    quota = json['quota'];
    duration = Duration(hours: (json['duration']['amount']));
  }
}

class LocationInfo {
  late final String? gid;
  late final String name;
  late final LocationType locationType;
  late final LatLng position;
  late final String? platform;
  late final int? straightLineDistanceInMeters;
  late final bool? hasLocalService;

  LocationInfo.fromJson(Json json) {
    gid = json['gid'];
    name = json['name'];
    locationType = LocationType.values.asNameMap()[json['locationType']]!;
    position = LatLng(json['latitude'], json['longitude']);
    platform = json['platform'];
    straightLineDistanceInMeters = json['straightLineDistanceInMeters'];
    hasLocalService = json['hasLocalService'];
  }

  Location toLocation() {
    switch (locationType) {
      case LocationType.stoparea:
      case LocationType.stoppoint:
      case LocationType.metastation:
        return StopLocation.fromLocationInfo(this);
      case LocationType.address:
      case LocationType.pointofinterest:
      case LocationType.unknown:
        return CoordLocation.fromLocationInfo(this);
    }
  }
}

class ValidTimeInterval {
  late DateTime validFrom;
  late DateTime validUntil;

  ValidTimeInterval.fromJson(Json json) {
    validFrom = DateTime.parse(json['validFrom']).toLocal();
    validUntil = DateTime.parse(json['validUntil']).toLocal();
  }
}

enum DepartureState { normal, departed, atStation, unknownTime, replacementBus, replacementTaxi }

mixin DepartureStateMixin {
  DepartureState state = DepartureState.normal;
}

class StopDepartureState with DepartureStateMixin {}

abstract class Location {
  @HiveField(0)
  late double _lon;
  @HiveField(1)
  late double _lat;
  @HiveField(2)
  late String name;

  LatLng get position => LatLng(_lat, _lon);

  Location(this.name, this._lat, this._lon);

  Location.fromLocationInfo(LocationInfo locationInfo) {
    _lon = locationInfo.position.longitude;
    _lat = locationInfo.position.latitude;
    name = locationInfo.name;
  }

  Location.fromStopPoint(StopPoint stopPoint) {
    _lon = stopPoint.position.longitude;
    _lat = stopPoint.position.latitude;
    name = stopPoint.name;
  }

  Location.fromParams(Map<String, String> params, String? prefix) {
    name = params[addPrefix('name', prefix)]!;
    _lat = double.parse(params[addPrefix('lat', prefix)]!);
    _lon = double.parse(params[addPrefix('lon', prefix)]!);
  }

  String getName() => name;

  @override
  bool operator ==(Object other) => (other is Location) && name == other.name;

  @override
  int get hashCode => name.hashCode;
}

@HiveType(typeId: 0)
class StopLocation extends Location {
  @HiveField(3)
  late int _gid;

  String get gid => _gid.toString().padLeft(16, '0');

  StopLocation(super.name, super._lat, super._lon, this._gid);

  StopLocation.fromLocationInfo(LocationInfo locationInfo) : super.fromLocationInfo(locationInfo) {
    _gid = int.parse(locationInfo.gid!);
    if (locationInfo.locationType == LocationType.metastation) {
      name = name.toLowerCase().capitalize();
    }
  }

  StopLocation.fromStopPoint(StopPoint stopPoint) : super.fromStopPoint(stopPoint) {
    _gid = int.parse(stopAreaFromStopPoint(stopPoint.gid));
  }

  StopLocation.fromParams(Map<String, String> params, String? prefix) : super.fromParams(params, prefix) {
    _gid = int.parse(params[addPrefix('id', prefix)]!);
  }

  bool get isStopArea => _gid >= 900000000 && _gid < 9022000000000000;

  bool get isStopPoint => _gid >= 9022000000000000;

  void toStopArea() {
    _gid = int.parse(stopAreaFromStopPoint(gid));
  }

  @override
  bool operator ==(Object other) => (other is StopLocation) && _gid == other._gid;

  @override
  int get hashCode => _gid.hashCode;
}

@HiveType(typeId: 1)
class CoordLocation extends Location {
  @HiveField(3)
  late String _type;

  LocationType get type => _type == 'POI' ? LocationType.pointofinterest : LocationType.address;

  String get typeString => _type;

  set _locationType(LocationType locationType) => _type = locationType == LocationType.pointofinterest ? 'POI' : 'ADR';

  CoordLocation(super.name, super._lat, super._lon, this._type);

  CoordLocation.fromLocationInfo(LocationInfo locationInfo) : super.fromLocationInfo(locationInfo) {
    _locationType = locationInfo.locationType;
  }

  CoordLocation.fromParams(Map<String, String> params, String? prefix) : super.fromParams(params, prefix) {
    _type = params[addPrefix('type', prefix)]!;
  }
}

@HiveType(typeId: 3)
class CurrentLocation extends Location {
  Location? _location;
  DateTime? lastUpdated;
  bool tried = false;
  VoidCallback? onNameChange;

  CurrentLocation({String? name}) : super(name ?? 'Nuvarande position', 0, 0);

  @override
  String getName() {
    var location = tried ? _location : null;
    return '${super.name}, ${location?.name.firstPart() ?? (tried && location == null ? 'okänd' : 'söker...')}';
  }

  Future<Location?> location({bool forceRefresh = false, bool onlyStops = false}) async {
    if (!forceRefresh &&
        _location != null &&
        tried &&
        (lastUpdated?.isBefore(DateTime.now().add(const Duration(minutes: 1))) ?? false) &&
        (!onlyStops || _location is StopLocation)) {
      return _location;
    }

    try {
      var pos = await getPosition();

      _lat = pos.latitude;
      _lon = pos.longitude;
      _location = await getLocationFromCoord(LatLng(pos.latitude, pos.longitude),
          stopMaxDist: onlyStops ? 3000 : 100, onlyStops: onlyStops);
    } catch (e) {
      _location = null;
      return Future.error(e);
    } finally {
      lastUpdated = DateTime.now();
      tried = true;
      onNameChange?.call();
    }

    return _location;
  }

  Location? get cachedLocation => _location;
}

class PlaneraResaError extends DefaultError {
  late int errorCode;

  PlaneraResaError.fromJson(Json json) : super() {
    errorCode = json['errorCode'];
    String? errorMessage = json['errorMessage'];

    if (kDebugMode) {
      print(errorCode);
      print(errorMessage);
    }

    switch (errorCode) {
      case 1001: // Ticket suggestion argument failed
      case 2001: // Limit must be greater than zero
      case 2004: // Decoding pagination reference failed
      case 2005: // Invalid transport mode to origin
      case 2006: // Transport sub modes without transport modes
      case 2011: // Invalid origin walk
      case 2012: // Invalid destination walk
      case 2013: // Invalid origin bike
      case 2014: // Invalid destination bike
      case 2015: // Invalid origin car
      case 2016: // Invalid destination car
      case 2017: // Invalid origin park
      case 2018: // Invalid destination park
      case 2019: // Invalid total bike
      case 3001: // Missing query parameter
      case 3002: // Invalid limit and offset values
      case 3003: // Query parameter exceeds maximum length
      case 4001: // Invalid limit and offset values
      case 4002: // Missing coordinates
      case 4003: // Invalid radius
      case 4101: // Invalid limit and offset values
      case 4104: // Invalid timespan
      case 4105: // Invalid max departures per line and direction
      case 4106: // Platforms exceeds maximum length
      case 5001: // Bad service request
      case 6003: // Faulty input
        message = 'Ogiltig förfrågan';
        break;
      case 1002: // Missing details reference
      case 1003: // Missing reconstruction reference
      case 1004: // Corrupt details reference
        message = 'Ogiltig referens';
        break;
      case 2002: // Invalid location
        message = 'Ogiltig plats';
        break;
      case 2003: // Invalid datetime
      case 4103: // Invalid start datetime
        message = 'Ogiltigt datum';
        break;
      case 2007: // Invalid origin gid
        message = 'Ogiltig startplats';
        break;
      case 2008: // Invalid destination gid
        message = 'Ogiltig destination';
        break;
      case 2009: // Invalid via gid
        message = 'Ogiltig via-hållplats';
        break;
      case 2010: // Invalid interchange duration
        message = 'Ogiltig bytesmarginal';
        break;
      case 2020: // Identical origin and destination
      case 6001: // Same origin and destination
        message = 'Startplatsen och destinationen är identiska';
        break;
      case 2021: // Origin name exceeds maximum length
        message = 'Startplatsens namn är för långt';
        break;
      case 2022: // Destination name exceeds maximum length
        message = 'Destinationens namn är för långt';
        break;
      case 5003: // Service error
        message = 'Serverfel';
        break;
      case 6002: // Error in date field
      case 6004: // Unknown arrival station
        message = 'Okänd startplats';
        break;
      case 6005: // Unknown intermediate station
        message = 'Okänd via-hållplats';
        break;
      case 6006: // Unknown departure station
        message = 'Okänd destination';
        break;
      case 6007: // Unsuccessful search
      case 6009: // Incomplete search
        message = 'Sökningen kunde inte genomföras';
        break;
      case 6008: // Nearby not found
        message = 'Kunde inte hitta en hållplats tillräckligt nära den angivna adressen';
        break;
      case 6010: // Origin/Destination are too near
        message = 'Startplatsen och destinationen ligger för nära varandra';
        break;
      case 4102: // Invalid stop area gid
        message = 'Ogiltig hållplats';
        break;
      case 4108: // Invalid direction gid
        message = 'Ogiltig riktningshållplats';
        break;
      default:
        message = errorMessage ?? 'Okänt fel';
    }
  }
}
