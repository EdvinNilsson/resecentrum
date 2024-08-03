import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'extensions.dart';
import 'journey_detail_widget.dart';
import 'main.dart';
import 'map_widget.dart';
import 'network/planera_resa.dart';
import 'trip_result_widget.dart';
import 'utils.dart';

const Set<JourneyDetailsIncludeType> journeyDetailsIncludes = {
  JourneyDetailsIncludeType.serviceJourneyCalls,
  JourneyDetailsIncludeType.serviceJourneyCoordinates,
  JourneyDetailsIncludeType.links,
};

class TripDetailsWidget extends StatelessWidget {
  Journey get journey => _journeys[journeyIndex];

  set journey(Journey value) => _journeys[journeyIndex] = value;

  final List<Journey> _journeys;
  final int journeyIndex;

  final StreamController<JourneyDetails> _streamController = StreamController.broadcast();

  Future<void> _handleRefresh() async => _refreshJourney();

  TripDetailsWidget(this._journeys, this.journeyIndex, {super.key}) {
    _updateJourney();
  }

  Future<void> _updateJourney() async {
    try {
      var journeyDetails =
          await PlaneraResa.journeyDetails(journey.detailsReference, journeyDetailsIncludes).suppress() ??
              await PlaneraResa.journeyDetails(
                  (journey = await PlaneraResa.reconstructJourney(journey.reconstructionReference)).detailsReference,
                  journeyDetailsIncludes);

      _streamController.add(journeyDetails);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        print(error);
        print(stackTrace);
      }
      _streamController.addError(error);
    }
  }

  Iterable<Widget> _legWidgets(JourneyDetails journeyDetails, BuildContext context) {
    List<Widget> legs = [];

    var bgColor = Theme.of(context).cardColor;

    for (var (i, (before, leg, after)) in journey.journeyLegTriplets.indexed) {
      if (leg is TripLeg) {
        var originSet = leg.origin.notes.toSet();
        var destinationSet = leg.destination.notes.toSet();

        if (leg.origin.notes.isNotEmpty && leg.destination.notes.isNotEmpty) {
          var intersection = originSet.intersection(destinationSet);

          var newLegNotes = leg.notes.toSet();
          newLegNotes.addAll(intersection);
          leg.notes = newLegNotes;

          originSet.removeAll(intersection);
          destinationSet.removeAll(intersection);
        }

        leg.origin.notes = originSet;
        leg.destination.notes = destinationSet;
      }

      if (leg is TripLeg && before is TripLeg) {
        void openMap() {
          Navigator.push(context, MaterialPageRoute(builder: (context) {
            return MapWidget(mapJourneys(journeyDetails), focusStopPoints: [leg.origin.stopPoint.gid]);
          }));
        }

        legs.add(Card(
          margin: const EdgeInsets.all(0),
          child: InkWell(
            onTap: openMap,
            onLongPress: openMap,
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: _walk('Byte', before.arrivalTime, leg.departureTime, context, true, before, leg, null)),
          ),
        ));
      }

      legs.add(_legCard(leg, i, context, bgColor, before, after, journeyDetails));
    }
    return legs;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: tripTitle(journey.firstJourneyLeg.originName, journey.lastJourneyLeg.destinationName),
          actions: [
            if (supportVttogo && journey.tripLegs.isNotEmpty)
              PopupMenuButton(
                  onSelected: (_) => buyTicket(context, journey.tripLegs.first.origin.stopPoint.gid,
                      journey.tripLegs.last.destination.stopPoint.gid),
                  itemBuilder: (BuildContext context) => [
                        const PopupMenuItem(
                          value: MenuAction.buyTicket,
                          child: ListTile(
                              leading: Icon(Icons.confirmation_num),
                              title: Text('Köp enkelbiljett'),
                              visualDensity: VisualDensity.compact),
                        )
                      ]),
            StreamBuilder<JourneyDetails>(
                stream: _streamController.stream,
                builder: (context, snapshot) {
                  return IconButton(
                      onPressed: () {
                        Navigator.push<MapWidget>(context, MaterialPageRoute(builder: (context) {
                          return MapWidget(snapshot.hasData
                              ? mapJourneys(snapshot.data!)
                              : [MapJourney(journeyDetailsReference: journey.detailsReference)]);
                        }));
                      },
                      icon: const Icon(Icons.map));
                })
          ],
        ),
        backgroundColor: cardBackgroundColor(context),
        body: SystemGestureArea(
          MediaQuery.of(context).systemGestureInsets,
          child: RefreshIndicator(
              onRefresh: () => _handleRefresh(),
              child: StreamBuilder<JourneyDetails>(
                stream: _streamController.stream,
                builder: (context, journeyDetailsSnapshot) {
                  if (journeyDetailsSnapshot.connectionState == ConnectionState.waiting) return loadingPage();
                  if (!journeyDetailsSnapshot.hasData) {
                    return ErrorPage(_updateJourney, error: journeyDetailsSnapshot.error);
                  }
                  var widgets = _legWidgets(journeyDetailsSnapshot.data!, context);
                  var zoneWidget = _zoneWidget(journeyDetailsSnapshot.data!, context);

                  return CustomScrollView(
                    slivers: [
                      if (!journey.firstJourneyLeg.plannedDepartureTime.isSameDayAs(DateTime.now()) &&
                          !journey.lastJourneyLeg.plannedArrivalTime.isSameDayAs(DateTime.now()))
                        dateBar(journey.firstJourneyLeg.plannedDepartureTime, showTime: false, margin: 24),
                      SliverSafeArea(
                        sliver: SliverPadding(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                          sliver: SeparatedSliverList(
                            itemCount: widgets.length,
                            itemBuilder: (context, i) => widgets.elementAt(i),
                            separatorBuilder: (context, i) => const Divider(),
                          ),
                        ),
                        bottom: false,
                      ),
                      SliverSafeArea(sliver: SliverToBoxAdapter(child: zoneWidget))
                    ],
                  );
                },
              )),
        ));
  }

  static List<MapJourney> mapJourneys(JourneyDetails journeyDetails) => journeyDetails.allJourneyLegs
      .map((leg) => switch (leg) {
            TripLegDetails leg => MapJourney(
                serviceJourneyDetails: ServiceJourneyDetails.fromTripLegDetails(leg),
                journeyPart: JourneyPart(leg.origin.index, leg.destination.index)),
            Link link => MapJourney(link: link),
            TripLeg _ => MapJourney(),
          })
      .toList(growable: false);

  Widget _zoneWidget(JourneyDetails journeyDetails, BuildContext context) {
    var zones = journeyDetails.tariffZones.map((e) => e.name).toList(growable: false)..sort();
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Center(child: Text(zones.joinNaturally(), style: TextStyle(color: Theme.of(context).hintColor))),
    );
  }

  Widget _legCard(JourneyLeg leg, int i, BuildContext context, Color bgColor, JourneyLeg? before, JourneyLeg? after,
      JourneyDetails journeyDetails) {
    void openLinkOnMap() {
      Navigator.push(context, MaterialPageRoute(builder: (context) {
        var journeys = mapJourneys(journeyDetails);
        journeys[i].focus = true;
        return MapWidget(journeys);
      }));
    }

    return Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: () => switch (leg) {
            Link() => openLinkOnMap(),
            TripLeg() => () {
                var tripLegIndex = journeyDetails.tripLegs.indexWhere((l) => l.journeyLegIndex == leg.journeyLegIndex);
                Navigator.push(context, MaterialPageRoute(builder: (context) {
                  return JourneyDetailsWidget(TripLegDetailsRef(journey, leg.serviceJourney, tripLegIndex));
                }));
              }(),
          },
          onLongPress: () => switch (leg) {
            Link() => openLinkOnMap(),
            TripLeg() => Navigator.push(context, MaterialPageRoute(builder: (context) {
                var journeys = mapJourneys(journeyDetails);
                journeys[i].focus = true;
                return MapWidget(journeys);
              })),
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: leg is Link
                ? _walkFromLeg(leg, before, after, context)
                : _normalLeg(leg as TripLeg, context, bgColor, journeyDetails),
          ),
        ));
  }

  Widget _normalLeg(TripLeg leg, BuildContext context, Color bgColor, JourneyDetails journeyDetails) {
    var tripLegDetails = journeyDetails.tripLegs.firstWhere((l) => l.journeyLegIndex == leg.journeyLegIndex);

    var line = leg.serviceJourney.line;

    return Column(children: [
      Row(
        children: [
          const SizedBox(width: 16),
          lineIconFromLine(line, bgColor, context, shortTrainName: false),
          const SizedBox(width: 16),
          Expanded(
              child: highlightFirstPart(leg.serviceJourney.direction,
                  style: const TextStyle(fontWeight: FontWeight.bold), textScalar: const TextScaler.linear(1.1))),
          accessibilityIcon(line.isWheelchairAccessible, leg.estimatedDepartureTime ?? leg.estimatedArrivalTime,
              margin: const EdgeInsets.only(left: 8)),
        ],
      ),
      displayTSs(leg.notes),
      leg.notes.isEmpty ? const SizedBox(height: 16) : const Divider(),
      _stopHeader(leg, tripLegDetails.origin, true),
      displayTSs(leg.origin.notes),
      const Divider(),
      _legDetail(leg, tripLegDetails, context),
      const Divider(),
      _stopHeader(leg, tripLegDetails.destination, false),
      displayTSs(leg.destination.notes)
    ]);
  }

  Widget _legDetail(TripLeg leg, TripLegDetails legDetails, BuildContext context) {
    Duration duration = leg.arrivalTime.difference(leg.departureTime);
    int numberOfStops = legDetails.destination.index - legDetails.origin.index;
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Row(
        children: [
          const SizedBox(width: 74),
          Text(
              (StringBuffer('${getDurationString(duration)}, $numberOfStops ')
                    ..write((leg.serviceJourney.line.isTrain
                        ? numberOfStops > 1
                            ? 'stationer'
                            : 'station'
                        : numberOfStops > 1
                            ? 'hållplatser'
                            : 'hållplats')))
                  .toString(),
              style: TextStyle(color: Theme.of(context).hintColor))
        ],
      ),
    );
  }

  Widget _walkFromLeg(Link link, JourneyLeg? before, JourneyLeg? after, BuildContext context) {
    bool transfer =
        before is TripLeg && after is TripLeg && before.destination.stopPoint.name == after.origin.stopPoint.name;
    return _walk(transfer ? 'Byte' : 'Gå', transfer ? before.arrivalTime : link.departureTime,
        transfer ? after.departureTime : link.arrivalTime, context, transfer, before, after, link);
  }

  Widget _walk(String text, DateTime start, DateTime end, BuildContext context, bool transfer, JourneyLeg? before,
      JourneyLeg? after, Link? link) {
    bool walkBetweenStops = before is TripLeg && after is TripLeg;
    var duration = walkBetweenStops ? after.departureTime.difference(before.arrivalTime) : end.difference(start);

    IconData icon = transfer ? Icons.transfer_within_a_station : Icons.directions_walk;

    int? walkDistance = link?.distanceInMeters;
    var connectionValidation = getConnectionValidation(before, link, after);

    if (connectionValidation == ConnectionValidation.mediumRisk && !transfer) icon = Icons.directions_run;
    if (connectionValidation == ConnectionValidation.highRisk) icon = Icons.warning;

    return Column(
      children: [
        Row(
          children: [
            Container(
                constraints: const BoxConstraints(minWidth: 64),
                margin: const EdgeInsets.fromLTRB(5, 0, 10, 0),
                child: iconAndText(icon, text, gap: 10, expand: false)),
            Text(getDurationString(duration), style: TextStyle(color: Theme.of(context).hintColor)),
            if (walkDistance != null) Text(', $walkDistance m', style: TextStyle(color: Theme.of(context).hintColor)),
          ],
        ),
        if (duration.inMinutes >= longWaitingTime && before != null && after != null)
          Column(
            children: [
              const Divider(),
              Padding(
                padding: const EdgeInsets.only(left: 5),
                child: iconAndText(Icons.info_outline, 'Längre uppehåll', gap: 10),
              ),
            ],
          ),
        if (before is TripLeg &&
            after is TripLeg &&
            !before.isCancelled &&
            !after.isCancelled &&
            !before.destination.isCancelled &&
            !after.origin.isCancelled)
          Builder(
            builder: (context) {
              var widget = getConnectionValidationWidget(connectionValidation, gap: 10);
              if (widget == null) return Container();
              return Column(
                children: [
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.only(left: 5),
                    child: widget,
                  ),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _stopHeader(TripLeg leg, Call call, bool origin) {
    return stopRow(
        origin
            ? simpleTimeWidget(leg.plannedDepartureTime, leg.departureDelay,
                leg.origin.isCancelled || call.isDepartureCancelled, leg.depState.state)
            : simpleTimeWidget(leg.plannedArrivalTime, leg.arrivalDelay,
                leg.destination.isCancelled || call.isArrivalCancelled, leg.arrState.state),
        origin ? leg.origin.stopPoint.name : leg.destination.stopPoint.name,
        origin ? leg.origin.stopPoint.plannedPlatform : leg.destination.stopPoint.plannedPlatform,
        origin ? leg.origin.stopPoint.estimatedPlatform : leg.destination.stopPoint.estimatedPlatform);
  }

  void _refreshJourney() async {
    var journeyReq = PlaneraResa.reconstructJourney(journey.reconstructionReference);
    var journeyDetailsReq = PlaneraResa.journeyDetails(journey.detailsReference, journeyDetailsIncludes).suppress();

    journey = await journeyReq;
    await setTripLegTrainInfo([journey]);
    var journeyDetails =
        await journeyDetailsReq ?? await PlaneraResa.journeyDetails(journey.detailsReference, journeyDetailsIncludes);
    _streamController.add(journeyDetails);
  }
}

double? getWalkSpeed(int? walkDistance, Duration duration) {
  if (walkDistance == null || duration == Duration.zero) return null;
  return 3.6 * walkDistance / duration.inSeconds; // km/h
}

enum ConnectionValidation { valid, lowRisk, mediumRisk, highRisk }

ConnectionValidation getConnectionValidation(JourneyLeg? before, Link? link, JourneyLeg? after) {
  if (link != null && link is! ConnectionLink) return ConnectionValidation.valid;

  var duration = before is TripLeg && after is TripLeg
      ? after.departureTime.difference(before.arrivalTime)
      : link?.duration ?? Duration.zero;

  var walkSpeed = getWalkSpeed(link?.distanceInMeters, duration);

  var likelyTripToTripTransfer = before is TripLeg &&
      after is TripLeg &&
      before.plannedArrivalTime == after.departureTime &&
      stopAreaFromStopPoint(before.destination.stopPoint.gid) == stopAreaFromStopPoint(after.origin.stopPoint.gid) &&
      !after.isRiskOfMissingConnection;

  if (duration < Duration.zero || walkSpeed != null && walkSpeed > 10) return ConnectionValidation.highRisk;

  if (!likelyTripToTripTransfer && (duration == Duration.zero || walkSpeed != null && walkSpeed > 6)) {
    return ConnectionValidation.mediumRisk;
  }

  if (after is TripLeg && after.isRiskOfMissingConnection && before is TripLeg && before.riskOfMissingConnectionNote) {
    return ConnectionValidation.lowRisk;
  }

  if (!likelyTripToTripTransfer &&
      before is TripLeg &&
      after is TripLeg &&
      !before.plannedArrivalTime.isBefore(after.departureTime)) {
    return ConnectionValidation.lowRisk;
  }

  return ConnectionValidation.valid;
}

Widget? getConnectionValidationWidget(ConnectionValidation connectionValidation,
    {double gap = 5, Color? textColor, bool specificConnection = true}) {
  String text = 'att missa anslutning${specificConnection ? 'en' : ''}';
  return switch (connectionValidation) {
    ConnectionValidation.lowRisk =>
      iconAndText(Icons.error, 'Risk $text', gap: gap, iconColor: Colors.orange, textColor: textColor),
    ConnectionValidation.mediumRisk =>
      iconAndText(Icons.warning, 'Stor risk $text', gap: gap, iconColor: Colors.red, textColor: textColor),
    ConnectionValidation.highRisk =>
      iconAndText(Icons.warning, 'Mycket stor risk $text', gap: gap, iconColor: Colors.red, textColor: textColor),
    ConnectionValidation.valid => null,
  };
}
