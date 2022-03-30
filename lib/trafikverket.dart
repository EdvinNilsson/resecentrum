import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'reseplaneraren.dart';
import 'utils.dart';

Trafikverket trafikverket = Trafikverket();

class Trafikverket {
  final Dio _dio =
      Dio(BaseOptions(baseUrl: 'https://api.trafikinfo.trafikverket.se', connectTimeout: 5000, receiveTimeout: 10000));

  Future<T?> _callApi<T>(String query, T Function(Response) generator) async {
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
    } catch (e, st) {
      if (kDebugMode) {
        print(e);
        print(st);
      }
      return null;
    }
  }

  Future<Iterable<TrainAnnouncement>?> getTrainJourney(int journeyNumber, DateTime start, DateTime end) async {
    return await _callApi('''
<QUERY objecttype="TrainAnnouncement" schemaversion="1.6" orderby="AdvertisedTimeAtLocation">
    <FILTER>
        <AND>
            <EQ name="AdvertisedTrainIdent" value="$journeyNumber" />
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

  Future<Iterable<TrainAnnouncement>?> getTrainTrips(Set<TrainTripRequest> trips) async {
    return await _callApi('''
<QUERY objecttype="TrainAnnouncement" schemaversion="1.6" orderby="AdvertisedTimeAtLocation">
    <FILTER>
        <AND>
            <EQ name="ActivityType" value="Ankomst" />
            <EQ name="Advertised" value="true" />
            <OR>
                ${trips.map((d) => '''
                <AND>
                    <EQ name="AdvertisedTrainIdent" value="${d.journeyNumber}" />
                    <EQ name="AdvertisedTimeAtLocation" value="${d.arrTime.toIso8601String()}" />
                </AND>
                ''').join()}
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
<QUERY objecttype="TrainAnnouncement" schemaversion="1.6" orderby="AdvertisedTimeAtLocation">
    <FILTER>
        <AND>
            <EQ name="ActivityType" value="Avgang" />
            <EQ name="Advertised" value="true" />
            <OR>
                ${trips.map((d) => '''
                <AND>
                    <EQ name="AdvertisedTrainIdent" value="${d.journeyNumber}" />
                    <EQ name="AdvertisedTimeAtLocation" value="${d.depTime.toIso8601String()}" />
                </AND>
                ''').join()}
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

  Future<Iterable<TrainAnnouncement>?> getTrainStationBoard(Iterable<Departure> departureBoard,
      {bool arrival = false}) async {
    var filteredBoard = departureBoard.where((d) => d.arrival == arrival && isTrainType(d.type));
    if (filteredBoard.isEmpty) return [];
    return await _callApi('''
<QUERY objecttype="TrainAnnouncement" schemaversion="1.6">
    <FILTER>
        <AND>
            <EQ name="ActivityType" value="${arrival ? 'Ankomst' : 'Avgang'}" />
            <EQ name="Advertised" value="true" />
            <OR>
                ${filteredBoard.map((d) => '''
                <AND>
                    <EQ name="AdvertisedTrainIdent" value="${d.journeyNumber}" />
                    <EQ name="AdvertisedTimeAtLocation" value="${d.dateTime.toIso8601String()}" />
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

  Future<String?> getTrainStationFromLocation(double lon, lat) async {
    return await _callApi('''
<QUERY objecttype="TrainStation" schemaversion="1.4">
    <FILTER>
        <WITHIN name="Geometry.WGS84" shape="center" value="$lon $lat" radius="500m" />
        <EQ name="Advertised" value="true" />
    </FILTER>
    <INCLUDE>LocationSignature</INCLUDE>
</QUERY>
''', (result) {
      return result.data['RESPONSE']['RESULT'].first['TrainStation'].first['LocationSignature'];
    });
  }

  Future<Iterable<TrainMessage>?> getTrainStationMessage(
      String locationSignature, DateTime start, DateTime end, String? direction) async {
    return await _callApi('''
<QUERY objecttype="TrainMessage" schemaversion="1.7" orderby="LastUpdateDateTime desc">
    <FILTER>
        <AND>
            <EQ name="TrafficImpact.AffectedLocation.LocationSignature" value="$locationSignature" />
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

  Future<Iterable<TrainMessage>?> getTrainMessage(
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
        <IN name="TrafficImpact.AffectedLocation.LocationSignature" value="G" />
    </FILTER>
    <INCLUDE>Header</INCLUDE>
    <INCLUDE>ExternalDescription</INCLUDE>
</QUERY>
''', (result) {
      return result.data['RESPONSE']['RESULT'].first['TrainMessage'].map<TrainMessage>((t) => TrainMessage(t));
    });
  }

  Future<Iterable<TrainAnnouncement>?> getLateTrains(String locationSignature, DateTime dateTime) async {
    return await _callApi('''
<QUERY objecttype="TrainAnnouncement" schemaversion="1.6" orderby="AdvertisedTimeAtLocation">
    <FILTER>
        <AND>
        <EQ name="LocationSignature" value="$locationSignature" />
            <AND>
                <LT name="AdvertisedTimeAtLocation" value="${dateTime.toIso8601String()}" />
                <OR>
                    <GTE name="EstimatedTimeAtLocation" value="${dateTime.toIso8601String()}" />
                    <AND>
                        <EXISTS name="TimeAtLocation" value="false" />
                        <OR>
                            <GTE name="AdvertisedTimeAtLocation" value="${dateTime.subtract(const Duration(minutes: 15))}" />
                            <GTE name="EstimatedTimeAtLocation" value="${dateTime.subtract(const Duration(minutes: 15))}" />
                        </OR>
                        <EQ name="Canceled" value="false" />
                    </AND>
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
</QUERY>
''', (result) {
      return result.data['RESPONSE']['RESULT'].first['TrainAnnouncement']
          .map<TrainAnnouncement>((t) => TrainAnnouncement(t));
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

class TrainMessage implements TS {
  late String header;
  late String externalDescription;
  String severity = 'normal';

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
                child: Text('$header${externalDescription.contains(': ') ? '' : ':'} $externalDescription',
                    style: TextStyle(color: Theme.of(context).hintColor))),
          ),
        ],
      ),
    );
  }
}

class TrainTripRequest {
  int journeyNumber;
  DateTime depTime;
  DateTime arrTime;

  TrainTripRequest(this.journeyNumber, this.depTime, this.arrTime);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrainTripRequest &&
          runtimeType == other.runtimeType &&
          journeyNumber == other.journeyNumber &&
          depTime == other.depTime &&
          arrTime == other.arrTime;

  @override
  int get hashCode => journeyNumber.hashCode ^ depTime.hashCode ^ arrTime.hashCode;
}
