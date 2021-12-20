import 'dart:async';

import 'package:flutter/material.dart';

import 'extensions.dart';
import 'journey_detail_widget.dart';
import 'map_widget.dart';
import 'options_panel.dart';
import 'reseplaneraren.dart';
import 'utils.dart';

class DepartureBoardResultWidget extends StatelessWidget {
  final StopLocation _stopLocation;
  final StopLocation? direction;
  final DateTime? _dateTime;
  final DepartureBoardOptions _departureBoardOptions;

  DepartureBoardResultWidget(this._stopLocation, this._dateTime, this._departureBoardOptions,
      {this.direction, Key? key})
      : super(key: key);

  final StreamController<DepartureBoardWithTrafficSituations?> _departureStreamController = StreamController();

  Future<void> _handleRefresh() async => _updateDepartureBoard(addOnlyOnce: true);

  @override
  Widget build(BuildContext context) {
    _updateDepartureBoard();
    return Scaffold(
        appBar: AppBar(
            title: direction == null
                ? Text(_stopLocation.name.firstPart(), overflow: TextOverflow.fade)
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_stopLocation.name.firstPart(), overflow: TextOverflow.fade),
                    Text('mot ' + direction!.name.firstPart(),
                        overflow: TextOverflow.fade, style: const TextStyle(fontSize: 14, color: Colors.white70))
                  ])),
        backgroundColor: cardBackgroundColor(context),
        body: RefreshIndicator(
          onRefresh: () => _handleRefresh(),
          child: StreamBuilder<DepartureBoardWithTrafficSituations?>(
              builder: (context, departureBoard) {
                if (departureBoard.connectionState == ConnectionState.waiting) return loadingPage();
                if (!departureBoard.hasData) return errorPage(_updateDepartureBoard);
                var bgLuminance = Theme.of(context).cardColor.computeLuminance();
                return CustomScrollView(slivers: [
                  departureBoardList(departureBoard.data!.departures, bgLuminance, onTap: (context, departure) async {
                    await Navigator.push(context, MaterialPageRoute(builder: (context) {
                      return JourneyDetailWidget(
                          departure.journeyDetailRef,
                          departure.sname,
                          departure.fgColor,
                          departure.bgColor,
                          departure.direction,
                          departure.journeyId,
                          departure.type,
                          departure.name,
                          departure.journeyNumber);
                    }));
                  }, onLongPress: (context, departure) async {
                    await Navigator.push<MapWidget>(context, MaterialPageRoute(builder: (context) {
                      return MapWidget([MapJourney(journeyDetailRef: departure.journeyDetailRef)]);
                    }));
                  }),
                  trafficSituationList(departureBoard.data!.ts,
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10), showAffectedStop: false)
                ]);
              },
              stream: _departureStreamController.stream),
        ));
  }

  Future<void> _updateDepartureBoard({bool addOnlyOnce = false}) async {
    await getDepartureBoard(
        _departureStreamController, _stopLocation.id, _dateTime, _departureBoardOptions, direction?.id,
        addOnlyOnce: addOnlyOnce);
  }
}

