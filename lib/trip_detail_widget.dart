import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'extensions.dart';
import 'journey_detail_widget.dart';
import 'map_widget.dart';
import 'options_panel.dart';
import 'reseplaneraren.dart';
import 'utils.dart';

class TripDetailWidget extends StatelessWidget {
  final Trip _trip;
  final ChangeMarginGetter _tripOptions;

  TripDetailWidget(this._trip, this._tripOptions, {Key? key}) : super(key: key) {
    _streamController.add(_trip);
  }

  Iterable<Widget> _legWidgets(BuildContext context) {
    List<Widget> legs = [];

    var bgLuminance = Theme.of(context).cardColor.computeLuminance();

    for (int i = 0; i < _trip.leg.length; i++) {
      Leg leg = _trip.leg.elementAt(i);
      Leg? before = _trip.leg.tryElementAt(i - 1);

      var originSet = leg.origin.notes.toSet();
      var destinationSet = leg.destination.notes.toSet();

      if (leg.origin.notes.isNotEmpty && leg.destination.notes.isNotEmpty) {
        var intersection = originSet.intersection(destinationSet);

        var newLegNotes = leg.notes.toList();
        newLegNotes.addAll(intersection);
        leg.notes = newLegNotes;

        originSet.removeAll(intersection);
        destinationSet.removeAll(intersection);
      }

      leg.origin.notes = originSet;
      leg.destination.notes = destinationSet;

      if (leg.journeyDetailRef != null && before?.journeyDetailRef != null) {
        legs.add(Card(
          margin: const EdgeInsets.all(0),
          child: InkWell(
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (context) {
                return MapWidget(_mapJourneys, focusStops: [leg.origin.id!]);
              }));
            },
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: _walk('Byte', _trip.leg.elementAt(i - 1).destination.getDateTime(), leg.origin.getDateTime(),
                    context, true, before, leg, null)),
          ),
        ));
      }
      if (leg.type == 'WALK' && before?.type == 'WALK') continue;
      legs.add(_legCard(leg, i, context, bgLuminance));
    }
    return legs;
  }

  final StreamController<Trip> _streamController = StreamController();

  Future<void> _handleRefresh() async => _updateTrip();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: tripTitle(_trip.leg.first.origin.name, _trip.leg.last.destination.name),
          actions: [
            IconButton(
                onPressed: () async {
                  await Navigator.push<MapWidget>(context, MaterialPageRoute(builder: (context) {
                    return MapWidget(_mapJourneys);
                  }));
                },
                icon: const Icon(Icons.map))
          ],
        ),
        backgroundColor: cardBackgroundColor(context),
        body: SystemGestureArea(
          MediaQuery.of(context).systemGestureInsets,
          child: RefreshIndicator(
              onRefresh: () => _handleRefresh(),
              child: StreamBuilder<Trip>(
                stream: _streamController.stream,
                builder: (context, tripSnapshot) {
                  if (tripSnapshot.connectionState == ConnectionState.waiting) return loadingPage();
                  var widgets = _legWidgets(context);
                  return CustomScrollView(
                    slivers: [
                      SliverSafeArea(
                        sliver: SliverPadding(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                          sliver: SeparatedSliverList(
                            itemCount: widgets.length,
                            itemBuilder: (context, i) => widgets.elementAt(i),
                            separatorBuilder: (context, i) => const Divider(),
                          ),
                        ),
                      )
                    ],
                  );
                },
              )),
        ));
  }

  List<MapJourney> get _mapJourneys => _trip.leg
      .map((l) => l.journeyDetailRef == null
          ? MapJourney(walk: true, geometry: l.cachedGeometry, geometryRef: l.geometryRef)
          : MapJourney(
              journeyDetailRef: JourneyDetailRef.fromLeg(l),
              journeyPart: IdxJourneyPart(l.origin.routeIdx!, l.destination.routeIdx!)))
      .toList(growable: false);

  Widget _legCard(Leg leg, int i, BuildContext context, double bgLuminance) {
    return Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: () async {
            if (leg.type == 'WALK') {
              await Navigator.push(context, MaterialPageRoute(builder: (context) {
                var journeys = _mapJourneys;
                for (int j = i; j < _trip.leg.length; j++) {
                  if (!journeys[j].walk) break;
                  journeys[j].focus = true;
                }
                return MapWidget(journeys);
              }));
            }
            if (leg.journeyDetailRef == null) return;
            await Navigator.push(context, MaterialPageRoute(builder: (context) {
              return JourneyDetailWidget(
                  leg.journeyDetailRef!,
                  leg.sname ?? leg.name,
                  leg.fgColor ?? Colors.white,
                  leg.bgColor ?? Colors.black,
                  leg.direction ?? leg.name,
                  leg.journeyId!,
                  leg.type,
                  leg.name,
                  leg.journeyNumber,
                  leg.origin.id!,
                  leg.origin.dateTime);
            }));
          },
          onLongPress: leg.journeyDetailRef == null
              ? null
              : () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (context) {
                    var journeys = _mapJourneys;
                    journeys[i].focus = true;
                    return MapWidget(journeys);
                  }));
                },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: leg.type == 'WALK'
                ? _walkFromLeg(leg, _trip.leg.tryElementAt(i - 1), nextLeg(_trip.leg, i), context)
                : _normalLeg(leg, context, bgLuminance),
          ),
        ));
  }

  Widget _normalLeg(Leg leg, BuildContext context, double bgLuminance) {
    return Column(children: [
      Row(
        children: [
          const SizedBox(width: 16),
          lineIconFromLeg(leg, bgLuminance, context),
          const SizedBox(width: 16),
          Expanded(
              child: highlightFirstPart(leg.direction ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold), textScaleFactor: 1.1)),
          accessibilityIcon(leg.accessibility, leg.destination.rtDateTime ?? leg.origin.rtDateTime,
              margin: const EdgeInsets.fromLTRB(8, 0, 0, 0)),
        ],
      ),
      displayTSs(leg.notes),
      leg.notes.isEmpty ? const SizedBox(height: 16) : const Divider(),
      _stopHeader(leg.origin),
      displayTSs(leg.origin.notes),
      const Divider(),
      _legDetail(leg, context),
      const Divider(),
      _stopHeader(leg.destination),
      displayTSs(leg.destination.notes)
    ]);
  }

  Widget _legDetail(Leg leg, BuildContext context) {
    Duration duration = leg.destination.getDateTime().difference(leg.origin.getDateTime());
    int numberOfStops = leg.destination.routeIdx! - leg.origin.routeIdx!;
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Row(
        children: [
          const SizedBox(width: 74),
          Text(
              '${getDurationString(duration)}, $numberOfStops ' +
                  (isTrainType(leg.type)
                      ? numberOfStops > 1
                          ? 'stationer'
                          : 'station'
                      : numberOfStops > 1
                          ? 'hållplatser'
                          : 'hållplats'),
              style: TextStyle(color: Theme.of(context).hintColor))
        ],
      ),
    );
  }

  Widget _walkFromLeg(Leg leg, Leg? before, Leg? after, BuildContext context) {
    bool transfer = before != null && after != null ? before.destination.name == after.origin.name : false;
    return _walk(transfer ? 'Byte' : leg.name, transfer ? before.destination.getDateTime() : leg.origin.getDateTime(),
        transfer ? after.origin.getDateTime() : leg.destination.getDateTime(), context, transfer, before, after, leg);
  }

  Widget _walk(String text, DateTime start, DateTime end, BuildContext context, bool transfer, Leg? before, Leg? after,
      Leg? leg) {
    bool walkBetweenStops = before != null && after != null && before.journeyId != null && after.journeyId != null;
    var duration = walkBetweenStops
        ? after.origin.getDateTime().difference(before.destination.getDateTime())
        : end.difference(start);

    IconData icon = transfer ? Icons.transfer_within_a_station : Icons.directions_walk;

    Future<double?> walkDistance = _getWalkDistance(leg);

    return Column(
      children: [
        Row(
          children: [
            Container(
                constraints: const BoxConstraints(minWidth: 64),
                margin: const EdgeInsets.fromLTRB(5, 0, 10, 0),
                child: FutureBuilder<double?>(
                    future: walkDistance,
                    builder: (context, distance) {
                      var walkSpeed = _walkSpeed(distance.data, duration);
                      if (walkSpeed > 6 && !transfer) icon = Icons.directions_run;
                      if (walkSpeed > 15 || walkSpeed < 0) icon = Icons.warning;
                      return iconAndText(icon, text, gap: 10);
                    })),
            Text(getDurationString(duration), style: TextStyle(color: Theme.of(context).hintColor)),
            FutureBuilder<double?>(
                future: walkDistance,
                builder: (context, distance) {
                  if (!distance.hasData || distance.data == null) return Container();
                  return Text(', ${distance.data!.round()} m', style: TextStyle(color: Theme.of(context).hintColor));
                })
          ],
        ),
        if (before != null && after != null)
          FutureBuilder<Widget?>(
            future: _walkValidation(walkDistance, duration, transfer),
            builder: (context, result) {
              if (!result.hasData || result.data == null) return Container();
              return Column(
                children: [
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(5, 0, 0, 0),
                    child: result.data!,
                  ),
                ],
              );
            },
          ),
      ],
    );
  }

  double _walkSpeed(double? walkDistance, Duration duration) {
    return 3.6 * (walkDistance ?? 0) / duration.inSeconds; // km/h
  }

  Future<Widget?> _walkValidation(Future<double?> walkDistance, Duration duration, bool transfer) async {
    var walkSpeed = _walkSpeed(await walkDistance, duration);
    const String text = 'Risk för att missa anslutningen';
    if (duration <= const Duration(minutes: 0) || walkSpeed > 10) {
      return iconAndText(Icons.warning, text, gap: 10, iconColor: Colors.red);
    }
    if (walkSpeed > 5 || duration <= Duration(minutes: (_tripOptions.changeMarginMinutes ?? 5) ~/ 2)) {
      return iconAndText(Icons.error, text, gap: 10, iconColor: Colors.orange);
    }
    return null;
  }

  Widget _stopHeader(TripLocation location) {
    return stopRow(simpleTimeWidget(location.dateTime, getTripLocationDelay(location), location.cancelled),
        location.name, location.track, location.rtTrack);
  }

  Future<double?> _getWalkDistance(Leg? leg) async {
    if (leg == null) return null;
    var geometry = await leg.geometry();
    if (geometry == null) return null;
    double distance = 0;
    Point? previous;
    for (var line in geometry) {
      for (var point in line) {
        if (previous != null) {
          distance += Geolocator.distanceBetween(previous.lat, previous.lon, point.lat, point.lon);
        }
        previous = point;
      }
    }
    int i = _trip.leg.indexOf(leg);
    Leg? after = _trip.leg.tryElementAt(i + 1);
    if (after?.type == 'WALK') distance += (await _getWalkDistance(after)) ?? 0;
    return distance;
  }

  void _updateTrip() async {
    _trip.leg = _trip.leg.toList(growable: false);

    await Future.wait(_trip.leg
        .where((leg) => leg.journeyDetailRef != null)
        .map((leg) => getJourneyDetailExtra(JourneyDetailRef.fromLeg(leg)).then((jt) {
              if (jt == null) return;

              Stop? origin = jt.stop.firstWhere((s) => s.routeIdx == leg.origin.routeIdx!);
              leg.origin.rtDateTime = origin.rtDepTime ?? origin.rtArrTime;
              leg.origin.rtTrack = origin.rtTrack;
              leg.origin.cancelled = origin.depCancelled;

              Stop? destination = jt.stop.firstWhere((s) => s.routeIdx == leg.destination.routeIdx!);
              leg.destination.rtDateTime = destination.rtArrTime ?? destination.rtDepTime;
              leg.destination.rtTrack = destination.rtTrack;
              leg.destination.cancelled = destination.arrCancelled;
            })));

    _streamController.add(_trip);
  }
}
