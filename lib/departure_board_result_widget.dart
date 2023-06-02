import 'dart:async';

import 'package:collection/collection.dart';
import 'package:diffutil_sliverlist/diffutil_sliverlist.dart';
import 'package:flutter/material.dart';

import 'extensions.dart';
import 'journey_detail_widget.dart';
import 'main.dart';
import 'map_widget.dart';
import 'options_panel.dart';
import 'reseplaneraren.dart';
import 'trafikverket.dart';
import 'utils.dart';
import 'vehicle_positions_service.dart';

class DepartureBoardResultWidget extends StatefulWidget {
  final Location _location;
  final StopLocation? direction;
  final DateTime? _dateTime;
  final DepartureBoardOptions _departureBoardOptions;

  const DepartureBoardResultWidget(this._location, this._dateTime, this._departureBoardOptions,
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
    if (state != AppLifecycleState.resumed && _timer?.isActive == true) {
      _timer?.cancel();
    } else if (state == AppLifecycleState.resumed && _timer?.isActive == false) {
      _initTimer();
    }
  }

  void _initTimer({bool updateIntermittently = true}) {
    _timer?.cancel();
    _timer =
        Timer.periodic(const Duration(seconds: 15), (_) => _updateDepartureBoard(addOnlyOnce: true, ignoreError: true));
    if (updateIntermittently) _updateDepartureBoard(addOnlyOnce: true, ignoreError: true);
  }

  final StreamController<DepartureBoardWithTrafficSituations> _departureStreamController = StreamController.broadcast();

  Future<void> _handleRefresh() async => _updateDepartureBoard(addOnlyOnce: true, ignoreError: true);