Future<void> getDepartureBoard(StreamController streamController, int stopId, DateTime? dateTime,
    DepartureBoardOptions departureBoardOptions, int? directionId,
    {int? timeSpan, bool addOnlyOnce = false, bool secondPass = false}) async {
  var departuresRequest = reseplaneraren.getDepartureBoard(
    stopId,
    dateTime: dateTime,
    direction: directionId,
    timeSpan: timeSpan,
    useTram: departureBoardOptions.toggleVehicleOptions.isSelected[0] ? null : false,
    useBus: departureBoardOptions.toggleVehicleOptions.isSelected[1] ? null : false,
    useVas: departureBoardOptions.toggleVehicleOptions.isSelected[2] ? null : false,
    useRegTrain: departureBoardOptions.toggleVehicleOptions.isSelected[3] ? null : false,
    useLDTrain: departureBoardOptions.toggleVehicleOptions.isSelected[3] ? null : false,
    useBoat: departureBoardOptions.toggleVehicleOptions.isSelected[4] ? null : false,
  );

  Future<Iterable<Departure>?>? arrivalsRequest;
  if (departureBoardOptions.includeArrivalOptions.includeArrivals && directionId == null) {
    arrivalsRequest = reseplaneraren.getArrivalBoard(
      stopId,
      dateTime: dateTime,
      timeSpan: timeSpan,
      useTram: departureBoardOptions.toggleVehicleOptions.isSelected[0] ? null : false,
      useBus: departureBoardOptions.toggleVehicleOptions.isSelected[1] ? null : false,
      useVas: departureBoardOptions.toggleVehicleOptions.isSelected[2] ? null : false,
      useRegTrain: departureBoardOptions.toggleVehicleOptions.isSelected[3] ? null : false,
      useLDTrain: departureBoardOptions.toggleVehicleOptions.isSelected[3] ? null : false,
      useBoat: departureBoardOptions.toggleVehicleOptions.isSelected[4] ? null : false,
    );
  }

  Future<Iterable<TrafficSituation>?> ts = reseplaneraren.getTrafficSituationsByStopId(stopId);

  var departures = await departuresRequest;

  if (departures != null) {
    var result = departures.toList();

    // Workaround for bug in API where some departures after midnight are missing when direction is set.
    if (directionId != null &&
        (departures.length < 20 || (dateTime ?? DateTime.now()).day != departures.last.dateTime.day)) {
      var departuresAfterMidnight = await reseplaneraren.getDepartureBoard(
        stopId,
        dateTime: nextDay(dateTime),
        direction: directionId,
        timeSpan: timeSpan,
        useTram: departureBoardOptions.toggleVehicleOptions.isSelected[0] ? null : false,
        useBus: departureBoardOptions.toggleVehicleOptions.isSelected[1] ? null : false,
        useVas: departureBoardOptions.toggleVehicleOptions.isSelected[2] ? null : false,
        useRegTrain: departureBoardOptions.toggleVehicleOptions.isSelected[3] ? null : false,
        useLDTrain: departureBoardOptions.toggleVehicleOptions.isSelected[3] ? null : false,
        useBoat: departureBoardOptions.toggleVehicleOptions.isSelected[4] ? null : false,
      );

      result = departures
          .followedBy(departuresAfterMidnight?.where((d) => !result.any((e) => e.journeyId == d.journeyId)) ?? [])
          .toList();
    }

    if (departureBoardOptions.includeArrivalOptions.includeArrivals) {
      var arrivals = await arrivalsRequest;

      if (departureBoardOptions.includeArrivalOptions.includeArrivals) {
        arrivals = await arrivalsRequest ?? arrivals;

        if (arrivals != null) {
          arrivals = arrivals.where(
              (a) => !result.any((d) => d.journeyId == a.journeyId) && a.dateTime.isBefore(result.last.dateTime));
          result.insertAll(0, arrivals);
        }
      }
    }

    result.sort((a, b) => (a.getDateTime()).compareTo(b.getDateTime()));

    var filteredTs = (await ts)
        ?.where((ts) => isPresent(ts.startTime, ts.endTime, dateTime ?? DateTime.now(), dateTime ?? DateTime.now()));

    if (directionId != null) {
      filteredTs = filteredTs?.where((ts) => ts.affectedLines
          .map((line) => line.gid)
          .toSet()
          .intersection(result.map((departure) => lineIdFromJourneyId(departure.journeyId)).toSet())
          .isNotEmpty);
    }

    filteredTs = filteredTs?.toList()
      ?..sort((a, b) => getNotePriority(a.severity).compareTo(getNotePriority(b.severity)));

    // If the next 20 departures does not include all departures within the next 10 minutes.
    if (departures.isNotEmpty &&
        departures.last.dateTime.isBefore((dateTime ?? DateTime.now()).add(const Duration(minutes: 10))) &&
        !secondPass) {
      getDepartureBoard(streamController, stopId, dateTime, departureBoardOptions, directionId,
          timeSpan: 10, secondPass: true);
      if (addOnlyOnce) return;
    }

    streamController.add(DepartureBoardWithTrafficSituations(result, filteredTs ?? []));
  } else {
    streamController.add(null);
  }
}

Widget departureBoardList(Iterable<Departure> departures, double bgLuminance,
    {void Function(BuildContext, Departure)? onTap, void Function(BuildContext, Departure)? onLongPress}) {
  if (departures.isEmpty) return SliverFillRemaining(child: noDataPage('Inga avgångar hittades.'));
  return SliverPadding(
    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
    sliver: SliverSafeArea(
      sliver: SliverList(
          delegate: SliverChildBuilderDelegate((context, i) {
        var departure = departures.elementAt(i);
        return Card(
            child: InkWell(
                onTap: onTap != null ? () => onTap(context, departure) : null,
                onLongPress: onLongPress != null ? () => onLongPress(context, departure) : null,
                child: Container(
                    constraints: const BoxConstraints(minHeight: 42),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    child: Row(children: [
                      Container(
                        child: Text(
                            departure.dateTime.time() + addLineIfNotEmpty(getDelayString(getDepartureDelay(departure))),
                            style: departure.cancelled ? cancelledTextStyle : null),
                        constraints: const BoxConstraints(minWidth: 35 + 8),
                      ),
                      Container(
                          child: Text(getCountdown(departure),
                              textAlign: TextAlign.center,
                              style: departure.cancelled
                                  ? const TextStyle(color: Colors.red)
                                  : const TextStyle(fontWeight: FontWeight.bold)),
                          constraints: const BoxConstraints(minWidth: 28)),
                      const SizedBox(width: 8),
                      lineIconFromDeparture(departure, bgLuminance, context),
                      const SizedBox(width: 10),
                      Expanded(
                          child: departure.arrival
                              ? Row(
                                  children: [
                                    const Icon(Icons.arrow_back, size: 18),
                                    const SizedBox(width: 5),
                                    Expanded(
                                        child: highlightFirstPart(departure.direction, overflow: TextOverflow.fade)),
                                  ],
                                )
                              : highlightFirstPart(departure.direction, overflow: TextOverflow.fade)),
                      const SizedBox(width: 10),
                      accessibilityIcon(departure.accessibility, departure.rtDateTime,
                          margin: EdgeInsets.fromLTRB(0, 0, departure.track == null ? 0 : 10, 0)),
                      Text(departure.rtTrack ?? departure.track ?? '')
                    ]))));
      }, childCount: departures.length)),
    ),
  );
}

class DepartureBoardWithTrafficSituations {
  Iterable<Departure> departures;
  Iterable<TrafficSituation> ts;

  DepartureBoardWithTrafficSituations(this.departures, this.ts);
}
