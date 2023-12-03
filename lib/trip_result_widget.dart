import 'dart:async';

import 'package:collection/collection.dart';
import 'package:dotted_line/dotted_line.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'extensions.dart';
import 'main.dart';
import 'map_widget.dart';
import 'network/planera_resa.dart';
import 'options_panel.dart';
import 'trip_detail_widget.dart';
import 'utils.dart';

const int longWaitingTime = 90;

class TripResultWidget extends StatefulWidget {
  final Location _from;
  final Location _to;
  final DateTime? _dateTime;
  final bool _searchForArrival;
  final TripOptions _tripOptions;

  const TripResultWidget(this._from, this._to, this._dateTime, this._searchForArrival, this._tripOptions, {super.key});

  @override
  State<TripResultWidget> createState() => _TripResultWidgetState();
}

class _TripResultWidgetState extends State<TripResultWidget> {
  @override
  void initState() {
    super.initState();
    _updateJourneys();
  }

  @override
  void dispose() {
    _streamController.close();
    super.dispose();
  }

  List<Journey>? _journeys;
  Links? _links;

  final StreamController<List<Journey>?> _streamController = StreamController.broadcast();
  final GlobalKey<RefreshIndicatorState> _refreshKey = GlobalKey();

  Future<void>? alternativeRefresh;

