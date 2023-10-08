import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/mapbox_gl.dart';

import '../utils.dart';
import 'planera_resa.dart';
import 'vehicle_positions.dart';

class Trafikverket {
  static final Dio _dio = Dio(BaseOptions(
      baseUrl: 'https://api.trafikinfo.trafikverket.se',
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 10)));

  static Future<T?> _callApi<T>(String query, T Function(Response) generator) async {
    try {
      var result = await _dio.post('/v2/data.json',
          data: '''
<REQUEST>
    <LOGIN authenticationkey="${const String.fromEnvironment('TRAFIKVERKET_KEY')}" />
    $query
</REQUEST>
''',
          options: Options(contentType: 'text/xml'));
      return generator(result);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        print(error);
        print(stackTrace);
      }
      return null;
    }
  }

  static Future<Iterable<TrainAnnouncement>?> getTrainJourney(int trainNumber, DateTime start, DateTime end) async {
    return await _callApi('''
<QUERY objecttype="TrainAnnouncement" schemaversion="1.8" orderby="AdvertisedTimeAtLocation, ActivityType">
    <FILTER>
        <AND>
            <EQ name="AdvertisedTrainIdent" value="$trainNumber" />
            <EQ name="Advertised" value="true" />
            <GTE name="AdvertisedTimeAtLocation" value="${start.toIso8601String()}" />
            <LTE name="AdvertisedTimeAtLocation" value="${end.toIso8601String()}" />
        </AND>
    </FILTER>
    <INCLUDE>ActivityType</INCLUDE>
    <INCLUDE>LocationSignature</INCLUDE>
    <INCLUDE>AdvertisedTimeAtLocation</INCLUDE>
    <INCLUDE>EstimatedTimeAtLocation</INCLUDE>
    <INCLUDE>TrackAtLocation</INCLUDE>
    <INCLUDE>Canceled</INCLUDE>
    <INCLUDE>Booking.Description</INCLUDE>
    <INCLUDE>Deviation.Description</INCLUDE>
    <INCLUDE>OtherInformation.Description</INCLUDE>
    <INCLUDE>Service.Description</INCLUDE>
    <INCLUDE>TrainComposition.Description</INCLUDE>
    <INCLUDE>TimeAtLocation</INCLUDE>
    <INCLUDE>PlannedEstimatedTimeAtLocation</INCLUDE>
</QUERY>
''', (result) {
      return result.data['RESPONSE']['RESULT'].first['TrainAnnouncement']
          .map<TrainAnnouncement>((t) => TrainAnnouncement(t));
    });
  }

  static Future<Iterable<TrainAnnouncement>?> getTrainTrips(Set<TrainLegRef> trips) async {
    return await _callApi('''
<QUERY objecttype="TrainAnnouncement" schemaversion="1.8" orderby="AdvertisedTimeAtLocation">
    <FILTER>
        <AND>
            <EQ name="Advertised" value="true" />
            <OR>
                <AND>
                    <EQ name="ActivityType" value="Avgang" />
                    <OR>
                        ${trips.map((d) => '''
                        <AND>
                            <EQ name="AdvertisedTrainIdent" value="${d.trainNumber}" />
                            <EQ name="AdvertisedTimeAtLocation" value="${d.departureTime.toIso8601String()}" />
                        </AND>
                        ''').join()}
                    </OR>
                </AND>
                <AND>
                    <EQ name="ActivityType" value="Ankomst" />
                    <OR>
                        ${trips.map((d) => '''
                        <AND>
                            <EQ name="AdvertisedTrainIdent" value="${d.trainNumber}" />
                            <EQ name="AdvertisedTimeAtLocation" value="${d.arrivalTime.toIso8601String()}" />
                        </AND>
                        ''').join()}
                  </OR>
                </AND>
            </OR>
        </AND>
    </FILTER>
    <INCLUDE>ActivityType</INCLUDE>
    <INCLUDE>LocationSignature</INCLUDE>
    <INCLUDE>AdvertisedTimeAtLocation</INCLUDE>
    <INCLUDE>AdvertisedTrainIdent</INCLUDE>
    <INCLUDE>EstimatedTimeAtLocation</INCLUDE>
    <INCLUDE>TrackAtLocation</INCLUDE>
    <INCLUDE>Canceled</INCLUDE>
    <INCLUDE>Booking.Description</INCLUDE>
    <INCLUDE>Deviation.Description</INCLUDE>
    <INCLUDE>OtherInformation.Description</INCLUDE>
    <INCLUDE>Service.Description</INCLUDE>
    <INCLUDE>TrainComposition.Description</INCLUDE>
    <INCLUDE>TimeAtLocation</INCLUDE>
    <INCLUDE>PlannedEstimatedTimeAtLocation</INCLUDE>
</QUERY>
''', (result) {
      return result.data['RESPONSE']['RESULT'].expand<TrainAnnouncement>((r) =>
          r['TrainAnnouncement'].map<TrainAnnouncement>((t) => TrainAnnouncement(t)) as Iterable<TrainAnnouncement>);
    });
  }

  static Future<Iterable<TrainAnnouncement>?> getTrainStationBoard(Iterable<Departure> departureBoard,
      {bool arrival = false}) async {
    var filteredBoard = departureBoard.where((d) => d.arrival == arrival && d.isTrain);
    if (filteredBoard.isEmpty) return [];
    return await _callApi('''
<QUERY objecttype="TrainAnnouncement" schemaversion="1.8">
    <FILTER>
        <AND>
            <EQ name="ActivityType" value="${arrival ? 'Ankomst' : 'Avgang'}" />
            <EQ name="Advertised" value="true" />
            <OR>
                ${filteredBoard.map((d) => '''
                <AND>
                    <EQ name="AdvertisedTrainIdent" value="${d.trainNumber}" />
                    <EQ name="AdvertisedTimeAtLocation" value="${d.plannedTime.toIso8601String()}" />
                </AND>
                ''').join()}
            </OR>
        </AND>
    </FILTER>
    <INCLUDE>ActivityType</INCLUDE>
    <INCLUDE>LocationSignature</INCLUDE>
    <INCLUDE>AdvertisedTrainIdent</INCLUDE>
    <INCLUDE>AdvertisedTimeAtLocation</INCLUDE>
    <INCLUDE>EstimatedTimeAtLocation</INCLUDE>
    <INCLUDE>TrackAtLocation</INCLUDE>
    <INCLUDE>Canceled</INCLUDE>
    <INCLUDE>Deviation.Description</INCLUDE>
    <INCLUDE>PlannedEstimatedTimeAtLocation</INCLUDE>
    <INCLUDE>TimeAtLocation</INCLUDE>
</QUERY>
''', (result) {
      return result.data['RESPONSE']['RESULT'].first['TrainAnnouncement']
          .map<TrainAnnouncement>((t) => TrainAnnouncement(t));
    });
  }

  static Future<String?> getTrainStationFromLocation(LatLng position) async {
    return await _callApi('''
<QUERY objecttype="TrainStation" schemaversion="1.4">
    <FILTER>
        <WITHIN name="Geometry.WGS84" shape="center" value="${position.longitude} ${position.latitude}" radius="500m" />
        <EQ name="Advertised" value="true" />
    </FILTER>
    <INCLUDE>LocationSignature</INCLUDE>
</QUERY>
''', (result) {
      return result.data['RESPONSE']['RESULT'].first['TrainStation'].first['LocationSignature'];
    });
  }

  static Future<Iterable<TrainMessage>?> getTrainStationMessage(
      String locationSignature, DateTime start, DateTime end, String? direction) async {
    return await _callApi('''
<QUERY objecttype="TrainMessage" schemaversion="1.7" orderby="LastUpdateDateTime desc">
    <FILTER>
        <AND>
            <OR>
                <EQ name="TrafficImpact.AffectedLocation.LocationSignature" value="$locationSignature" />
                <EQ name='TrafficImpact.FromLocation' value='$locationSignature'/>
                <EQ name='TrafficImpact.ToLocation' value='$locationSignature'/>
			      </OR>
            <EQ name="TrafficImpact.AffectedLocation.ShouldBeTrafficInformed" value="true" />
            <LTE name="StartDateTime" value="${end.toIso8601String()}" />
            <GTE name="PrognosticatedEndDateTimeTrafficImpact" value="${start.toIso8601String()}" />
            ${direction != null ? '<EQ name="TrafficImpact.AffectedLocation.LocationSignature" value="$direction" />' : ''}
        </AND>
    </FILTER>
    <INCLUDE>Header</INCLUDE>
    <INCLUDE>ExternalDescription</INCLUDE>
</QUERY>
''', (result) {
      return result.data['RESPONSE']['RESULT'].first['TrainMessage'].map<TrainMessage>((t) => TrainMessage(t));
    });
  }

  static Future<Iterable<TrainMessage>?> getTrainMessage(
      Iterable<String> locationSignatures, DateTime start, DateTime end) async {
    return await _callApi('''
<QUERY objecttype="TrainMessage" schemaversion="1.7" orderby="LastUpdateDateTime desc">
    <FILTER>
        <AND>
            ${locationSignatures.map((l) => '''<IN name="TrafficImpact.AffectedLocation.LocationSignature" value="$l" />
            ''').join()}
            <LTE name="StartDateTime" value="${end.toIso8601String()}" />
            <GTE name="PrognosticatedEndDateTimeTrafficImpact" value="${start.toIso8601String()}" />
        </AND>
    </FILTER>
    <INCLUDE>Header</INCLUDE>
    <INCLUDE>ExternalDescription</INCLUDE>
</QUERY>
''', (result) {
      return result.data['RESPONSE']['RESULT'].first['TrainMessage'].map<TrainMessage>((t) => TrainMessage(t));
    });
  }

  static Future<Iterable<TrainAnnouncement>?> getLateTrains(String locationSignature, DateTime? dateTime) async {
    bool now = dateTime == null;
    dateTime ??= DateTime.now();
    return await _callApi('''
<QUERY objecttype="TrainAnnouncement" schemaversion="1.8" orderby="AdvertisedTimeAtLocation">
    <FILTER>
        <AND>
        <EQ name="LocationSignature" value="$locationSignature" />
            <AND>
                <LT name="AdvertisedTimeAtLocation" value="${dateTime.toIso8601String()}" />
                <EQ name='Advertised' value='true'/>
                <OR>
                    <GTE name="EstimatedTimeAtLocation" value="${dateTime.toIso8601String()}" />
                    ${!now ? '' : '''
                    <AND>
                        <EXISTS name="TimeAtLocation" value="false" />
                        <OR>
                            <GTE name="AdvertisedTimeAtLocation" value="${dateTime.subtract(const Duration(hours: 1))}" />
                            <GTE name="EstimatedTimeAtLocation" value="${dateTime.subtract(const Duration(hours: 1))}" />
                            <AND>
                                <GTE name="AdvertisedTimeAtLocation" value="${dateTime.subtract(const Duration(hours: 12))}" />
                                <IN name="Deviation.Code" value="ANA088" />
                            </AND>
                        </OR>
                        <EQ name="Canceled" value="false" />
                    </AND>
                    '''}
                </OR>
            </AND>
        </AND>
    </FILTER>
    <INCLUDE>ActivityType</INCLUDE>
    <INCLUDE>AdvertisedTrainIdent</INCLUDE>
    <INCLUDE>AdvertisedTimeAtLocation</INCLUDE>
    <INCLUDE>EstimatedTimeAtLocation</INCLUDE>
    <INCLUDE>TrackAtLocation</INCLUDE>
    <INCLUDE>Canceled</INCLUDE>
    <INCLUDE>Deviation.Description</INCLUDE>
    <INCLUDE>PlannedEstimatedTimeAtLocation</INCLUDE>
    <INCLUDE>TimeAtLocation</INCLUDE>
    <INCLUDE>LocationSignature</INCLUDE>
</QUERY>
''', (result) {
      return result.data['RESPONSE']['RESULT'].first['TrainAnnouncement']
          .map<TrainAnnouncement>((t) => TrainAnnouncement(t));
    });
  }

  static Future<TrainPositions?> getTrainPositions(Iterable<TrainPositionRef> trains) async {
    return await _callApi('''
<QUERY sseurl="true" namespace="järnväg.trafikinfo" objecttype="TrainPosition" schemaversion="1.0" orderby="Status.Active">
    <FILTER>
        <OR>
            ${trains.map((train) => '<EQ name="Train.AdvertisedTrainNumber" value="${train.trainNumber}" />').join()}
        </OR>
        <GTE name="TimeStamp" value="${DateTime.now().subtract(const Duration(hours: 12))}" />
    </FILTER>
    <INCLUDE>Position.WGS84</INCLUDE>
    <INCLUDE>TimeStamp</INCLUDE>
    <INCLUDE>Status.Active</INCLUDE>
    <INCLUDE>Speed</INCLUDE>
    <INCLUDE>Train.AdvertisedTrainNumber</INCLUDE>
</QUERY>
''', (response) {
      var result = response.data['RESPONSE']['RESULT'][0];
      var trainPositions = result['TrainPosition'].map<TrainPosition>((t) => TrainPosition(t, trains));
      var sseUrl = result['INFO']['SSEURL'];
      return TrainPositions(trainPositions, sseUrl, trains);
    });
  }
}

