import 'dart:async';

import 'package:collection/collection.dart';
import 'package:diffutil_sliverlist/diffutil_sliverlist.dart';
import 'package:flutter/material.dart';

import 'extensions.dart';
import 'journey_detail_widget.dart';
import 'map_widget.dart';
import 'options_panel.dart';
import 'reseplaneraren.dart';
import 'trafikverket.dart';
import 'utils.dart';
import 'vehicle_positions_service.dart';

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
    _timer?.cancel();
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
        body: SystemGestureArea(
          MediaQuery.of(context).systemGestureInsets,
          child: RefreshIndicator(
            onRefresh: () => _handleRefresh(),
            child: StreamBuilder<DepartureBoardWithTrafficSituations?>(
                builder: (context, departureBoard) {
                  if (departureBoard.connectionState == ConnectionState.waiting) return loadingPage();
                  if (!departureBoard.hasData) return ErrorPage(_updateDepartureBoard);
                  var bgLuminance = Theme.of(context).cardColor.computeLuminance();
                  return CustomScrollView(slivers: [
                    SliverSafeArea(
                      sliver: departureBoardList(departureBoard.data!.departures, bgLuminance,
                          onTap: (context, departure) async {
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
                              departure.journeyNumber,
                              departure.stopId,
                              departure.dateTime);
                        })).then((_) => _initTimer());
                      }, onLongPress: (context, departure) async {
                        await Navigator.push<MapWidget>(context, MaterialPageRoute(builder: (context) {
                          _timer?.cancel();
                          return MapWidget([MapJourney(journeyDetailRef: JourneyDetailRef.fromDeparture(departure))]);
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
          ),
        ));
  }

  Future<void> _updateDepartureBoard({bool addOnlyOnce = false, bool ignoreError = false}) async {
    await getDepartureBoard(_departureStreamController, widget._stopLocation.id, widget._dateTime,
        widget._departureBoardOptions, widget.direction, widget._stopLocation.lat, widget._stopLocation.lon,
        addOnlyOnce: addOnlyOnce, ignoreError: ignoreError);
  }
}

Future<void> getDepartureBoard(StreamController streamController, int stopId, DateTime? dateTime,
    DepartureBoardOptions departureBoardOptions, StopLocation? direction, double lat, long,
    {int? timeSpan, bool addOnlyOnce = false, bool secondPass = false, bool ignoreError = false}) async {
  var departuresRequest = reseplaneraren.getDepartureBoard(
    stopId,
    dateTime: dateTime,
    direction: direction?.id,
    timeSpan: timeSpan,
    useTram: departureBoardOptions.toggleVehicleOptions.isSelected[0] ? null : false,
    useBus: departureBoardOptions.toggleVehicleOptions.isSelected[1] ? null : false,
    useVas: departureBoardOptions.toggleVehicleOptions.isSelected[2] ? null : false,
    useRegTrain: departureBoardOptions.toggleVehicleOptions.isSelected[3] ? null : false,
    useLDTrain: departureBoardOptions.toggleVehicleOptions.isSelected[3] ? null : false,
    useBoat: departureBoardOptions.toggleVehicleOptions.isSelected[4] ? null : false,
  );

  Future<Iterable<Departure>?>? arrivalsRequest;
  if (departureBoardOptions.includeArrivalOptions.includeArrivals && direction == null) {
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
    if (direction != null &&
        (departures.length < 20 || (dateTime ?? DateTime.now()).day != departures.last.dateTime.day) &&
        !secondPass) {
      var departuresAfterMidnight = await reseplaneraren.getDepartureBoard(
        stopId,
        dateTime: (dateTime ?? DateTime.now()).startONextDay(),
        direction: direction.id,
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

    var needDepartedCheck = result.where((d) {
      var timeLeft = d.getDateTime().difference(DateTime.now());
      var minutesLeft = timeLeft.minutesRounded();
      return d.rtDateTime == null && minutesLeft >= -1 && minutesLeft <= 5 && !d.cancelled;
    });

    if (needDepartedCheck.isNotEmpty) {
      Iterable<VehiclePosition>? positions =
          await vehiclePositionsService.getPositions(needDepartedCheck.map((d) => d.journeyId).toList(growable: false));
      for (VehiclePosition position in positions ?? []) {
        var departure = needDepartedCheck.firstWhere((d) => d.journeyId == position.journeyId);
        if (hasDeparted(position, lat, long)) departure.state = DepartureState.departed;
      }
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

    var filteredTs = (await ts)
        ?.where((ts) => isPresent(ts.startTime, ts.endTime, dateTime ?? DateTime.now(), dateTime ?? DateTime.now()));

    if (direction != null) {
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
      getDepartureBoard(streamController, stopId, dateTime, departureBoardOptions, direction, lat, long,
          timeSpan: 15, secondPass: true, ignoreError: ignoreError);
      if (addOnlyOnce) return;
    }

    var notes = <TS>[];

    if (result.any((d) => isTrainType(d.type) && !d.arrival)) {
      var trainDeparturesRequest = trafikverket.getTrainStationBoard(result);
      var trainArrivalsRequest = departureBoardOptions.includeArrivalOptions.includeArrivals && direction == null
          ? trafikverket.getTrainStationBoard(result, arrival: true)
          : null;

      var trainActivities = (await trainDeparturesRequest)?.followedBy(await trainArrivalsRequest ?? []);

      if (trainActivities == null) {
        notes.add(Note(0, 'low', 'Kunde inte hämta information från Trafikverket'));
      } else if (trainActivities.isNotEmpty) {
        String locationSignature = trainActivities.first.locationSignature;

        var lateTrainsRequest = trafikverket.getLateTrains(locationSignature, dateTime ?? DateTime.now());

        String? directionSignature;
        if (direction != null) {
          directionSignature = await trafikverket.getTrainStationFromLocation(direction.lon, direction.lat);
        }

        var trainStationMessages = trafikverket.getTrainStationMessage(
            locationSignature, dateTime ?? DateTime.now(), result.last.getDateTime(), directionSignature);

        var lateTrains = await lateTrainsRequest;

        notes.addAll((await trainStationMessages ?? <TrainMessage>[]));

        if (lateTrains != null && lateTrains.isNotEmpty) {
          var lateDepartures = lateTrains.where((t) => t.activityType == 'Avgang');
          var lateArrivals = lateTrains.where((t) => t.activityType == 'Ankomst');

          List<TrainAnnouncement> lateTrainActivities = [];

          if (lateDepartures.isNotEmpty) {
            var lateDepartureBoard = await reseplaneraren.getDepartureBoard(stopId,
                dateTime: lateDepartures.first.advertisedTimeAtLocation,
                timeSpan: lateDepartures.last.advertisedTimeAtLocation
                    .difference(lateDepartures.first.advertisedTimeAtLocation)
                    .inMinutes,
                direction: direction?.id,
                useBus: false,
                useTram: false,
                useBoat: false);

            if (lateDepartureBoard != null) {
              for (TrainAnnouncement lateDeparture in lateDepartures) {
                var missingDeparture =
                    lateDepartureBoard.firstWhereOrNull((d) => d.journeyNumber == lateDeparture.advertisedTrainIdent);
                if (missingDeparture != null &&
                    !result.any((d) =>
                        d.journeyNumber == lateDeparture.advertisedTrainIdent &&
                        d.dateTime.isAtSameMomentAs(lateDeparture.advertisedTimeAtLocation))) {
                  result.add(missingDeparture);
                  lateTrainActivities.add(lateDeparture);
                }
              }
            }
          }

          if (lateArrivals.isNotEmpty &&
              departureBoardOptions.includeArrivalOptions.includeArrivals &&
              direction == null) {
            var lateArrivalBoard = await reseplaneraren.getArrivalBoard(stopId,
                dateTime: lateArrivals.first.advertisedTimeAtLocation,
                timeSpan: lateArrivals.last.advertisedTimeAtLocation
                    .difference(lateArrivals.first.advertisedTimeAtLocation)
                    .inMinutes,
                useBus: false,
                useTram: false,
                useBoat: false);

            if (lateArrivalBoard != null) {
              for (TrainAnnouncement lateArrival in lateArrivals) {
                var missingArrival =
                    lateArrivalBoard.firstWhereOrNull((d) => d.journeyNumber == lateArrival.advertisedTrainIdent);
                if (missingArrival != null &&
                    !result.any((d) =>
                        d.journeyNumber == lateArrival.advertisedTrainIdent &&
                        d.dateTime.isAtSameMomentAs(lateArrival.advertisedTimeAtLocation))) {
                  result.add(missingArrival);
                  lateTrainActivities.add(lateArrival);
                }
              }
            }
          }

          trainActivities = trainActivities.followedBy(lateTrainActivities);
        }
      }

      for (TrainAnnouncement activity in trainActivities ?? []) {
        int i = result.indexWhere((d) =>
            d.journeyNumber == activity.advertisedTrainIdent &&
            d.dateTime == activity.advertisedTimeAtLocation &&
            isTrainType(d.type) &&
            d.arrival == (activity.activityType == 'Ankomst'));
        if (i == -1) continue;
        result[i].rtDateTime = activity.timeAtLocation ??
            activity.estimatedTimeAtLocation ??
            activity.plannedEstimatedTimeAtLocation ??
            activity.advertisedTimeAtLocation;
        result[i].track = activity.trackAtLocation;
        if (activity.deviation.contains('Spårändrat')) result[i].rtTrack = activity.trackAtLocation;
        result[i].cancelled |= activity.canceled;

        if (activity.deviation.isNotEmpty) result[i].direction += ', ' + activity.deviation.join(', ');

        if (activity.timeAtLocation == null && (result[i].rtDateTime?.isBefore(DateTime.now()) ?? false)) {
          result[i].state = DepartureState.atStation;
        }
        if (activity.deviation.contains('Invänta tid')) result[i].state = DepartureState.unknownTime;
        if (activity.deviation.contains('Buss ersätter')) result[i].state = DepartureState.replacementBus;
        if (activity.deviation.contains('Taxi ersätter')) result[i].state = DepartureState.replacementTaxi;
        if (activity.timeAtLocation != null &&
            activity.activityType == 'Avgang' &&
            (result[i].rtDateTime?.isAfter(DateTime.now().subtract(const Duration(minutes: 15))) ?? false)) {
          result[i].state = DepartureState.departed;
        }
      }
    }

    result.sort((a, b) {
      int cmp = a.getDateTime().compareTo(b.getDateTime());
      if (cmp != 0) return cmp;
      cmp = a.dateTime.compareTo(b.dateTime);
      if (cmp != 0) return cmp;
      if (a.arrival != b.arrival) return a.arrival ? -1 : 1;
      return a.journeyId.compareTo(b.journeyId);
    });

    streamController.add(DepartureBoardWithTrafficSituations(result, (filteredTs ?? []).cast<TS>().followedBy(notes)));
  } else {
    if (ignoreError) return;
    streamController.add(null);
  }
}

Widget departureBoardList(Iterable<Departure> departures, double bgLuminance,
    {void Function(BuildContext, Departure)? onTap, void Function(BuildContext, Departure)? onLongPress}) {
  if (departures.isEmpty) return SliverFillRemaining(child: noDataPage('Inga avgångar hittades'));
  return SliverPadding(
    padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 3),
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
                            style: departure.cancelled
                                ? departure.state == DepartureState.replacementBus ||
                                        departure.state == DepartureState.replacementTaxi
                                    ? cancelledTextStyle.copyWith(color: orange(context))
                                    : cancelledTextStyle
                                : null),
                        constraints: const BoxConstraints(minWidth: 35 + 8),
                      ),
                      Container(child: getCountdown(departure), constraints: const BoxConstraints(minWidth: 28)),
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
                                        child: highlightFirstPart(
                                            isTrainType(departure.type)
                                                ? 'Från ${[
                                                    shortStationName(departure.origin!, useAcronyms: false)
                                                  ].followedBy(departure.direction.split(',').skip(1)).join(',')}'
                                                : departure.direction,
                                            overflow: TextOverflow.fade)),
                                  ],
                                )
                              : highlightFirstPart(departure.direction, overflow: TextOverflow.fade)),
                      const SizedBox(width: 10),
                      accessibilityIcon(departure.accessibility, departure.rtDateTime,
                          margin: EdgeInsets.fromLTRB(
                              0, 0, departure.track == null ? 0 : (departure.rtTrack == null ? 5 : 10), 0)),
                      departure.rtTrack != null ? trackChange(departure.rtTrack!) : Text(departure.track ?? '')
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
  Iterable<TS> ts;

  DepartureBoardWithTrafficSituations(this.departures, this.ts);
}