  Future<void> _handleRefresh() async {
    if (alternativeRefresh != null) {
      var refresh = alternativeRefresh!;
      alternativeRefresh = null;
      return refresh;
    }
    return _updateJourneys(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    var bgColor = Theme.of(context).cardColor;
    return Scaffold(
        appBar: AppBar(
          title: StreamBuilder(
              stream: _streamController.stream,
              builder: (context, snapshot) {
                return tripTitle(widget._from.getName(), widget._to.getName(), via: widget._tripOptions.via?.name);
              }),
          actions: [
            StreamBuilder(
                stream: _streamController.stream,
                builder: (context, snapshot) {
                  return supportShortcuts || _links?.previous != null
                      ? PopupMenuButton(
                          onSelected: (selection) async {
                            switch (selection) {
                              case MenuAction.addToHomeScreen:
                                _createShortcut(context);
                                break;
                              case MenuAction.showEarlierJourneys:
                                alternativeRefresh = _addEarlierJourneys();
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
                                        visualDensity: VisualDensity.compact),
                                  ),
                                if (_links?.previous != null)
                                  const PopupMenuItem(
                                    value: MenuAction.showEarlierJourneys,
                                    child: ListTile(
                                        leading: Icon(Icons.history),
                                        title: Text('Visa tidigare resor'),
                                        visualDensity: VisualDensity.compact),
                                  )
                              ])
                      : Container();
                })
          ],
        ),
        backgroundColor: cardBackgroundColor(context),
        body: SystemGestureArea(
          MediaQuery.of(context).systemGestureInsets,
          child: RefreshIndicator(
            key: _refreshKey,
            onRefresh: () => _handleRefresh(),
            child: StreamBuilder<List<Journey>?>(
              builder: (context, journeys) {
                if (journeys.connectionState == ConnectionState.waiting) return loadingPage();
                if (!journeys.hasData) return ErrorPage(_updateJourneys, error: journeys.error);
                if (journeys.data!.isEmpty) return noDataPage('Inga reseförslag hittades');
                int maxTripTime = _getJourneyTimeWindow(journeys.data!);
                return CustomScrollView(
                  slivers: [
                    SliverSafeArea(
                      sliver: SliverPadding(
                        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 5),
                        sliver: SliverList(
                            delegate: SliverChildBuilderDelegate((context, i) {
                          if (i == journeys.data!.length) {
                            return FutureBuilder(
                                future: _addJourneys(),
                                builder: (context, snapshot) {
                                  return snapshot.connectionState == ConnectionState.waiting
                                      ? Container(
                                          constraints: const BoxConstraints(minHeight: 80), child: loadingPage())
                                      : Container();
                                });
                          }
                          var journey = journeys.data!.elementAt(i);
                          var tripTime = journey.travelTime;

                          var partlyReplacementBus = journey.tripLegs.where((l) =>
                              (l.depState.state == DepartureState.replacementBus) ^
                              (l.arrState.state == DepartureState.replacementBus));

                          var replacementBus = journey.tripLegs.where((l) =>
                              l.depState.state == DepartureState.replacementBus &&
                              l.arrState.state == DepartureState.replacementBus);

                          var partlyCancelled =
                              journey.tripLegs.where((tripLeg) => tripLeg.isPartCancelled && !tripLeg.isCancelled);

                          var cancelled = journey.tripLegs.where(
                              (l) => l.isCancelled && !replacementBus.followedBy(partlyReplacementBus).contains(l));

                          var partlyCancelledWithNote = partlyCancelled
                              .where((leg) => leg.notes.any((note) => note.text.contains('Färd inställd ')));
                          partlyCancelled = partlyCancelled.where((leg) => !partlyCancelledWithNote.contains(leg));

                          List<String> notes = <String>[].addIf(
                              _getMaxWaitTime(journey) >= longWaitingTime,
                              'Längre uppehåll vid en hållplats '
                              '(${getDurationString(Duration(minutes: _getMaxWaitTime(journey)))})');

                          var highestConnectionRisk = _highestConnectionRisk(journey);
                          Widget? connectionValidationWidget;
                          if (cancelled.isEmpty &&
                              partlyCancelled.isEmpty &&
                              partlyCancelledWithNote.isEmpty &&
                              replacementBus.isEmpty &&
                              highestConnectionRisk != ConnectionValidation.valid) {
                            connectionValidationWidget = getConnectionValidationWidget(highestConnectionRisk,
                                textColor: Theme.of(context).hintColor, specificConnection: false);
                          }

                          List<String> cancellations = <String>[].addIf(
                              cancelled.isNotEmpty,
                              cancelled
                                      .map((l) => l.serviceJourney.isTrain
                                          ? '${l.serviceJourney.line.name} ${l.serviceJourney.line.designation}'
                                          : l.serviceJourney.line.name.uncapitalize())
                                      .joinNaturally()
                                      .capitalize() +
                                  (cancelled.length == 1
                                      ? (cancelled.single.serviceJourney.isTrain ? ' är inställt' : ' är inställd')
                                      : ' är inställda'));
                          cancellations.addAll(partlyCancelledWithNote.map((leg) =>
                              leg.notes.firstWhere((note) => note.text.contains('Färd inställd ')).text.replaceFirst(
                                  'Färd inställd ',
                                  '${leg.serviceJourney.line.name}'
                                      ' är ${leg.serviceJourney.isTrain ? 'inställt' : 'inställd'} ')));
                          cancellations
                              .addIf(
                                  partlyCancelled.isNotEmpty,
                                  partlyCancelled
                                          .map((l) => l.serviceJourney.isTrain
                                              ? '${l.serviceJourney.line.name} ${l.serviceJourney.line.designation}'
                                              : l.serviceJourney.line.name.uncapitalize())
                                          .joinNaturally()
                                          .capitalize() +
                                      (partlyCancelled.length == 1
                                          ? (partlyCancelled.single.serviceJourney.isTrain
                                              ? ' är delvis inställt'
                                              : ' är delvis inställd')
                                          : ' är delvis inställda'))
                              .addIf(
                                  replacementBus.isNotEmpty,
                                  replacementBus
                                          .map((l) =>
                                              '${l.serviceJourney.line.name} ${l.serviceJourney.line.designation}')
                                          .joinNaturally() +
                                      (replacementBus.length > 1 ? ' är ersatta med buss' : ' är ersatt med buss'))
                              .addIf(
                                  partlyReplacementBus.isNotEmpty,
                                  partlyReplacementBus
                                          .map((l) =>
                                              '${l.serviceJourney.line.name} ${l.serviceJourney.line.designation}')
                                          .joinNaturally() +
                                      (partlyReplacementBus.length > 1
                                          ? ' är delvis ersatta med buss'
                                          : ' är delvis ersatt med buss'));
                          var firstJourneyLeg = journey.firstJourneyLeg;
                          var lastJourneyLeg = journey.lastJourneyLeg;
                          return Card(
                              margin: const EdgeInsets.all(5),
                              child: InkWell(
                                onTap: () {
                                  Navigator.push(context, MaterialPageRoute(builder: (context) {
                                    return TripDetailsWidget(journeys.data!, i);
                                  })).then((_) => _streamController.add(_journeys));
                                },
                                onLongPress: () {
                                  Navigator.push<MapWidget>(context, MaterialPageRoute(builder: (context) {
                                    return MapWidget([MapJourney(journeyDetailsReference: journey.detailsReference)]);
                                  }));
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    _legBar(journey, bgColor, maxTripTime, tripTime.inMinutes, context),
                                    const SizedBox(height: 8),
                                    Row(children: [
                                      Container(
                                        constraints: const BoxConstraints(minWidth: 56),
                                        child: simpleTimeWidget(
                                            firstJourneyLeg.plannedDepartureTime,
                                            getDelay(firstJourneyLeg.plannedDepartureTime,
                                                firstJourneyLeg.estimatedDepartureTime),
                                            journey.tripLegs.firstOrNull?.isDepartureCancelled ?? false,
                                            journey.tripLegs.firstOrNull?.depState.state,
                                            walk: firstJourneyLeg is Link,
                                            useHintColor: true),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Wrap(
                                            spacing: 12,
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            children: <Widget>[TripTimeWidget(tripTime, journey)]
                                                .insertIf(_anyNote(journey), 0, _getNotesIcon(journey))
                                                .insertIf(cancelled.isNotEmpty, 0,
                                                    const Text('Inställd', style: TextStyle(color: Colors.red)))
                                                .insertIf(
                                                    (partlyCancelled.isNotEmpty ||
                                                            partlyCancelledWithNote.isNotEmpty) &&
                                                        cancelled.isEmpty,
                                                    0,
                                                    const Text('Delvis inställd', style: TextStyle(color: Colors.red)))
                                                .insertIf(_requireBooking(journey), 0, const Icon(Icons.phone))
                                                .addIf(
                                                    journey.tripLegs.any((tripLeg) =>
                                                        (tripLeg.estimatedDepartureTime ??
                                                                tripLeg.estimatedArrivalTime) !=
                                                            null &&
                                                        !tripLeg.serviceJourney.line.isWheelchairAccessible),
                                                    const Icon(Icons.not_accessible))),
                                      ),
                                      const SizedBox(width: 8),
                                      simpleTimeWidget(
                                          lastJourneyLeg.plannedArrivalTime,
                                          getDelay(
                                              lastJourneyLeg.plannedArrivalTime, lastJourneyLeg.estimatedArrivalTime),
                                          journey.tripLegs.lastOrNull?.isArrivalCancelled ?? false,
                                          journey.tripLegs.lastOrNull?.arrState.state,
                                          walk: lastJourneyLeg is Link,
                                          useHintColor: true)
                                    ]),
                                    if (notes.isNotEmpty ||
                                        cancellations.isNotEmpty ||
                                        connectionValidationWidget != null)
                                      const SizedBox(height: 8),
                                    Wrap(
                                        runSpacing: 5,
                                        children: [
                                          cancellations.map<Widget>((msg) => iconAndText(Icons.cancel, msg,
                                              iconColor: Colors.red, textColor: Theme.of(context).hintColor)),
                                          if (connectionValidationWidget != null) [connectionValidationWidget],
                                          notes.map<Widget>((msg) => iconAndText(Icons.info_outline, msg,
                                              iconColor: Theme.of(context).hintColor,
                                              textColor: Theme.of(context).hintColor))
                                        ].flattened.toList(growable: false))
                                  ]),
                                ),
                              ));
                        }, childCount: journeys.data!.length + 1)),
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

  Future<Journeys> _getJourneys({String? url, bool refresh = false, bool addMore = false}) async {
    Location? from = widget._from, to = widget._to;

    if (widget._from is CurrentLocation) {
      var currentLocation = (widget._from as CurrentLocation);
      from = addMore ? currentLocation.cachedLocation : await currentLocation.location(forceRefresh: refresh);
    }
    if (widget._to is CurrentLocation) {
      var currentLocation = (widget._to as CurrentLocation);
      to = addMore ? currentLocation.cachedLocation : await currentLocation.location(forceRefresh: refresh);
    }

    if (from == null || to == null) return Future.error(NoLocationError());

    Set<TransportMode>? transportModes;
    Set<TransportSubMode>? transportSubModes;

    if (!widget._tripOptions.services.all()) {
      transportModes = {
        if (widget._tripOptions.services[0]) TransportMode.tram,
        if (widget._tripOptions.services[1]) TransportMode.bus,
        if (widget._tripOptions.services[4]) TransportMode.ferry,
        if (widget._tripOptions.services[2] || widget._tripOptions.services[3]) TransportMode.train,
        TransportMode.taxi,
        TransportMode.walk
      };

      if (!widget._tripOptions.services[2] || !widget._tripOptions.services[3]) {
        transportSubModes = {
          if (widget._tripOptions.services[2]) TransportSubMode.vasttagen,
          if (widget._tripOptions.services[3]) TransportSubMode.longdistancetrain,
          if (widget._tripOptions.services[3]) TransportSubMode.regionaltrain
        };
      }
    }

    var journeys = url != null
        ? await PlaneraResa.journeys(url: url)
        : await PlaneraResa.journeys(
            originGid: from is StopLocation ? from.gid : null,
            destinationGid: to is StopLocation ? to.gid : null,
            originCoord: widget._from is! StopLocation ? widget._from.position : null,
            originName: from is! StopLocation ? from.name : null,
            destinationCoord: widget._to is! StopLocation ? widget._to.position : null,
            destinationName: to is! StopLocation ? to.name : null,
            dateTime: widget._dateTime,
            interchangeDurationInMinutes: widget._tripOptions.changeMarginMinutes,
            transportModes: transportModes,
            transportSubModes: transportSubModes,
            viaGid: widget._tripOptions.via?.gid,
            dateTimeRelatesTo:
                widget._searchForArrival ? DateTimeRelatesToType.arrival : DateTimeRelatesToType.departure,
            includeNearbyStopAreas: widget._tripOptions.includeNearbyStops,
            originWalk:
                widget._tripOptions.maxWalkDistance != null ? '1,0,${widget._tripOptions.maxWalkDistance}' : null,
            destWalk: widget._tripOptions.maxWalkDistance != null ? '1,0,${widget._tripOptions.maxWalkDistance}' : null,
          );

    await setTripLegTrainInfo(journeys.results);

    return journeys;
  }

  Future<void> _updateJourneys({bool refresh = false}) async {
    try {
      var journeys = await _getJourneys(refresh: refresh);
      _journeys = journeys.results;
      _links = journeys.links;
      _streamController.add(_journeys);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        print(error);
        print(stackTrace);
      }
      _streamController.addError(error);
    }
  }

  Future<void> _addJourneys() async {
    if (_links?.next == null) return;
    var moreJourneys = await _getJourneys(url: _links?.next, addMore: true).suppress();
    if (moreJourneys == null || moreJourneys.results.isEmpty) return;
    _journeys?.addAll(moreJourneys.results);
    _links?.next = moreJourneys.links.next;
    _streamController.add(_journeys);
  }

  Future<void> _addEarlierJourneys() async {
    if (_links?.previous == null) return;
    var moreJourneys = await _getJourneys(url: _links?.previous, addMore: true).suppress();
    if (moreJourneys == null || moreJourneys.results.isEmpty) return;
    (_journeys ?? []).insertAll(0, moreJourneys.results);
    _links?.previous = moreJourneys.links.previous;
    _streamController.add(_journeys);
  }

  Widget _legBar(Journey trip, Color bgColor, int maxTripTime, int tripTime, BuildContext context) {
    var children = <Widget>[];

    int minutes = 0;
    DateTime startTime = trip.firstJourneyLeg.departureTime;
    int flex;

    for (var (before, leg, after) in trip.journeyLegTriplets) {
      if (leg is ConnectionLink &&
          leg.transportMode == TransportMode.walk &&
          leg.origin.stopPoint.stopArea!.gid == leg.destination.stopPoint.stopArea!.gid) continue;

      flex = leg.departureTime.difference(startTime).inMinutes - minutes;
      if (flex > 0) {
        minutes += flex;
        children.add(Expanded(flex: flex, child: Container()));
      }

      flex = leg.arrivalTime.difference(startTime).inMinutes - minutes;
      if (flex <= 0) flex = 1;
      minutes += flex;

      var legWidget = switch (leg) {
        TripLeg() => _lineBox(leg, bgColor, context),
        Link() => _walk(before, leg, after, context),
      };

      if (leg is TripLeg && _anyNoteLeg(leg)) {
        var icon = _getNotesIconLeg(leg);

        if (icon.icon == Icons.info) icon = const Icon(Icons.info, color: Colors.white);

        var line = leg.serviceJourney.line;

        var iconColor = icon.color ?? Theme.of(context).iconTheme.color!;
        var bgContrast = colorDiff2(iconColor, line.backgroundColor);
        bool lowContrast = bgContrast < 500 * 500 && bgContrast < colorDiff2(iconColor, line.foregroundColor);

        Widget iconWidget = lowContrast || (icon.icon == Icons.info && Theme.of(context).brightness == Brightness.light)
            ? Stack(alignment: Alignment.center, children: [
                if (lowContrast) Container(decoration: BoxDecoration(color: line.foregroundColor), width: 4, height: 8),
                Icon(icon.icon, color: lowContrast ? line.foregroundColor : line.backgroundColor, size: 18),
                Icon(icon.icon, color: icon.color, size: 16),
              ])
            : Icon(icon.icon, color: icon.color, size: 16);

        legWidget =
            Stack(clipBehavior: Clip.none, children: [legWidget, Positioned(top: -5, right: -5, child: iconWidget)]);
      }

      children.add(Expanded(flex: flex, child: legWidget));
    }

    children.add(Expanded(flex: maxTripTime - tripTime, child: Container()));

    return Row(children: children);
  }

  Stack _walk(JourneyLeg? before, Link link, JourneyLeg? after, BuildContext context) {
    var icon = switch (link.transportMode) {
      TransportMode.bike => Icons.directions_bike,
      TransportMode.car => Icons.directions_car,
      TransportMode.walk || _ => Icons.directions_walk,
    };

    var connectionValidation = getConnectionValidation(before, link, after);
    if (connectionValidation.index >= ConnectionValidation.mediumRisk.index) icon = Icons.directions_run;

    return Stack(
        alignment: Alignment.bottomCenter, children: [Icon(icon), DottedLine(dashColor: Theme.of(context).hintColor)]);
  }

  Widget defaultNote(String msg, BuildContext context) => iconAndText(Icons.info_outline, msg,
      iconColor: Theme.of(context).hintColor, textColor: Theme.of(context).hintColor);

  Widget defaultWarning(String msg, BuildContext context) =>
      iconAndText(Icons.warning, msg, iconColor: Colors.red, textColor: Theme.of(context).hintColor);

  Widget _lineBox(TripLeg leg, Color bgColor, BuildContext context) {
    var line = leg.serviceJourney.line;
    BoxDecoration decoration = lineBoxDecoration(line, bgColor, context);
    bool replacementBus =
        (leg.depState.state == DepartureState.replacementBus || leg.arrState.state == DepartureState.replacementBus) &&
            !(leg.isDepartureCancelled && leg.depState.state != DepartureState.replacementBus ||
                leg.isArrivalCancelled && leg.arrState.state != DepartureState.replacementBus);
    if (leg.isCancelled || leg.isDepartureCancelled || leg.isArrivalCancelled) {
      decoration =
          decoration.copyWith(border: Border.all(color: replacementBus ? orange(context) : Colors.red, width: 4));
    }
    return PhysicalModel(
      elevation: 1.5,
      color: line.backgroundColor,
      borderRadius: BorderRadius.circular(3),
      child: Container(
          decoration: decoration,
          height: 26,
          child: Center(
              child: Text(line.shortName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: line.foregroundColor, fontWeight: FontWeight.bold, overflow: TextOverflow.ellipsis)))),
    );
  }

  int _getJourneyTimeWindow(Iterable<Journey> journeys) {
    int maxJourneyTime = 0;
    for (var journey in journeys) {
      int journeyTime = journey.travelTime.inMinutes;
      if (journeyTime > maxJourneyTime && _getMaxWaitTime(journey) <= longWaitingTime) maxJourneyTime = journeyTime;
    }
    return maxJourneyTime;
  }

  int _getMaxWaitTime(Journey journey) {
    if (journey.tripLegs.isEmpty) return 0;
    TripLeg prevLeg = journey.tripLegs.first;
    int maxWaitTime = 0;
    for (var leg in journey.tripLegs.skip(1)) {
      int diff = leg.departureTime.difference(prevLeg.arrivalTime).inMinutes;
      if (diff > maxWaitTime) maxWaitTime = diff;
      prevLeg = leg;
    }
    return maxWaitTime;
  }

  bool _anyNote(Journey journey) => journey.tripLegs.any(_anyNoteLeg);

  bool _requireBooking(Journey journey) => journey.tripLegs.any((leg) => leg.notes.any((note) => note.booking));

  bool _anyNoteLeg(TripLeg leg) =>
      leg.notes.isNotEmpty || leg.origin.notes.isNotEmpty || leg.destination.notes.isNotEmpty;

  bool _noteOfSeverity(Journey journey, Severity severity) =>
      journey.tripLegs.any((leg) => _noteOfSeverityLeg(leg, severity));

  bool _noteOfSeverityLeg(TripLeg leg, Severity severity) {
    return leg.notes.any((n) => n.severity == severity) ||
        leg.origin.notes.any((n) => n.severity == severity) ||
        leg.destination.notes.any((n) => n.severity == severity);
  }

  Icon _getNotesIcon(Journey journey) {
    if (_noteOfSeverity(journey, Severity.high)) return getNoteIcon(Severity.high);
    if (_noteOfSeverity(journey, Severity.normal)) return getNoteIcon(Severity.normal);
    return getNoteIcon(Severity.low, infoOutline: false);
  }

  Icon _getNotesIconLeg(TripLeg leg) {
    if (_noteOfSeverityLeg(leg, Severity.high)) return getNoteIcon(Severity.high);
    if (_noteOfSeverityLeg(leg, Severity.normal)) return getNoteIcon(Severity.normal);
    return getNoteIcon(Severity.low, infoOutline: false);
  }

  ConnectionValidation _highestConnectionRisk(Journey journey) {
    var highest = ConnectionValidation.valid;

    // Check connections
    for (var (before, leg, after) in journey.journeyLegTriplets) {
      ConnectionValidation? connectionValidation;
      if (leg is ConnectionLink) {
        connectionValidation = getConnectionValidation(before, leg, after);
      } else if (before is TripLeg && leg is TripLeg) {
        connectionValidation = getConnectionValidation(before, null, leg);
      }

      if (connectionValidation != null && connectionValidation.index > highest.index) highest = connectionValidation;
    }

    return highest;
  }

  void _createShortcut(BuildContext context) {
    Map<String, String> params = {};

    if (widget._from is CurrentLocation) {
      params['originCurrentLocation'] = 'true';
    } else {
      params['originLat'] = widget._from.position.latitude.toString();
      params['originLon'] = widget._from.position.longitude.toString();
      params['originName'] = widget._from.name;
    }

    if (widget._to is CurrentLocation) {
      params['destCurrentLocation'] = 'true';
    } else {
      params['destLat'] = widget._to.position.latitude.toString();
      params['destLon'] = widget._to.position.longitude.toString();
      params['destName'] = widget._to.name;
    }

    if (widget._from is StopLocation) params['originId'] = (widget._from as StopLocation).gid;
    if (widget._from is CoordLocation) params['originType'] = (widget._from as CoordLocation).typeString;
    if (widget._to is StopLocation) params['destId'] = (widget._to as StopLocation).gid;
    if (widget._to is CoordLocation) params['destType'] = (widget._to as CoordLocation).typeString;

    if (widget._tripOptions.changeMarginMinutes != null) {
      params['changeMargin'] = widget._tripOptions.changeMarginMinutes.toString();
    }

    if (!widget._tripOptions.services.all()) {
      params['services'] = widget._tripOptions.services.map((b) => b ? 1 : 0).join();
    }

    if (!widget._tripOptions.includeNearbyStops) params['includeNearbyStops'] = 'false';

    if (widget._tripOptions.maxWalkDistance != null) {
      params['maxWalkDistance'] = widget._tripOptions.maxWalkDistance.toString();
    }

    if (widget._tripOptions.via != null) {
      params['viaId'] = widget._tripOptions.via!.gid;
      params['viaName'] = widget._tripOptions.via!.name;
      params['viaLat'] = widget._tripOptions.via!.position.latitude.toString();
      params['viaLon'] = widget._tripOptions.via!.position.longitude.toString();
    }

    var uri = Uri(scheme: 'resecentrum', host: 'trip', queryParameters: params);
    var label = widget._from is CurrentLocation
        ? widget._to.name.firstPart()
        : '${widget._from.name.firstPart()}–${widget._to.name.firstPart()}';

    createShortcut(context, uri.toString(), label, 'trip', widget._tripOptions.summary);
  }
}

class TripTimeWidget extends StatefulWidget {
  final Duration _tripTime;
  final Journey _journey;

  const TripTimeWidget(this._tripTime, this._journey, {super.key});

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
    var tripLeg = widget._journey.tripLegs.firstOrNull;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.access_time),
      const SizedBox(width: 5),
      highlightFirstPart(getDurationString(widget._tripTime) +
          getTripCountdown(tripLeg?.isDepartureCancelled == true ? null : tripLeg?.departureTime, tripLeg,
              widget._journey.isDeparted)),
    ]);
  }
}