class TrainAnnouncement {
  late String activityType;
  late DateTime advertisedTimeAtLocation;
  late DateTime? estimatedTimeAtLocation;
  late String? trackAtLocation;
  late bool canceled;
  late Iterable<String> booking;
  late Iterable<String> deviation;
  late Iterable<String> otherInformation;
  late Iterable<String> service;
  late Iterable<String> trainComposition;
  late DateTime? timeAtLocation;
  late DateTime? plannedEstimatedTimeAtLocation;
  late int advertisedTrainIdent;
  late String locationSignature;

  TrainAnnouncement(dynamic data) {
    activityType = data['ActivityType'] ?? '';
    advertisedTimeAtLocation = DateTime.parse(data['AdvertisedTimeAtLocation']).toLocal();
    estimatedTimeAtLocation = DateTime.tryParse(data['EstimatedTimeAtLocation'] ?? '')?.toLocal();
    trackAtLocation = data['TrackAtLocation'];
    canceled = data['Canceled'];
    booking = data['Booking']?.map((d) => d['Description']).cast<String>() ?? [];
    deviation = data['Deviation']?.map((d) => d['Description']).cast<String>() ?? [];
    otherInformation = data['OtherInformation']?.map((d) => d['Description']).cast<String>() ?? [];
    service = data['Service']?.map((d) => d['Description']).cast<String>() ?? [];
    trainComposition = data['TrainComposition']?.map((d) => d['Description']).cast<String>() ?? [];
    timeAtLocation = DateTime.tryParse(data['TimeAtLocation'] ?? '')?.toLocal();
    plannedEstimatedTimeAtLocation = DateTime.tryParse(data['PlannedEstimatedTimeAtLocation'] ?? '')?.toLocal();
    advertisedTrainIdent = int.tryParse(data['AdvertisedTrainIdent'] ?? '') ?? 0;
    locationSignature = data['LocationSignature'] ?? '';
  }
}

