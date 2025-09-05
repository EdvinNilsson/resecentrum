import 'dart:async';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:diffutil_sliverlist/diffutil_sliverlist.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:rxdart/subjects.dart';

import 'extensions.dart';
import 'journey_detail_widget.dart';
import 'main.dart';
import 'map_widget.dart';
import 'network/planera_resa.dart';
import 'network/traffic_situations.dart';
import 'network/trafikverket.dart';
import 'network/vehicle_positions.dart';
import 'options_panel.dart';
import 'utils.dart';

class DepartureBoardResultWidget extends StatefulWidget {
  final Location _location;
  final StopLocation? _direction;
  final DateTime? _initialDateTime;
  final DepartureBoardOptions _departureBoardOptions;
  final DepartureBoardState _state = DepartureBoardState();

  DepartureBoardResultWidget(this._location, this._initialDateTime, this._departureBoardOptions,
      {StopLocation? direction, super.key})
      : _direction = direction;

  @override
  State<DepartureBoardResultWidget> createState() => _DepartureBoardResultWidgetState();
}

class _DepartureBoardResultWidgetState extends State<DepartureBoardResultWidget> with WidgetsBindingObserver {
  Timer? _timer;
  DateTime? _dateTime;
  final GlobalKey<RefreshIndicatorState> _refreshKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dateTime = widget._initialDateTime;
    _initTimer(updateIntermittently: false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _departureStreamController.close();
    _trafficSituationSubject.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _timer?.isActive == true) {
      _timer?.cancel();
    } else if (state == AppLifecycleState.resumed &&
        _timer?.isActive == false &&
        ModalRoute.of(context)?.isCurrent == true) {
      _initTimer();
    }
  }

  void _initTimer({bool updateIntermittently = true}) {
    _timer?.cancel();
    _timer =
        Timer.periodic(const Duration(seconds: 15), (_) => _updateDepartureBoard(addOnlyOnce: true, ignoreError: true));
    if (updateIntermittently) _updateDepartureBoard(addOnlyOnce: true, ignoreError: true);
  }

  final StreamController<Iterable<Departure>> _departureStreamController = StreamController.broadcast();
  final BehaviorSubject<Iterable<TS>> _trafficSituationSubject = BehaviorSubject();

  Future<void> _handleRefresh() async => _updateDepartureBoard(addOnlyOnce: true, ignoreError: true);

  @override
  Widget build(BuildContext context) {
    _updateDepartureBoard();
    return Scaffold(
        appBar: AppBar(
            title: StreamBuilder(stream: _departureStreamController.stream, builder: (context, snapshot) => _title()),
            actions: <Widget>[
              PopupMenuButton(
                  onSelected: (action) {
                    switch (action) {
                      case MenuAction.addToHomeScreen:
                        return _createShortcut();
                      case MenuAction.showEarlierDepartures:
                        var duration =
                            widget._state.departureFrequency != null ? 5.0 / widget._state.departureFrequency! : 60;
                        _dateTime = (_dateTime ?? DateTime.now()).subtract(Duration(minutes: duration.ceil()));
                        _updateDepartureBoard(addOnlyOnce: true, ignoreError: true);
                        _refreshKey.currentState?.show();
                        break;
                      case MenuAction.showMoreDepartures:
                        if (widget._state.timeSpan != null && widget._state.timeSpan != 1439) {
                          widget._state.timeSpan = min(widget._state.timeSpan! + 15, 1439);
                        } else {
                          widget._state.limit = (widget._state.limit ?? 20) + 20;
                          widget._state.target = widget._state.limit;
                        }
                        _updateDepartureBoard(addOnlyOnce: true, ignoreError: true);
                        _refreshKey.currentState?.show();
                        break;
                      default:
                    }
                  },
                  itemBuilder: (BuildContext context) => [
                        if (supportShortcuts)
                          const PopupMenuItem(
                              value: MenuAction.addToHomeScreen,
                              child: ListTile(
                                  leading: Icon(Icons.add_to_home_screen),
                                  title: Text('Skapa genväg'),
                                  visualDensity: VisualDensity.compact)),
                        const PopupMenuItem(
                            value: MenuAction.showEarlierDepartures,
                            child: ListTile(
                                leading: Icon(Icons.history),
                                title: Text('Visa tidigare avgångar'),
                                visualDensity: VisualDensity.compact)),
                        const PopupMenuItem(
                            value: MenuAction.showMoreDepartures,
                            child: ListTile(
                                leading: Icon(Icons.update),
                                title: Text('Visa fler avgångar'),
                                visualDensity: VisualDensity.compact))
                      ])
            ]),
        backgroundColor: cardBackgroundColor(context),
        body: SystemGestureArea(
          MediaQuery.of(context).systemGestureInsets,
          child: RefreshIndicator(
            key: _refreshKey,
            onRefresh: () => _handleRefresh(),
            child: StreamBuilder<Iterable<Departure>>(
                builder: (context, departureBoard) {
                  if (departureBoard.connectionState == ConnectionState.waiting) return loadingPage();
                  if (!departureBoard.hasData) return ErrorPage(_updateDepartureBoard, error: departureBoard.error);
                  if (departureBoard.data!.isEmpty) return noDataPage('Inga avgångar hittades');
                  var bgColor = Theme.of(context).cardColor;
                  return CustomScrollView(slivers: [
                    if (_dateTime != null && departureBoard.data!.isNotEmpty) dateBar(_dateTime!),
                    SliverSafeArea(
                      sliver: departureBoardList(departureBoard.data!, bgColor,
                          tsStream: _trafficSituationSubject.stream, onTap: (context, departure) {
                        _timer?.cancel();
                        Navigator.push(context, MaterialPageRoute(builder: (context) {
                          return JourneyDetailsWidget(DepartureDetailsRef.fromDeparture(departure));
                        })).then((_) => _initTimer());
                      }, onLongPress: (context, departure) {
                        Navigator.push<MapWidget>(context, MaterialPageRoute(builder: (context) {
                          _timer?.cancel();
                          return MapWidget([
                            MapJourney(
                                journeyDetailsRef: DepartureDetailsRef.fromDeparture(departure),
                                refStopPointGid: departure.stopPoint.gid,
                                focusJid: departure.serviceJourney.gid,
                                focusTrainNumber: departure.isTrain ? departure.trainNumber : null)
                          ]);
                        })).then((_) => _initTimer());
                      }),
                      bottom: false,
                    ),
                    trafficSituationWidget(_trafficSituationSubject.stream)
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

    return widget._direction == null
        ? text
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            text,
            Text('mot ${widget._direction!.name.firstPart()}',
                overflow: TextOverflow.fade, style: const TextStyle(fontSize: 14, color: Colors.white70))
          ]);
  }

  Future<void> _updateDepartureBoard({bool addOnlyOnce = false, bool ignoreError = false}) async {
    String stopAreaGid;
    if (widget._location is CurrentLocation) {
      try {
        StopLocation? location = await (widget._location as CurrentLocation)
            .location(onlyStops: true, forceRefresh: true, requestPermissions: !ignoreError) as StopLocation?;
        if (location == null) throw NoLocationError();
        stopAreaGid = location.gid;
      } catch (e) {
        return _departureStreamController.addError(e);
      }
    } else {
      stopAreaGid = (widget._location as StopLocation).gid;
    }
    await getDepartureBoard(_departureStreamController, stopAreaGid, _dateTime, widget._departureBoardOptions,
        widget._direction, widget._location.position, widget._state,
        addOnlyOnce: addOnlyOnce, ignoreError: ignoreError, tsSubject: _trafficSituationSubject);
  }

  void _createShortcut() {
    Map<String, String> params = {};

    if (widget._location is CurrentLocation) {
      params['currentLocation'] = 'true';
    } else if (widget._location is StopLocation) {
      params['id'] = (widget._location as StopLocation).gid;
      params['name'] = widget._location.name;
      params['lat'] = widget._location.position.latitude.toString();
      params['lon'] = widget._location.position.longitude.toString();
    }

    if (widget._direction != null) {
      params['dirId'] = widget._direction!.gid;
      params['dirName'] = widget._direction!.name;
      params['dirLat'] = widget._direction!.position.latitude.toString();
      params['dirLon'] = widget._direction!.position.longitude.toString();
    }

    if (widget._departureBoardOptions.includeArrivals) {
      params['includeArrivals'] = 'true';
    }

    var uri = Uri(scheme: 'resecentrum', host: 'board', queryParameters: params);

    var icon = widget._location is StopLocation ? getStopIconString(widget._location as StopLocation) : 'my_location';

    var summary = widget._departureBoardOptions.summary;

    createShortcut(context, uri.toString(), widget._location.name.firstPart(), icon, summary);
  }
}

Future<void> getDepartureBoard(
    StreamController streamController,
    String stopAreaGid,
    DateTime? dateTime,
    DepartureBoardOptions departureBoardOptions,
    StopLocation? direction,
    LatLng stopPosition,
    DepartureBoardState state,
    {bool addOnlyOnce = false,
    bool secondPass = false,
    bool ignoreError = false,
    BehaviorSubject? tsSubject}) async {
  try {
    var departuresRequest = PlaneraResa.departures(stopAreaGid,
        startDateTime: dateTime, timeSpanInMinutes: state.timeSpan, limit: state.limit, directionGid: direction?.gid);

    Future<Iterable<Departure>?>? arrivalsRequest;
    if (departureBoardOptions.includeArrivals && direction == null) {
      arrivalsRequest = PlaneraResa.arrivals(stopAreaGid,
              startDateTime: dateTime, timeSpanInMinutes: state.timeSpan, limit: state.limit)
          .suppress();
    }

    Future<Iterable<TrafficSituation>?>? ts;
    if (tsSubject != null && !secondPass) {
      ts = TrafficSituations.getTrafficSituationsForStopArea(stopAreaGid).suppress();
    }

    var departures = await departuresRequest;

    var result = departures.toList();

    var needDepartedCheck = result.where((d) {
      var timeLeft = d.time.difference(DateTime.now());
      var minutesLeft = timeLeft.minutesRounded();
      return !d.isTrain && d.estimatedTime == null && minutesLeft >= -1 && minutesLeft <= 5 && !d.isCancelled;
    });

    if (needDepartedCheck.isNotEmpty) {
      Iterable<VehiclePosition>? positions = await VehiclePositions.getPositions(
          needDepartedCheck.map((d) => d.serviceJourney.gid).toList(growable: false));
      for (VehiclePosition vehiclePosition in positions ?? []) {
        var departure = needDepartedCheck.firstWhere((d) => d.serviceJourney.gid == vehiclePosition.journeyId);
        if (hasDeparted(vehiclePosition, departure.stopPoint.position)) departure.state = DepartureState.departed;
      }
    }

    var lastPlannedTime = maxBy(result, (departure) => departure.plannedTime)?.plannedTime;
    var lastEstimatedTime = maxBy(result, (departure) => departure.time)?.time;

    if (departureBoardOptions.includeArrivals) {
      var arrivals = await arrivalsRequest;

      if (arrivals != null) {
        arrivals = arrivals.where((a) =>
            !result.any((d) => d.detailsReference == a.detailsReference) &&
            (result.length >= (state.limit ?? 20)).implies(lastPlannedTime != null &&
                lastEstimatedTime != null &&
                a.plannedTime.isBefore(lastPlannedTime) &&
                a.time.isBefore(lastEstimatedTime)) &&
            !(dateTime == null && a.plannedTime.isBefore(DateTime.now())));
        result.addAll(arrivals);
      }
    }

    var lastPass = true;
    var secondPassDone = false;

    // If the next 20 departures does not include all departures within the next 15 minutes.
    if (result.length >= 20 &&
        lastPlannedTime!.isBefore((dateTime ?? DateTime.now()).add(const Duration(minutes: 15))) &&
        state.timeSpan != 15 &&
        !secondPass) {
      state.timeSpan = 15;
      state.limit = 10000;
      getDepartureBoard(streamController, stopAreaGid, dateTime, departureBoardOptions, direction, stopPosition, state,
              secondPass: true, ignoreError: ignoreError, tsSubject: tsSubject)
          .whenComplete(() => secondPassDone = true);
      if (addOnlyOnce) return;
      lastPass = false;
    }

    if (result.length < (state.target ?? 20) && state.timeSpan != 1439 && !secondPass) {
      state.timeSpan = 1439;
      state.limit = state.target;
      getDepartureBoard(streamController, stopAreaGid, dateTime, departureBoardOptions, direction, stopPosition, state,
              secondPass: true, ignoreError: ignoreError, tsSubject: tsSubject)
          .whenComplete(() => secondPassDone = true);
      if (addOnlyOnce || result.isEmpty) return;
      lastPass = false;
    }

    // Workaround for bug in API where some departures after midnight are missing when direction is set.
    if (lastPass && direction != null) {
      DateTime? startDateTime;
      if (departures.length < 20 || (dateTime ?? DateTime.now()).day != departures.last.plannedTime.day) {
        startDateTime = (dateTime ?? DateTime.now()).startOfNextDay();
      } else if (!departures.last.plannedTime.isSameTransportDayAs(dateTime ?? DateTime.now())) {
        startDateTime = dateTime ?? DateTime.now();
      }

      if (startDateTime != null) {
        var departuresAfterMidnight = await PlaneraResa.departures(stopAreaGid,
                startDateTime: startDateTime,
                directionGid: direction.gid,
                limit: state.limit ?? 20,
                timeSpanInMinutes: state.timeSpan?.clamp(0, 720))
            .suppress();

        result = departures
            .followedBy(departuresAfterMidnight
                    ?.where((d) => !result.any((e) => e.serviceJourney.gid == d.serviceJourney.gid)) ??
                [])
            .toList();
      }
    }

    var notes = <TS>[];

    if (result.any((d) => d.isTrain)) {
      await _addTrainInfo(result, departureBoardOptions, direction, notes, stopPosition, dateTime, stopAreaGid);
    }

    result.sort((a, b) {
      int cmp = a.time.compareTo(b.time);
      if (cmp != 0) return cmp;
      cmp = a.plannedTime.compareTo(b.plannedTime);
      if (cmp != 0) return cmp;
      if (a.arrival != b.arrival) return a.arrival ? -1 : 1;
      return a.serviceJourney.gid.compareTo(b.serviceJourney.gid);
    });

    if (result.length > 1) {
      var deltaTimes = <int>[];

      var previousDeparture = result.first;
      for (var departure in result.skip(1)) {
        var deltaTime = departure.time.difference(previousDeparture.time).inMinutes;
        deltaTimes.add(deltaTime);
        previousDeparture = departure;
      }

      deltaTimes.sort();
      var avgPeriod = truncatedMean(deltaTimes, 0.1);

      state.departureFrequency = 1.0 / avgPeriod;
    }

    if (!secondPassDone) streamController.add(result);

    if (tsSubject != null) {
      if (!secondPass) state.ts = await ts;

      var filteredTs = state.ts?.where((ts) => isPresent(
          ts.startTime, ts.endTime, dateTime ?? DateTime.now(), result.lastOrNull?.time ?? dateTime ?? DateTime.now()));

      if (direction != null) {
        filteredTs = filteredTs?.where((ts) => ts.affectedLines
            .map((line) => line.gid)
            .toSet()
            .intersection(result.map((departure) => lineIdFromJourneyId(departure.serviceJourney.gid)).toSet())
            .isNotEmpty);
      }

      filteredTs = filteredTs?.sortTs(dateTime ?? DateTime.now());
      tsSubject.add((filteredTs ?? []).cast<TS>().followedBy(notes));
    }
  } catch (error, stackTrace) {
    if (kDebugMode) {
      print(error);
      print(stackTrace);
    }
    if (ignoreError) return;
    streamController.addError(error);
  }
}

Future<void> _addTrainInfo(List<Departure> result, DepartureBoardOptions departureBoardOptions, StopLocation? direction,
    List<TS> notes, LatLng position, DateTime? dateTime, String stopAreaGid) async {
  var trainDeparturesRequest = Trafikverket.getTrainStationBoard(result);
  var trainArrivalsRequest = departureBoardOptions.includeArrivals && direction == null
      ? Trafikverket.getTrainStationBoard(result, arrival: true)
      : null;

  var trainActivities = (await trainDeparturesRequest)?.followedBy(await trainArrivalsRequest ?? []);

  if (trainActivities == null) {
    notes.add(Note('Kunde inte hämta information från Trafikverket'));
    return;
  }

  String? locationSignature = trainActivities.firstOrNull?.locationSignature;
  if (!trainActivities.every((train) => train.locationSignature == locationSignature)) locationSignature = null;
  locationSignature ??= await Trafikverket.getTrainStationFromLocation(position);
  if (locationSignature == null) return;

  var lateTrainsRequest = trainActivities.isNotEmpty ? Trafikverket.getLateTrains(locationSignature, dateTime) : null;

  String? directionSignature;
  if (direction != null) {
    directionSignature = await Trafikverket.getTrainStationFromLocation(direction.position);
  }

  var trainStationMessages =
      Trafikverket.getTrainStationMessage(locationSignature, dateTime, result.last.time, directionSignature);

  var lateTrains = await lateTrainsRequest;

  notes.addAll((await trainStationMessages ?? <TrainMessage>[]));

  if (lateTrains != null && lateTrains.isNotEmpty) {
    var lateDepartures = lateTrains.where((t) => t.activityType == 'Avgang');
    var lateArrivals = lateTrains.where((t) => t.activityType == 'Ankomst');

    List<TrainAnnouncement> lateTrainActivities = [];

    Future<Iterable<Departure>?>? lateDepartureBoardRequest;
    if (lateDepartures.isNotEmpty) {
      lateDepartureBoardRequest = PlaneraResa.departures(
        stopAreaGid,
        directionGid: direction?.gid,
        startDateTime: lateDepartures.first.advertisedTimeAtLocation,
        timeSpanInMinutes: lateDepartures.last.advertisedTimeAtLocation
            .difference(lateDepartures.first.advertisedTimeAtLocation)
            .inMinutes,
      ).suppress();
    }

    Future<Iterable<Departure>?>? lateArrivalBoardRequest;
    if (lateArrivals.isNotEmpty && departureBoardOptions.includeArrivals && direction == null) {
      lateArrivalBoardRequest = PlaneraResa.arrivals(
        stopAreaGid,
        startDateTime: lateArrivals.first.advertisedTimeAtLocation,
        timeSpanInMinutes: lateArrivals.last.advertisedTimeAtLocation
            .difference(lateArrivals.first.advertisedTimeAtLocation)
            .inMinutes,
      ).suppress();
    }

    var lateDepartureBoard = await lateDepartureBoardRequest;
    if (lateDepartureBoard != null) {
      for (TrainAnnouncement lateDeparture in lateDepartures) {
        var missingDeparture = lateDepartureBoard.firstWhereOrNull((d) =>
            d.isTrain &&
            d.trainNumber == lateDeparture.advertisedTrainIdent &&
            d.plannedTime.isAtSameMomentAs(lateDeparture.advertisedTimeAtLocation) &&
            lateDeparture.locationSignature == locationSignature);
        if (missingDeparture != null &&
            !result.any((d) =>
                d.isTrain &&
                d.trainNumber == lateDeparture.advertisedTrainIdent &&
                d.plannedTime.isAtSameMomentAs(lateDeparture.advertisedTimeAtLocation))) {
          result.add(missingDeparture);
          lateTrainActivities.add(lateDeparture);
        }
      }
    }

    var lateArrivalBoard = await lateArrivalBoardRequest;
    if (lateArrivalBoard != null) {
      for (TrainAnnouncement lateArrival in lateArrivals) {
        var missingArrival = lateArrivalBoard.firstWhereOrNull((a) =>
            a.isTrain &&
            a.trainNumber == lateArrival.advertisedTrainIdent &&
            a.plannedTime.isAtSameMomentAs(lateArrival.advertisedTimeAtLocation) &&
            lateArrival.locationSignature == locationSignature);
        if (missingArrival != null &&
            !result.any((d) => d.isTrain && d.trainNumber == lateArrival.advertisedTrainIdent)) {
          result.add(missingArrival);
          lateTrainActivities.add(lateArrival);
        }
      }
    }

    trainActivities = trainActivities.followedBy(lateTrainActivities);
  }

  for (TrainAnnouncement activity in trainActivities) {
    int i = result.indexWhere((d) =>
        d.isTrain &&
        d.trainNumber == activity.advertisedTrainIdent &&
        d.plannedTime == activity.advertisedTimeAtLocation &&
        d.arrival == (activity.activityType == 'Ankomst') &&
        activity.locationSignature == locationSignature);
    if (i == -1) continue;
    result[i].estimatedTime = activity.timeAtLocation ??
        activity.estimatedTimeAtLocation ??
        activity.plannedEstimatedTimeAtLocation ??
        activity.advertisedTimeAtLocation;
    result[i].stopPoint.plannedPlatform = activity.trackAtLocation;
    if (activity.deviation.contains('Spårändrat')) result[i].stopPoint.estimatedPlatform = activity.trackAtLocation;
    result[i].isCancelled |= activity.canceled;

    if (activity.deviation.isNotEmpty) result[i].deviation = activity.deviation;

    if (activity.timeAtLocation == null && (result[i].estimatedTime?.isBefore(DateTime.now()) ?? false)) {
      result[i].state = DepartureState.atStation;
    }

    setDepartureState(activity, result[i]);

    if (activity.timeAtLocation != null &&
        activity.activityType == 'Avgang' &&
        (result[i].estimatedTime?.isAfter(DateTime.now().subtract(const Duration(minutes: 15))) ?? false)) {
      result[i].state = DepartureState.departed;
    }
  }
}

Widget departureBoardList(Iterable<Departure> departures, Color bgColor,
    {void Function(BuildContext, Departure)? onTap,
    void Function(BuildContext, Departure)? onLongPress,
    Stream<Iterable<TS>>? tsStream}) {
  if (departures.isEmpty) return SliverFillRemaining(child: noDataPage('Inga avgångar hittades'));
  return SliverPadding(
    padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 3),
    sliver: DiffUtilSliverList<Departure>(
      equalityChecker: (a, b) => a.serviceJourney.gid == b.serviceJourney.gid && a.plannedTime == b.plannedTime,
      items: departures.toList(growable: false),
      builder: (BuildContext context, Departure departure) {
        var lineIcon = StreamBuilder(
            stream: tsStream,
            builder: (context, snapshot) {
              var lineIcon = lineIconFromLine(departure.serviceJourney.line, bgColor, context);
              if (!snapshot.hasData) return lineIcon;

              var trafficSituations = snapshot.data!.whereType<TrafficSituation>().where((ts) =>
                  (ts.affectedLines.any((line) =>
                          line.gid == departure.serviceJourney.line.gid &&
                          ts.affectedStopPoints.any((stopPoint) => stopPoint.gid == departure.stopPoint.gid)) &&
                      !departure.isTrain &&
                      isPresent(ts.startTime, ts.endTime, departure.plannedTime, departure.time)) ||
                  ts.affectedJourneys.any((journey) => journey.gid == departure.serviceJourney.gid));

              if (trafficSituations.isEmpty) return lineIcon;

              var severity = trafficSituations.map((ts) => ts.severity).max;
              var line = departure.serviceJourney.line;

              return addSeverityIcon(lineIcon, severity, context, line, bgColor);
            });

        return Card(
            child: InkWell(
                onTap: onTap != null ? () => onTap(context, departure) : null,
                onLongPress: onLongPress != null ? () => onLongPress(context, departure) : null,
                child: Container(
                    constraints: const BoxConstraints(minHeight: 46),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    child: Row(children: [
                      Container(
                          constraints: const BoxConstraints(minWidth: 35 + 8),
                          child: simpleTimeWidget(
                              departure.plannedTime, departure.delay, departure.isCancelled, departure.state,
                              bold: false, multiline: true)),
                      Container(constraints: const BoxConstraints(minWidth: 28), child: getCountdown(departure)),
                      const SizedBox(width: 8),
                      lineIcon,
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
                      accessibilityIcon(departure.serviceJourney.line.isWheelchairAccessible, departure.estimatedTime,
                          margin: EdgeInsets.only(
                              right: departure.stopPoint.plannedPlatform.isNullOrEmpty
                                  ? 0
                                  : (departure.stopPoint.estimatedPlatform == null ? 5 : 10)),
                          transportMode: departure.serviceJourney.line.transportMode),
                      departure.stopPoint.estimatedPlatform != null
                          ? trackChange(departure.stopPoint.estimatedPlatform!)
                          : Text(departure.stopPoint.plannedPlatform ?? '')
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

StreamBuilder<Iterable<TS>> trafficSituationWidget(Stream<Iterable<TS>> stream) {
  return StreamBuilder<Iterable<TS>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SliverToBoxAdapter(child: loadingPage());
        }
        if (!snapshot.hasData) {
          return SliverToBoxAdapter(child: noDataPage('Kunde inte hämta trafikinformation'));
        }
        return SliverSafeArea(
          sliver: trafficSituationList(snapshot.data!,
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10), showAffectedStop: false),
        );
      });
}

class DepartureBoardState {
  int? timeSpan;
  int? limit;
  Iterable<TrafficSituation>? ts;
  double? departureFrequency;
  int? target;
}
