import 'dart:async';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:dotted_line/dotted_line.dart';
import 'package:flutter/material.dart';

import 'extensions.dart';
import 'map_widget.dart';
import 'options_panel.dart';
import 'reseplaneraren.dart';
import 'trafikverket.dart';
import 'trip_detail_widget.dart';
import 'utils.dart';

class TripResultWidget extends StatelessWidget {
  final Location _from;
  final Location _to;
  final DateTime? _dateTime;
  final bool? _searchForArrival;
  final TripOptions _tripOptions;

  Iterable<Trip>? _trips;

  TripResultWidget(this._from, this._to, this._dateTime, this._searchForArrival, this._tripOptions, {Key? key})
      : super(key: key) {
    _updateTrip();
  }

  final StreamController<Iterable<Trip>?> _streamController = StreamController.broadcast();

  Future<void> _handleRefresh() async => _updateTrip();

  @override
  Widget build(BuildContext context) {
    var bgLuminance = Theme.of(context).cardColor.computeLuminance();
    return Scaffold(
        appBar: AppBar(
          title: tripTitle(_from.name, _to.name, via: _tripOptions.viaFieldController.location?.name),
        ),
        backgroundColor: cardBackgroundColor(context),
        body: SystemGestureArea(
          MediaQuery.of(context).systemGestureInsets,
          child: RefreshIndicator(
            onRefresh: () => _handleRefresh(),
            child: StreamBuilder<Iterable<Trip>?>(
              builder: (context, tripList) {
                if (tripList.connectionState == ConnectionState.waiting) return loadingPage();
                if (!tripList.hasData) return ErrorPage(_updateTrip);
                if (tripList.data!.isEmpty) return noDataPage('Inga reseförslag hittades');
                int maxTripTime = _getMaxTripTime(tripList.data!);
                return CustomScrollView(
                  slivers: [
                    SliverSafeArea(
                      sliver: SliverPadding(
                        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 5),
                        sliver: SliverList(
                            delegate: SliverChildBuilderDelegate((context, i) {
                          if (i == tripList.data!.length) {
                            return FutureBuilder(
                                future: _addTrips(
                                    tripList.data!.last.leg.first.origin.dateTime.add(const Duration(minutes: 1))),
                                builder: (context, snapshot) {
                                  return snapshot.connectionState == ConnectionState.waiting
                                      ? Container(
                                          child: loadingPage(), constraints: const BoxConstraints(minHeight: 80))
                                      : Container();
                                });
                          }
                          var trip = tripList.data!.elementAt(i);
                          var tripTime = getTripTime(trip);
                          bool cancelled = trip.leg.any((l) => l.cancelled);
                          List<String> notes = <String>[]
                              .addIf(!trip.travelWarranty, 'Resegaranti gäller ej för denna resa')
                              .addIf(trip.alternative, 'Reseförslaget baseras på aktuell trafiksituation');
                          List<String> warnings = <String>[]
                              .addIf(!cancelled && !_isValidTrip(trip), 'Risk för att missa anslutning')
                              .addIf(
                                  cancelled,
                                  trip.leg
                                          .where((l) => l.cancelled)
                                          .map((l) =>
                                              isTrainType(l.type) ? '${l.name} ${l.sname}' : l.name.uncapitalize())
                                          .joinNaturally()
                                          .capitalize() +
                                      ' är inställd');
                          return Card(
                              margin: const EdgeInsets.all(5),
                              child: InkWell(
                                onTap: () async {
                                  await Navigator.push(context, MaterialPageRoute(builder: (context) {
                                    return TripDetailWidget(trip, _tripOptions.changeMarginOptions);
                                  }));
                                },
                                onLongPress: () async {
                                  await Navigator.push<MapWidget>(context, MaterialPageRoute(builder: (context) {
                                    return MapWidget(trip.leg
                                        .map((l) => l.journeyDetailRef == null
                                            ? MapJourney(
                                                walk: true, geometry: l.cachedGeometry, geometryRef: l.geometryRef!)
                                            : MapJourney(
                                                journeyDetailRef: JourneyDetailRef.fromLeg(l),
                                                journeyPart:
                                                    IdxJourneyPart(l.origin.routeIdx!, l.destination.routeIdx!)))
                                        .toList(growable: false));
                                  }));
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    _legBar(trip, bgLuminance, maxTripTime, tripTime.inMinutes, context),
                                    const SizedBox(height: 8),
                                    Row(children: [
                                      Container(
                                        constraints: const BoxConstraints(minWidth: 56),
                                        child: Text(
                                            trip.leg.first.origin.dateTime.time() +
                                                getDelayString(getTripLocationDelay(trip.leg.first.origin)),
                                            style: trip.leg.first.origin.cancelled ? cancelledTextStyle : null),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Wrap(
                                            spacing: 12,
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            children: <Widget>[
                                              TripTimeWidget(
                                                  tripTime, trip.leg.firstWhereOrNull((l) => l.type != 'WALK'))
                                            ]
                                                .insertIf(_anyNote(trip), 0, _getNotesIcon(trip))
                                                .insertIf(cancelled, 0,
                                                    const Text('Inställd', style: TextStyle(color: Colors.red)))
                                                .addIf(
                                                    trip.leg.any((l) =>
                                                        (l.origin.rtDateTime ?? l.destination.rtDateTime) != null &&
                                                        l.type != 'WALK' &&
                                                        l.accessibility == null),
                                                    const Icon(Icons.not_accessible))),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                          trip.leg.last.destination.dateTime.time() +
                                              getDelayString(getTripLocationDelay(trip.leg.last.destination)),
                                          style: trip.leg.last.destination.cancelled ? cancelledTextStyle : null)
                                    ]),
                                    if (notes.isNotEmpty || warnings.isNotEmpty) const SizedBox(height: 8),
                                    Wrap(
                                        children: [
                                      warnings.map<Widget>((msg) => iconAndText(Icons.warning, msg,
                                          iconColor: Colors.red, textColor: Theme.of(context).hintColor)),
                                      notes.map<Widget>(
                                          (msg) => Text(msg, style: TextStyle(color: Theme.of(context).hintColor)))
                                    ].expand((x) => x).toList(growable: false))
                                  ]),
                                ),
                              ));
                        }, childCount: tripList.data!.length + 1)),
                      ),
                    )
                  ],
                );
              },
              stream: _streamController.stream,
            ),
          ),
        ));
  }

  Future<Iterable<Trip>> _getTrip(DateTime? dateTime, {bool addMore = false, bool refresh = false}) async {
    Location? from = _from, to = _to;

    if (_from is CurrentLocation) {
      var currentLocation = (_from as CurrentLocation);
      from = addMore ? currentLocation.cachedLocation : await currentLocation.location(forceRefresh: refresh);
    }
    if (_to is CurrentLocation) {
      var currentLocation = (_to as CurrentLocation);
      to = addMore ? currentLocation.cachedLocation : await currentLocation.location(forceRefresh: refresh);
    }

    if (from == null || to == null) return Future.error(NoLocationError());

    var trips = await reseplaneraren.getTrip(
      originId: from is StopLocation ? from.id : null,
      destId: to is StopLocation ? to.id : null,
      originCoordLat: from is StopLocation ? null : from.lat,
      originCoordLong: from is StopLocation ? null : from.lon,
      originCoordName: from is StopLocation ? null : from.name,
      destCoordLat: to is StopLocation ? null : to.lat,
      destCoordLong: to is StopLocation ? null : to.lon,
      destCoordName: to is StopLocation ? null : to.name,
      dateTime: dateTime,
      additionalChangeTime: _tripOptions.changeMarginMinutes,
      wheelChairSpace: _tripOptions.wheelchair ? true : null,
      rampOrLift: _tripOptions.wheelchair ? true : null,
      useTram: !_tripOptions.services[0] ? false : null,
      useBus: !_tripOptions.services[1] ? false : null,
      useVas: !_tripOptions.services[2] ? false : null,
      useRegTrain: !_tripOptions.services[3] ? false : null,
      useLDTrain: !_tripOptions.services[3] ? false : null,
      useBoat: !_tripOptions.services[4] ? false : null,
      viaId: _tripOptions.via?.id,
      needGeo: true,
      searchForArrival: addMore ? null : _searchForArrival,
    );

    if (trips != null && trips.any((t) => t.leg.any((l) => isTrainType(l.type)))) {
      trips = trips.toList();
      var trainLegs = trips.expand((t) => t.leg).where((l) => isTrainType(l.type));
      var trainActivities = await trafikverket.getTrainTrips(
          trainLegs.map((l) => TrainTripRequest(l.journeyNumber!, l.origin.dateTime, l.destination.dateTime)).toSet());

      for (TrainAnnouncement activity in trainActivities ?? []) {
        if (activity.activityType == 'Ankomst') {
          var legs = trainLegs.where((l) =>
              l.journeyNumber == activity.advertisedTrainIdent &&
              l.destination.dateTime.isAtSameMomentAs(activity.advertisedTimeAtLocation));
          for (var leg in legs) {
            leg.destination.rtDateTime = activity.timeAtLocation ??
                activity.estimatedTimeAtLocation ??
                activity.plannedEstimatedTimeAtLocation ??
                activity.advertisedTimeAtLocation;
            leg.destination.track = activity.trackAtLocation;
            leg.destination.cancelled |= activity.canceled;
          }
        } else {
          var legs = trainLegs.where((l) =>
              l.journeyNumber == activity.advertisedTrainIdent &&
              l.origin.dateTime.isAtSameMomentAs(activity.advertisedTimeAtLocation));
          for (var leg in legs) {
            leg.origin.rtDateTime = activity.timeAtLocation ??
                activity.estimatedTimeAtLocation ??
                activity.plannedEstimatedTimeAtLocation ??
                activity.advertisedTimeAtLocation;
            leg.origin.track = activity.trackAtLocation;
            leg.origin.cancelled |= activity.canceled;
            if (activity.deviation.isNotEmpty) leg.direction = '${leg.direction}, ${activity.deviation.join(', ')}';
          }
        }
      }
    }

    return trips;
  }

  Future<void> _updateTrip() async {
    _trips = await _getTrip(_dateTime);
    _streamController.add(_trips);
  }

  Future<void> _addTrips(DateTime dateTime) async {
    var moreTrips = await _getTrip(dateTime, addMore: true).suppress();
    if (moreTrips == null || moreTrips.isEmpty) return;
    _trips = _trips?.followedBy(moreTrips);
    _streamController.add(_trips);
  }

  Widget _legBar(Trip trip, double bgLuminance, int maxTripTime, int tripTime, BuildContext context) {
    var children = <Widget>[];
    if (trip.leg.isEmpty) return Container();

    int minutes = 0;
    DateTime startTime = trip.leg.first.origin.getDateTime();
    int flex;

    Leg? before;

    for (var leg in trip.leg) {
      if (leg.type == 'WALK' && leg.origin.name == leg.destination.name) continue;
      if (leg.type == 'WALK' && before?.type == 'WALK') continue;

      flex = leg.origin.getDateTime().difference(startTime).inMinutes - minutes;
      if (flex > 0) {
        minutes += flex;
        children.add(Expanded(flex: flex, child: Container()));
      }

      flex = leg.destination.getDateTime().difference(startTime).inMinutes - minutes;
      if (flex <= 0) flex = 1;
      minutes += flex;

      children.add(Expanded(
          flex: flex,
          child: leg.type != 'WALK'
              ? _lineBox(leg, bgLuminance, context)
              : Stack(
                  alignment: Alignment.bottomCenter,
                  children: [const Icon(Icons.directions_walk), DottedLine(dashColor: Theme.of(context).hintColor)])));

      before = leg;
    }

    children.add(Expanded(flex: maxTripTime - tripTime, child: Container()));

    return Row(children: children);
  }

  Widget _lineBox(Leg leg, double bgLuminance, BuildContext context) {
    BoxDecoration decoration =
        lineBoxDecoration(leg.bgColor ?? Colors.black, leg.fgColor ?? Colors.white, bgLuminance, context);
    if (leg.cancelled) decoration = decoration.copyWith(border: Border.all(color: Colors.red, width: 4));
    return PhysicalModel(
      elevation: 1.5,
      color: leg.bgColor ?? Colors.black,
      borderRadius: BorderRadius.circular(3),
      child: Container(
          decoration: decoration,
          height: 26,
          child: Center(
              child: Text(leg.sname ?? leg.name,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: leg.cancelled ? Colors.red : leg.fgColor,
                      fontWeight: FontWeight.bold,
                      overflow: TextOverflow.ellipsis,
                      decoration: leg.cancelled ? TextDecoration.lineThrough : null)))),
    );
  }

  int _getMaxTripTime(Iterable<Trip> trips) {
    return trips.map((trip) => getTripTime(trip).inMinutes).reduce(max);
  }

  bool _anyNote(Trip trip) {
    return trip.leg
        .any((leg) => leg.notes.isNotEmpty || leg.origin.notes.isNotEmpty || leg.destination.notes.isNotEmpty);
  }

  bool _noteOfSeverity(Trip trip, String severity) {
    return trip.leg.any((leg) =>
        leg.notes.any((n) => n.severity == severity) ||
        leg.origin.notes.any((n) => n.severity == severity) ||
        leg.destination.notes.any((n) => n.severity == severity));
  }

  Widget _getNotesIcon(Trip trip) {
    if (_noteOfSeverity(trip, 'high')) return getNoteIcon('high');
    if (_noteOfSeverity(trip, 'normal')) return getNoteIcon('normal');
    return getNoteIcon('low');
  }

  bool _isValidTrip(Trip trip) {
    if (!trip.valid) return false;

    // Check walks between stops
    for (int i = 0; i < trip.leg.length; i++) {
      var leg = trip.leg.elementAt(i);
      if (leg.type == 'WALK' && leg.origin.name != leg.destination.name) {
        Leg? before = trip.leg.tryElementAt(i - 1);
        Leg? after = nextLeg(trip.leg, i);
        if (before == null || after == null) continue;
        if (after.origin.getDateTime().difference(before.destination.getDateTime()) < const Duration(minutes: 5)) {
          return false;
        }
      }
    }

    // Check change times
    Leg? before;
    for (var leg in trip.leg) {
      if (leg.type == 'WALK') continue;
      if (before != null &&
          leg.origin.getDateTime().difference(before.destination.getDateTime()) <=
              Duration(minutes: (_tripOptions.changeMarginOptions.minutes ?? 5) ~/ 2)) return false;
      before = leg;
    }

    return true;
  }
}

class TripTimeWidget extends StatefulWidget {
  final Duration _tripTime;
  final Leg? _leg;

  const TripTimeWidget(this._tripTime, this._leg, {Key? key}) : super(key: key);

  @override
  State<TripTimeWidget> createState() => _TripTimeWidgetState();
}

class _TripTimeWidgetState extends State<TripTimeWidget> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.access_time),
      const SizedBox(width: 5),
      highlightFirstPart(getDurationString(widget._tripTime) +
          getTripCountdown(widget._leg?.cancelled == true ? null : widget._leg?.origin.getDateTime())),
    ]);
  }
}