class TrainPositionRef {
  String serviceJourneyGid;
  int trainNumber;

  TrainPositionRef(this.serviceJourneyGid, this.trainNumber);
}

class TrainPosition extends VehiclePosition {
  late bool active;
  late int advertisedTrainNumber;

  TrainPosition(dynamic data, Iterable<TrainPositionRef> trains) {
    String positionString = data['Position']['WGS84'];
    var splits = positionString.substring(7, positionString.length - 1).split(' ');
    position = LatLng(double.parse(splits[1]), double.parse(splits[0]));
    speed = data['Speed']?.toDouble();
    updatedAt = DateTime.parse(data['TimeStamp']).toLocal();
    active = data['Status']['Active'];
    advertisedTrainNumber = int.parse(data['Train']['AdvertisedTrainNumber']);
    journeyId = trains.firstWhere((train) => train.trainNumber == advertisedTrainNumber).serviceJourneyGid;
  }
}

class TrainPositions {
  final Iterable<TrainPosition> initial;
  final String _sseUrl;
  final Iterable<TrainPositionRef> _trainRefs;

  Future<Stream<Iterable<TrainPosition>>?> getStream() async {
    Response<ResponseBody> response = await Dio().get(
      _sseUrl,
      options: Options(
        contentType: 'text/xml',
        headers: {'Accept': 'text/event-stream'},
        responseType: ResponseType.stream,
      ),
    );

    return response.data?.stream
        .transform(StreamTransformer.fromBind(utf8.decoder.bind))
        .transform(const LineSplitter())
        .transform(StreamTransformer.fromHandlers(
      handleData: (data, sink) {
        if (!data.startsWith('data: ')) return;
        var json = jsonDecode(data.substring(6));
        var trainPositions =
            json['RESPONSE']['RESULT'][0]['TrainPosition'].map<TrainPosition>((t) => TrainPosition(t, _trainRefs));
        sink.add(trainPositions);
      },
    ));
  }