  @override
  Widget build(BuildContext context) {
    _updateDepartureBoard();
    return Scaffold(
        appBar: AppBar(
            title: StreamBuilder(stream: _departureStreamController.stream, builder: (context, snapshot) => _title()),
            actions: supportShortcuts
                ? <Widget>[
                    PopupMenuButton(
                        onSelected: (_) => _createShortcut(),
                        itemBuilder: (BuildContext context) => [
                              const PopupMenuItem(
                                  value: 0,
                                  child: ListTile(
                                      leading: Icon(Icons.add_to_home_screen),
                                      title: Text('Skapa genväg'),
                                      visualDensity: VisualDensity.compact))
                            ])
                  ]
                : null),
        backgroundColor: cardBackgroundColor(context),
        body: SystemGestureArea(
          MediaQuery.of(context).systemGestureInsets,
          child: RefreshIndicator(
            onRefresh: () => _handleRefresh(),
            child: StreamBuilder<DepartureBoardWithTrafficSituations>(
                builder: (context, departureBoard) {
                  if (departureBoard.connectionState == ConnectionState.waiting) return loadingPage();
                  if (!departureBoard.hasData) return ErrorPage(_updateDepartureBoard, error: departureBoard.error);
                  if (departureBoard.data!.departures.isEmpty) return noDataPage('Inga avgångar hittades');
                  var bgLuminance = Theme.of(context).cardColor.computeLuminance();
                  return CustomScrollView(slivers: [
                    if (widget._dateTime != null && departureBoard.data!.departures.isNotEmpty)
                      dateBar(widget._dateTime!),
                    SliverSafeArea(
                      sliver:
                          departureBoardList(departureBoard.data!.departures, bgLuminance, onTap: (context, departure) {
                        _timer?.cancel();
                        Navigator.push(context, MaterialPageRoute(builder: (context) {
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
                      }, onLongPress: (context, departure) {
                        Navigator.push<MapWidget>(context, MaterialPageRoute(builder: (context) {
                          _timer?.cancel();
                          return MapWidget([
                            MapJourney(
                                journeyDetailRef: JourneyDetailRef.fromDeparture(departure),
                                refStopId: departure.stopId,
                                focusJid: departure.journeyId)
                          ]);
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

  Widget _title() {
    var text = widget._location is CurrentLocation
        ? Row(
            children: [
              const Icon(Icons.my_location),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(
                      (widget._location as CurrentLocation).cachedLocation?.name.firstPart() ??
                          widget._location.getName().split(', ').last.capitalize(),
                      overflow: TextOverflow.fade)),
            ],
          )
        : Text(widget._location.name.firstPart(), overflow: TextOverflow.fade);

    return widget.direction == null
        ? text
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            text,
            Text('mot ${widget.direction!.name.firstPart()}',
                overflow: TextOverflow.fade, style: const TextStyle(fontSize: 14, color: Colors.white70))
          ]);
  }

  Future<void> _updateDepartureBoard({bool addOnlyOnce = false, bool ignoreError = false}) async {
    int stopId;
    if (widget._location is CurrentLocation) {
      try {
        StopLocation? location =
            await (widget._location as CurrentLocation).location(onlyStops: true, forceRefresh: true) as StopLocation?;
        if (location == null) throw NoLocationError();
        stopId = location.id;
      } catch (e) {
        return _departureStreamController.addError(e);
      }
    } else {
      stopId = (widget._location as StopLocation).id;
    }
    await getDepartureBoard(_departureStreamController, stopId, widget._dateTime, widget._departureBoardOptions,
        widget.direction, widget._location.lat, widget._location.lon,
        addOnlyOnce: addOnlyOnce, ignoreError: ignoreError);
  }

  void _createShortcut() {
    Map<String, String> params = {};

    if (widget._location is CurrentLocation) {
      params['currentLocation'] = 'true';
    } else if (widget._location is StopLocation) {
      params['id'] = (widget._location as StopLocation).id.toString();
      params['name'] = widget._location.name;
      params['lat'] = widget._location.lat.toString();
      params['lon'] = widget._location.lon.toString();
    }

    if (widget.direction != null) {
      params['dirId'] = widget.direction!.id.toString();
      params['dirName'] = widget.direction!.name;
      params['dirLat'] = widget.direction!.lat.toString();
      params['dirLon'] = widget.direction!.lon.toString();
    }

    if (widget._departureBoardOptions.includeArrivals) {
      params['includeArrivals'] = 'true';
    }

    if (!widget._departureBoardOptions.services.every((b) => b)) {
      params['services'] = widget._departureBoardOptions.services.map((b) => b ? 1 : 0).join();
    }

    var uri = Uri(scheme: 'resecentrum', host: 'board', queryParameters: params);

    var icon = widget._location is StopLocation
        ? getStopIconString((widget._location as StopLocation).id.toString())
        : 'my_location';

    var summary = widget._departureBoardOptions.summary;

    createShortcut(context, uri.toString(), widget._location.name.firstPart(), icon, summary);
  }
}

Future<void> getDepartureBoard(StreamController streamController, int stopId, DateTime? dateTime,
    DepartureBoardOptions departureBoardOptions, StopLocation? direction, double lat, long,
    {int? timeSpan, bool addOnlyOnce = false, bool secondPass = false, bool ignoreError = false}) async {
  try {
    var departuresRequest = reseplaneraren.getDepartureBoard(
      stopId,
      dateTime: dateTime,
      direction: direction?.id,
      timeSpan: timeSpan,
      useTram: departureBoardOptions.services[0] ? null : false,
      useBus: departureBoardOptions.services[1] ? null : false,
      useVas: departureBoardOptions.services[2] ? null : false,
      useRegTrain: departureBoardOptions.services[3] ? null : false,
      useLDTrain: departureBoardOptions.services[3] ? null : false,
      useBoat: departureBoardOptions.services[4] ? null : false,
    );

    Future<Iterable<Departure>?>? arrivalsRequest;
    if (departureBoardOptions.includeArrivals && direction == null) {
      arrivalsRequest = reseplaneraren
          .getArrivalBoard(
            stopId,
            dateTime: dateTime ?? DateTime.now(),
            timeSpan: timeSpan,
            useTram: departureBoardOptions.services[0] ? null : false,
            useBus: departureBoardOptions.services[1] ? null : false,
            useVas: departureBoardOptions.services[2] ? null : false,
            useRegTrain: departureBoardOptions.services[3] ? null : false,
            useLDTrain: departureBoardOptions.services[3] ? null : false,
            useBoat: departureBoardOptions.services[4] ? null : false,
          )
          .suppress();
    }

    Future<Iterable<TrafficSituation>?> ts = reseplaneraren.getTrafficSituationsByStopId(stopId).suppress();

    var departures = await departuresRequest;

    var result = departures.toList();

    // Workaround for bug in API where some departures after midnight are missing when direction is set.
    if (direction != null &&
        (departures.length < 20 || (dateTime ?? DateTime.now()).day != departures.last.dateTime.day) &&
        !secondPass) {
      var departuresAfterMidnight = await reseplaneraren
          .getDepartureBoard(
            stopId,
            dateTime: (dateTime ?? DateTime.now()).startOfNextDay(),
            direction: direction.id,
            timeSpan: timeSpan,
            useTram: departureBoardOptions.services[0] ? null : false,
            useBus: departureBoardOptions.services[1] ? null : false,
            useVas: departureBoardOptions.services[2] ? null : false,
            useRegTrain: departureBoardOptions.services[3] ? null : false,
            useLDTrain: departureBoardOptions.services[3] ? null : false,
            useBoat: departureBoardOptions.services[4] ? null : false,
          )
          .suppress();

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

    if (departureBoardOptions.includeArrivals) {
      var arrivals = await arrivalsRequest;

      if (arrivals != null) {
        arrivals = arrivals.where((a) =>
            !result.any((d) => d.journeyId == a.journeyId) &&
            (result.isEmpty || a.dateTime.isBefore(result.last.dateTime)) &&
            !(dateTime == null && a.dateTime.isBefore(DateTime.now())));
        result.insertAll(0, arrivals);
      }
    }

    // If the next 20 departures does not include all departures within the next 15 minutes.
    if (result.isNotEmpty &&
        result.length >= 20 &&
        result.last.dateTime.isBefore((dateTime ?? DateTime.now()).add(const Duration(minutes: 15))) &&
        !secondPass) {
      getDepartureBoard(streamController, stopId, dateTime, departureBoardOptions, direction, lat, long,
          timeSpan: 15, secondPass: true, ignoreError: ignoreError);
      if (addOnlyOnce) return;
    }

    var notes = <TS>[];

    if (result.any((d) => isTrainType(d.type) && !d.arrival)) {
      await _addTrainInfo(result, departureBoardOptions, direction, notes, long, lat, dateTime, stopId);
    }

    result.sort((a, b) {
      int cmp = a.getDateTime().compareTo(b.getDateTime());
      if (cmp != 0) return cmp;
      cmp = a.dateTime.compareTo(b.dateTime);
      if (cmp != 0) return cmp;
      if (a.arrival != b.arrival) return a.arrival ? -1 : 1;
      return a.journeyId.compareTo(b.journeyId);
    });

    var filteredTs = (await ts)?.where((ts) => isPresent(ts.startTime, ts.endTime, dateTime ?? DateTime.now(),
        result.lastOrNull?.getDateTime() ?? dateTime ?? DateTime.now()));

    if (direction != null) {
      filteredTs = filteredTs?.where((ts) => ts.affectedLines
          .map((line) => line.gid)
          .toSet()
          .intersection(result.map((departure) => lineIdFromJourneyId(departure.journeyId)).toSet())
          .isNotEmpty);
    }

    filteredTs = filteredTs?.sortTs(dateTime ?? DateTime.now());

    streamController.add(DepartureBoardWithTrafficSituations(result, (filteredTs ?? []).cast<TS>().followedBy(notes)));
  } catch (error) {
    if (ignoreError) return;
    streamController.addError(error);
  }
}

Future<void> _addTrainInfo(List<Departure> result, DepartureBoardOptions departureBoardOptions, StopLocation? direction,
    List<TS> notes, long, double lat, DateTime? dateTime, int stopId) async {
  var trainDeparturesRequest = trafikverket.getTrainStationBoard(result);
  var trainArrivalsRequest = departureBoardOptions.includeArrivals && direction == null
      ? trafikverket.getTrainStationBoard(result, arrival: true)
      : null;

  var trainActivities = (await trainDeparturesRequest)?.followedBy(await trainArrivalsRequest ?? []);

  if (trainActivities == null) {
    notes.add(Note(0, 'low', 'Kunde inte hämta information från Trafikverket'));
    return;
  }

  String? locationSignature = trainActivities.isNotEmpty
      ? trainActivities.first.locationSignature
      : await trafikverket.getTrainStationFromLocation(long, lat);
  if (locationSignature == null) return;

  var lateTrainsRequest =
      trainActivities.isNotEmpty ? trafikverket.getLateTrains(locationSignature, dateTime) : null;

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

    Future<Iterable<Departure>?>? lateDepartureBoardRequest;
    if (lateDepartures.isNotEmpty) {
      lateDepartureBoardRequest = reseplaneraren
          .getDepartureBoard(stopId,
              dateTime: lateDepartures.first.advertisedTimeAtLocation,
              timeSpan: lateDepartures.last.advertisedTimeAtLocation
                  .difference(lateDepartures.first.advertisedTimeAtLocation)
                  .inMinutes,
              direction: direction?.id,
              useBus: false,
              useTram: false,
              useBoat: false)
          .suppress();
    }

    Future<Iterable<Departure>?>? lateArrivalBoardRequest;
    if (lateArrivals.isNotEmpty && departureBoardOptions.includeArrivals && direction == null) {
      lateArrivalBoardRequest = reseplaneraren
          .getArrivalBoard(stopId,
              dateTime: lateArrivals.first.advertisedTimeAtLocation,
              timeSpan: lateArrivals.last.advertisedTimeAtLocation
                  .difference(lateArrivals.first.advertisedTimeAtLocation)
                  .inMinutes,
              useBus: false,
              useTram: false,
              useBoat: false)
          .suppress();
    }

    var lateDepartureBoard = await lateDepartureBoardRequest;
    if (lateDepartureBoard != null) {
      for (TrainAnnouncement lateDeparture in lateDepartures) {
        var missingDeparture = lateDepartureBoard.firstWhereOrNull((d) =>
            d.journeyNumber == lateDeparture.advertisedTrainIdent &&
            d.dateTime.isAtSameMomentAs(lateDeparture.advertisedTimeAtLocation) &&
            isTrainType(d.type));
        if (missingDeparture != null &&
            !result.any((d) =>
                d.journeyNumber == lateDeparture.advertisedTrainIdent &&
                d.dateTime.isAtSameMomentAs(lateDeparture.advertisedTimeAtLocation) &&
                isTrainType(d.type))) {
          result.add(missingDeparture);
          lateTrainActivities.add(lateDeparture);
        }
      }
    }

    var lateArrivalBoard = await lateArrivalBoardRequest;
    if (lateArrivalBoard != null) {
      for (TrainAnnouncement lateArrival in lateArrivals) {
        var missingArrival = lateArrivalBoard.firstWhereOrNull((a) =>
            a.journeyNumber == lateArrival.advertisedTrainIdent &&
            a.dateTime.isAtSameMomentAs(lateArrival.advertisedTimeAtLocation) &&
            isTrainType(a.type));
        if (missingArrival != null &&
            !result.any((d) => d.journeyNumber == lateArrival.advertisedTrainIdent && isTrainType(d.type))) {
          result.add(missingArrival);
          lateTrainActivities.add(lateArrival);
        }
      }
    }

    trainActivities = trainActivities.followedBy(lateTrainActivities);
  }

  for (TrainAnnouncement activity in trainActivities) {
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

    if (activity.deviation.isNotEmpty) result[i].deviation = activity.deviation;

    if (activity.timeAtLocation == null && (result[i].rtDateTime?.isBefore(DateTime.now()) ?? false)) {
      result[i].state = DepartureState.atStation;
    }

    setDepartureState(activity, result[i]);

    if (activity.timeAtLocation != null &&
        activity.activityType == 'Avgang' &&
        (result[i].rtDateTime?.isAfter(DateTime.now().subtract(const Duration(minutes: 15))) ?? false)) {
      result[i].state = DepartureState.departed;
    }
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
                          constraints: const BoxConstraints(minWidth: 35 + 8),
                          child: simpleTimeWidget(
                              departure.dateTime, getDepartureDelay(departure), departure.cancelled, departure.state,
                              bold: false, multiline: true)),
                      Container(constraints: const BoxConstraints(minWidth: 28), child: getCountdown(departure)),
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
                                        child: highlightFirstPart(departure.getDirection(showOrigin: true),
                                            overflow: TextOverflow.fade)),
                                  ],
                                )
                              : highlightFirstPart(departure.getDirection(), overflow: TextOverflow.fade)),
                      const SizedBox(width: 10),
                      accessibilityIcon(departure.accessibility, departure.rtDateTime,
                          margin: EdgeInsets.fromLTRB(
                              0, 0, departure.track == null ? 0 : (departure.rtTrack == null ? 5 : 10), 0),
                          type: departure.type),
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
