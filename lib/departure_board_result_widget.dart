import 'dart:async';

import 'package:diffutil_sliverlist/diffutil_sliverlist.dart';
import 'package:flutter/material.dart';

import 'extensions.dart';
import 'journey_detail_widget.dart';
import 'map_widget.dart';
import 'options_panel.dart';
import 'reseplaneraren.dart';
import 'utils.dart';

class DepartureBoardResultWidget extends StatefulWidget {
  final StopLocation _stopLocation;
  final StopLocation? direction;
  final DateTime? _dateTime;
  final DepartureBoardOptions _departureBoardOptions;

  const DepartureBoardResultWidget(this._stopLocation, this._dateTime, this._departureBoardOptions,
      {this.direction, Key? key})
      : super(key: key);

  @override
  State<DepartureBoardResultWidget> createState() => _DepartureBoardResultWidgetState();
}

class _DepartureBoardResultWidgetState extends State<DepartureBoardResultWidget> with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance!.addObserver(this);
    _initTimer(updateIntermittently: false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance!.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_timer == null) return;
    if (state != AppLifecycleState.resumed && _timer!.isActive) {
      _timer?.cancel();
    } else if (state == AppLifecycleState.resumed && !_timer!.isActive) {
      _initTimer();
    }
  }

  void _initTimer({bool updateIntermittently = true}) {
    _timer =
        Timer.periodic(const Duration(seconds: 15), (_) => _updateDepartureBoard(addOnlyOnce: true, ignoreError: true));
    if (updateIntermittently) _updateDepartureBoard(addOnlyOnce: true, ignoreError: true);
  }

  final StreamController<DepartureBoardWithTrafficSituations?> _departureStreamController = StreamController();

  Future<void> _handleRefresh() async => _updateDepartureBoard(addOnlyOnce: true, ignoreError: true);

  @override
  Widget build(BuildContext context) {
    _updateDepartureBoard();
    return Scaffold(
        appBar: AppBar(
            title: widget.direction == null
                ? Text(widget._stopLocation.name.firstPart(), overflow: TextOverflow.fade)
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget._stopLocation.name.firstPart(), overflow: TextOverflow.fade),
                    Text('mot ' + widget.direction!.name.firstPart(),
                        overflow: TextOverflow.fade, style: const TextStyle(fontSize: 14, color: Colors.white70))
                  ])),
        backgroundColor: cardBackgroundColor(context),
        body: RefreshIndicator(
          onRefresh: () => _handleRefresh(),
          child: StreamBuilder<DepartureBoardWithTrafficSituations?>(
              builder: (context, departureBoard) {
                if (departureBoard.connectionState == ConnectionState.waiting) return loadingPage();
                if (!departureBoard.hasData) return ErrorPage(_updateDepartureBoard);
                var bgLuminance = Theme.of(context).cardColor.computeLuminance();
                return CustomScrollView(slivers: [
                  SliverSafeArea(
                    sliver: departureBoardList(departureBoard.data!.departures, bgLuminance, widget._stopLocation.lat,
                        widget._stopLocation.lon, onTap: (context, departure) async {
                      _timer?.cancel();
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
                      })).then((_) => _initTimer());
                    }, onLongPress: (context, departure) async {
                      await Navigator.push<MapWidget>(context, MaterialPageRoute(builder: (context) {
                        _timer?.cancel();
                        return MapWidget([MapJourney(journeyDetailRef: departure.journeyDetailRef)]);
                      })).then((_) => _initTimer());
                    }),
                    bottom: false,
                  ),
                  SliverSafeArea(
                    sliver: trafficSituationList(departureBoard.data!.ts,
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10), showAffectedStop: false),
                  )
                ]);
              },
              stream: _departureStreamController.stream),
        ));
  }

  Future<void> _updateDepartureBoard({bool addOnlyOnce = false, bool ignoreError = false}) async {
    await getDepartureBoard(_departureStreamController, widget._stopLocation.id, widget._dateTime,
        widget._departureBoardOptions, widget.direction?.id,
        addOnlyOnce: addOnlyOnce, ignoreError: ignoreError);
  }
}

Future<void> getDepartureBoard(StreamController streamController, int stopId, DateTime? dateTime,
    DepartureBoardOptions departureBoardOptions, int? directionId,
    {int? timeSpan, bool addOnlyOnce = false, bool secondPass = false, bool ignoreError = false}) async {
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

      if (arrivals != null) {
        arrivals = arrivals.where((a) =>
            !result.any((d) => d.journeyId == a.journeyId) &&
            a.dateTime.isBefore(result.last.dateTime) &&
            !(dateTime == null && a.dateTime.isBefore(DateTime.now())));
        result.insertAll(0, arrivals);
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

    // If the next 20 departures does not include all departures within the next 15 minutes.
    if (result.isNotEmpty &&
        result.last.dateTime.isBefore((dateTime ?? DateTime.now()).add(const Duration(minutes: 15))) &&
        !secondPass) {
      getDepartureBoard(streamController, stopId, dateTime, departureBoardOptions, directionId,
          timeSpan: 15, secondPass: true, ignoreError: ignoreError);
      if (addOnlyOnce) return;
    }

    streamController.add(DepartureBoardWithTrafficSituations(result, filteredTs ?? []));
  } else {
    if (ignoreError) return;
    streamController.add(null);
  }
}

Widget departureBoardList(Iterable<Departure> departures, double bgLuminance, double lat, double long,
    {void Function(BuildContext, Departure)? onTap, void Function(BuildContext, Departure)? onLongPress}) {
  if (departures.isEmpty) return SliverFillRemaining(child: noDataPage('Inga avgångar hittades'));
  return SliverPadding(
    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
    sliver: DiffUtilSliverList<Departure>(
      equalityChecker: (a, b) => a.journeyId == b.journeyId && a.dateTime == b.dateTime,
      items: departures.toList(growable: false),
      builder: (BuildContext context, Departure departure) {
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
                          child: Builder(
                            builder: (context) {
                              var res = getCountdown(departure);
                              if (!res.needExtraCheck || departure.arrival) {
                                return Text(res.text,
                                    textAlign: TextAlign.center,
                                    style: departure.cancelled
                                        ? const TextStyle(color: Colors.red)
                                        : const TextStyle(fontWeight: FontWeight.bold));
                              } else {
                                return FutureBuilder<bool>(
                                    future: hasDeparted(departure, lat, long),
                                    builder: (context, departed) {
                                      if (!departed.hasData || !departed.data!) {
                                        return Text(res.text,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(fontWeight: FontWeight.bold));
                                      }
                                      return const Text('avgått', textAlign: TextAlign.center);
                                    });
                              }
                            },
                          ),
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
      },
      insertAnimationBuilder: (context, animation, child) => FadeTransition(
        opacity: animation,
        child: child,
      ),
      removeAnimationBuilder: (context, animation, child) => FadeTransition(
        opacity: animation,
        child: SizeTransition(
          sizeFactor: animation,
          axisAlignment: 0,
          child: child,
        ),
      ),
    ),
  );
}

class DepartureBoardWithTrafficSituations {
  Iterable<Departure> departures;
  Iterable<TrafficSituation> ts;

  DepartureBoardWithTrafficSituations(this.departures, this.ts);
}
