import 'dart:async';

import 'package:collection/collection.dart';
import 'package:dotted_line/dotted_line.dart';
import 'package:flutter/material.dart';

import 'extensions.dart';
import 'main.dart';
import 'map_widget.dart';
import 'options_panel.dart';
import 'reseplaneraren.dart';
import 'trafikverket.dart';
import 'trip_detail_widget.dart';
import 'utils.dart';

const int longWaitingTime = 90;

class TripResultWidget extends StatelessWidget {
  final Location _from;
  final Location _to;
  final DateTime? _dateTime;
  final bool _searchForArrival;
  final TripOptions _tripOptions;

  Iterable<Trip>? _trips;

  TripResultWidget(this._from, this._to, this._dateTime, this._searchForArrival, this._tripOptions, {Key? key})
      : super(key: key) {
    _updateTrip();
  }

  final StreamController<Iterable<Trip>?> _streamController = StreamController.broadcast();

  Future<void> _handleRefresh() async => _updateTrip(refresh: true);

  @override
  Widget build(BuildContext context) {
    var bgLuminance = Theme.of(context).cardColor.computeLuminance();
    return Scaffold(
        appBar: AppBar(
            title: StreamBuilder(
                stream: _streamController.stream,
                builder: (context, snapshot) {
                  return tripTitle(_from.getName(), _to.getName(), via: _tripOptions.via?.name);
                }),
            actions: supportShortcuts || supportVttogo
                ? <Widget>[
                    PopupMenuButton(
                        onSelected: (selection) async {
                          if (selection == 0) _createShortcut(context);
                          if (selection == 1) buyTicket(context, await _getStopId(_from), await _getStopId(_to));
                        },
                        itemBuilder: (BuildContext context) => [
                              if (supportShortcuts)
                                const PopupMenuItem(
                                  value: 0,
                                  child: ListTile(
                                      leading: Icon(Icons.add_to_home_screen),
                                      title: Text('Skapa genväg'),
                                      visualDensity: VisualDensity.compact),
                                ),
                              if (supportVttogo)
                                const PopupMenuItem(
                                  value: 1,
                                  child: ListTile(
                                      leading: Icon(Icons.confirmation_num),
                                      title: Text('Köp enkelbiljett'),
                                      visualDensity: VisualDensity.compact),
                                )
                            ])
                  ]
                : null),
        backgroundColor: cardBackgroundColor(context),
        body: SystemGestureArea(
          MediaQuery.of(context).systemGestureInsets,
          child: RefreshIndicator(
            onRefresh: () => _handleRefresh(),
            child: StreamBuilder<Iterable<Trip>?>(
              builder: (context, tripList) {
                if (tripList.connectionState == ConnectionState.waiting) return loadingPage();
                if (!tripList.hasData) return ErrorPage(_updateTrip, error: tripList.error);
                if (tripList.data!.isEmpty) return noDataPage('Inga reseförslag hittades');
                int maxTripTime = _getTripTimeWindow(tripList.data!);
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
                                          constraints: const BoxConstraints(minHeight: 80), child: loadingPage())
                                      : Container();
                                });
                          }
                          var trip = tripList.data!.elementAt(i);
                          var tripTime = getTripTime(trip);
                          var replacementBus = trip.leg.where((l) =>
                              l.cancelled &&
                              l.origin.state == DepartureState.replacementBus &&
                              l.destination.state == DepartureState.replacementBus);
                          var partlyCancelled = trip.leg.where((l) => l.origin.cancelled != l.destination.cancelled);
                          var cancelled = trip.leg
                              .where((l) => l.cancelled && !replacementBus.contains(l) && !partlyCancelled.contains(l));
                          List<String> notes = <String>[]
                              .addIf(!trip.travelWarranty, 'Resegaranti gäller ej för denna resa')
                              .addIf(trip.alternative, 'Reseförslaget baseras på aktuell trafiksituation')
                              .addIf(
                                  _getMaxWaitTime(trip) >= longWaitingTime,
                                  'Längre uppehåll vid en hållplats '
                                  '(${getDurationString(Duration(minutes: _getMaxWaitTime(trip)))})');
                          List<String> warnings = <String>[].addIf(
                              cancelled.isEmpty &&
                                  partlyCancelled.isEmpty &&
                                  replacementBus.isEmpty &&
                                  !_isValidTrip(trip),
                              'Risk för att missa anslutning');
                          List<String> cancellations = <String>[]
                              .addIf(
                                  cancelled.isNotEmpty,
                                  cancelled
                                          .map((l) =>
                                              isTrainType(l.type) ? '${l.name} ${l.sname}' : l.name.uncapitalize())
                                          .joinNaturally()
                                          .capitalize() +
                                      (cancelled.length > 1 ? ' är inställda' : ' är inställd'))
                              .addIf(
                                  partlyCancelled.isNotEmpty,
                                  partlyCancelled
                                          .map((l) =>
                                              isTrainType(l.type) ? '${l.name} ${l.sname}' : l.name.uncapitalize())
                                          .joinNaturally()
                                          .capitalize() +
                                      (cancelled.length > 1 ? ' är delvis inställda' : ' är delvis inställd'))
                              .addIf(
                                  replacementBus.isNotEmpty,
                                  replacementBus.map((l) => '${l.name} ${l.sname}').joinNaturally() +
                                      (replacementBus.length > 1 ? ' är ersatta med buss' : ' är ersatt med buss'));
                          return Card(
                              margin: const EdgeInsets.all(5),
                              child: InkWell(
                                onTap: () {
                                  Navigator.push(context, MaterialPageRoute(builder: (context) {
                                    return TripDetailWidget(trip, _tripOptions);
                                  }));
                                },
                                onLongPress: () {
                                  Navigator.push<MapWidget>(context, MaterialPageRoute(builder: (context) {
                                    return MapWidget(trip.leg
                                        .map((l) => l.journeyDetailRef == null
                                            ? MapJourney(
                                                walk: true, geometry: l.cachedGeometry, geometryRef: l.geometryRef!)
                                            : MapJourney(
                                                journeyDetailRef: JourneyDetailRef.fromLeg(l),
                                                journeyPart: JourneyPart(l.origin.routeIdx!, l.destination.routeIdx!)))
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
                                        child: simpleTimeWidget(
                                            trip.leg.first.origin.dateTime,
                                            getTripLocationDelay(trip.leg.first.origin),
                                            trip.leg.first.origin.cancelled,
                                            trip.leg.first.origin.state,
                                            bold: false),
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
                                                .insertIf(cancelled.isNotEmpty || partlyCancelled.isNotEmpty, 0,
                                                    const Text('Inställd', style: TextStyle(color: Colors.red)))
                                                .addIf(
                                                    trip.leg.any((l) =>
                                                        (l.origin.rtDateTime ?? l.destination.rtDateTime) != null &&
                                                        l.type != 'WALK' &&
                                                        l.accessibility == null),
                                                    const Icon(Icons.not_accessible))),
                                      ),
                                      const SizedBox(width: 8),
                                      simpleTimeWidget(
                                          trip.leg.last.destination.dateTime,
                                          getTripLocationDelay(trip.leg.last.destination),
                                          trip.leg.last.destination.cancelled,
                                          trip.leg.last.destination.state,
                                          bold: false)
                                    ]),
                                    if (notes.isNotEmpty || warnings.isNotEmpty) const SizedBox(height: 8),
                                    Wrap(
                                        runSpacing: 5,
                                        children: [
                                          cancellations.map<Widget>((msg) => iconAndText(Icons.cancel, msg,
                                              iconColor: Colors.red, textColor: Theme.of(context).hintColor)),
                                          warnings.map<Widget>((msg) => iconAndText(Icons.warning, msg,
                                              iconColor: Colors.red, textColor: Theme.of(context).hintColor)),
                                          notes.map<Widget>((msg) => iconAndText(Icons.info_outline, msg,
                                              iconColor: Theme.of(context).hintColor,
                                              textColor: Theme.of(context).hintColor))
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
      searchForArrival: _searchForArrival && !addMore ? true : null,
    );

    if (trips.any((t) => t.leg.any((l) => isTrainType(l.type)))) {
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
            if (activity.timeAtLocation != null) leg.destination.rtDateTime = null;
            setDepartureState(activity, leg.destination);
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
            if (activity.timeAtLocation != null) leg.origin.rtDateTime = null;
            setDepartureState(activity, leg.origin);
            if (activity.deviation.isNotEmpty) leg.direction = '${leg.direction}, ${activity.deviation.join(', ')}';
          }
        }
      }
    }

    return trips;
  }

  Future<void> _updateTrip({bool refresh = false}) async {
    try {
      _trips = await _getTrip(_dateTime, refresh: refresh);
      _streamController.add(_trips);
    } catch (error) {
      _streamController.addError(error);
    }
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

      var legWidget = leg.type != 'WALK'
          ? _lineBox(leg, bgLuminance, context)
          : Stack(
              alignment: Alignment.bottomCenter,
              children: [const Icon(Icons.directions_walk), DottedLine(dashColor: Theme.of(context).hintColor)]);

      if (leg.notes.isNotEmpty || leg.origin.notes.isNotEmpty || leg.destination.notes.isNotEmpty) {
        var icon = _getNotesIconLeg(leg);

        if (icon.icon == Icons.info_outline) {
          icon = const Icon(Icons.info, color: Colors.white);
        }

        bool lowContrast = colorDiff(leg.bgColor!, icon.color ?? Theme.of(context).iconTheme.color!) <= 20;

        Widget iconWidget = lowContrast || (icon.icon == Icons.info && Theme.of(context).brightness == Brightness.light)
            ? Stack(alignment: Alignment.center, children: [
                if (lowContrast) Container(decoration: BoxDecoration(color: leg.fgColor), width: 4, height: 8),
                Icon(icon.icon, color: lowContrast ? leg.fgColor : leg.bgColor, size: 18),
                Icon(icon.icon, color: icon.color, size: 16),
              ])
            : Icon(icon.icon, color: icon.color, size: 16);

        legWidget = Stack(children: [
          legWidget,
          Transform.translate(
              offset: const Offset(5, -5), child: Align(alignment: Alignment.topRight, child: iconWidget))
        ]);
      }

      children.add(Expanded(flex: flex, child: legWidget));

      before = leg;
    }

    children.add(Expanded(flex: maxTripTime - tripTime, child: Container()));

    return Row(children: children);
  }

  Widget defaultNote(String msg, BuildContext context) => iconAndText(Icons.info_outline, msg,
      iconColor: Theme.of(context).hintColor, textColor: Theme.of(context).hintColor);

  Widget defaultWarning(String msg, BuildContext context) =>
      iconAndText(Icons.warning, msg, iconColor: Colors.red, textColor: Theme.of(context).hintColor);

  Widget _lineBox(Leg leg, double bgLuminance, BuildContext context) {
    BoxDecoration decoration =
        lineBoxDecoration(leg.bgColor ?? Colors.black, leg.fgColor ?? Colors.white, bgLuminance, context);
    bool replacementBus =
        leg.origin.state == DepartureState.replacementBus && leg.destination.state == DepartureState.replacementBus;
    if (leg.cancelled) {
      decoration =
          decoration.copyWith(border: Border.all(color: replacementBus ? orange(context) : Colors.red, width: 4));
    }
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
                  style: TextStyle(color: leg.fgColor, fontWeight: FontWeight.bold, overflow: TextOverflow.ellipsis)))),
    );
  }

  int _getTripTimeWindow(Iterable<Trip> trips) {
    int maxTripTime = 0;
    for (var trip in trips) {
      int tripTime = getTripTime(trip).inMinutes;
      if (tripTime > maxTripTime && _getMaxWaitTime(trip) <= longWaitingTime) maxTripTime = tripTime;
    }
    return maxTripTime;
  }

  int _getMaxWaitTime(Trip trip) {
    Leg prevLeg = trip.leg.first;
    int maxWaitTime = 0;
    for (var leg in trip.leg.skip(1)) {
      if (leg.type == 'WALK') continue;

      int diff = leg.origin.getDateTime().difference(prevLeg.destination.getDateTime()).inMinutes;
      if (diff > maxWaitTime) maxWaitTime = diff;
      prevLeg = leg;
    }
    return maxWaitTime;
  }

  bool _anyNote(Trip trip) => trip.leg.any(_anyNoteLeg);

  bool _anyNoteLeg(Leg leg) => leg.notes.isNotEmpty || leg.origin.notes.isNotEmpty || leg.destination.notes.isNotEmpty;

  bool _noteOfSeverity(Trip trip, String severity) => trip.leg.any((leg) => _noteOfSeverityLeg(leg, severity));

  bool _noteOfSeverityLeg(Leg leg, String severity) {
    return leg.notes.any((n) => n.severity == severity) ||
        leg.origin.notes.any((n) => n.severity == severity) ||
        leg.destination.notes.any((n) => n.severity == severity);
  }

  Icon _getNotesIcon(Trip trip) {
    if (_noteOfSeverity(trip, 'high')) return getNoteIcon('high');
    if (_noteOfSeverity(trip, 'normal')) return getNoteIcon('normal');
    return getNoteIcon('low');
  }

  Icon _getNotesIconLeg(Leg leg) {
    if (_noteOfSeverityLeg(leg, 'high')) return getNoteIcon('high');
    if (_noteOfSeverityLeg(leg, 'normal')) return getNoteIcon('normal');
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
              Duration(minutes: (_tripOptions.changeMarginMinutes ?? 5) ~/ 2)) return false;
      before = leg;
    }

    return true;
  }

  void _createShortcut(BuildContext context) {
    Map<String, String> params = {};

    if (_from is CurrentLocation) {
      params['originCurrentLocation'] = 'true';
    } else {
      params['originLat'] = _from.lat.toString();
      params['originLon'] = _from.lon.toString();
      params['originName'] = _from.name;
    }

    if (_to is CurrentLocation) {
      params['destCurrentLocation'] = 'true';
    } else {
      params['destLat'] = _to.lat.toString();
      params['destLon'] = _to.lon.toString();
      params['destName'] = _to.name;
    }

    if (_from is StopLocation) params['originId'] = (_from as StopLocation).id.toString();
    if (_from is CoordLocation) params['originType'] = (_from as CoordLocation).type;
    if (_to is StopLocation) params['destId'] = (_to as StopLocation).id.toString();
    if (_to is CoordLocation) params['destType'] = (_to as CoordLocation).type;

    if (_tripOptions.changeMarginMinutes != null) {
      params['changeMargin'] = _tripOptions.changeMarginMinutes.toString();
    }

    if (!_tripOptions.services.every((b) => b)) {
      params['services'] = _tripOptions.services.map((b) => b ? 1 : 0).join();
    }

    if (_tripOptions.wheelchair) params['wheelchair'] = 'true';

    if (_tripOptions.via != null) {
      params['viaId'] = _tripOptions.via!.id.toString();
      params['viaName'] = _tripOptions.via!.name;
      params['viaLat'] = _tripOptions.via!.lat.toString();
      params['viaLon'] = _tripOptions.via!.lon.toString();
    }

    var uri = Uri(scheme: 'resecentrum', host: 'trip', queryParameters: params);
    var label = _from is CurrentLocation ? _to.name.firstPart() : '${_from.name.firstPart()}–${_to.name.firstPart()}';

    createShortcut(context, uri.toString(), label, 'trip', _tripOptions.summary);
  }

  Future<int> _getStopId(Location location) async {
    if (location is CurrentLocation) {
      return (await location.location(onlyStops: true) as StopLocation).id;
    } else if (location is CoordLocation) {
      return (await getLocationFromCoord(location.lat, location.lon, onlyStops: true) as StopLocation).id;
    }
    return (location as StopLocation).id;
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