  TrainPositions(this.initial, this._sseUrl, this._trainRefs);
}

class TrainMessage implements TS {
  late String? header;
  late String externalDescription;
  Severity severity = Severity.normal;

  TrainMessage(dynamic data) {
    header = data['Header'];
    externalDescription = data['ExternalDescription'].replaceAll('\n', ' ').replaceAll('  ', ' ');
  }

  @override
  Widget display(BuildContext context, {bool boldTitle = false, bool showAffectedStop = false}) {
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Row(
        children: [
          getNoteIcon(severity),
          const SizedBox(width: 20),
          Expanded(
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    header == null
                        ? externalDescription
                        : '${header!.trim()}${externalDescription.contains(': ') || header!.contains(':') ? '' : ':'} '
                            '$externalDescription',
                    style: TextStyle(color: Theme.of(context).hintColor))),
          ),
        ],
      ),
    );
  }
}

class TrainLegRef {
  int trainNumber;
  DateTime departureTime;
  DateTime arrivalTime;

  TrainLegRef(this.trainNumber, this.departureTime, this.arrivalTime);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrainLegRef &&
          runtimeType == other.runtimeType &&
          trainNumber == other.trainNumber &&
          departureTime == other.departureTime &&
          arrivalTime == other.arrivalTime;

  @override
  int get hashCode => trainNumber.hashCode ^ departureTime.hashCode ^ arrivalTime.hashCode;
}
