import 'dart:async';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'departure_board_result_widget.dart';
import 'departure_board_widget.dart';
import 'extensions.dart';
import 'map_widget.dart';
import 'network/planera_resa.dart';
import 'network/traffic_situations.dart';
import 'network/trafikverket.dart';
import 'utils.dart';

class JourneyDetailsWidget extends StatefulWidget {
  final DetailsRef detailsReference;

  const JourneyDetailsWidget(this.detailsReference, {super.key});

  @override
  State<JourneyDetailsWidget> createState() => _JourneyDetailsWidgetState();
}

class _JourneyDetailsWidgetState extends State<JourneyDetailsWidget> {
  ServiceJourney get serviceJourney => widget.detailsReference.serviceJourney;

  ServiceJourneyDetails? _serviceJourneyDetails;

  final StreamController<ServiceJourneyDetailsWithTrafficSituations> _streamController = StreamController.broadcast();

  Future<void> _handleRefresh() async => _updateJourneyDetails();

  @override
  void initState() {
    super.initState();
    _updateJourneyDetails();
  }

  @override
  Widget build(BuildContext context) {
    var bgColor = Theme.of(context).primaryColor;
    return Scaffold(
        appBar: AppBar(
          title: StreamBuilder<ServiceJourneyDetailsWithTrafficSituations>(
              stream: _streamController.stream,
              builder: (context, snapshot) {
                var serviceJourneyDetails = snapshot.data?.serviceJourneyDetails;
                var direction = serviceJourney.direction;
                if (serviceJourneyDetails != null && (serviceJourney.isTrain || serviceJourney.origin != null)) {
                  direction = serviceJourneyDetails.serviceJourneys
                      .firstWhere((serviceJourney) => serviceJourney.gid == this.serviceJourney.gid)
                      .direction;
                  if (snapshot.data!.deviation.isNotEmpty) direction += ', ${snapshot.data!.deviation.join(', ')}';
                }
                return Row(
                  children: [
                    lineIconFromLine(serviceJourney.line, bgColor, context, shortTrainName: false),
                    const SizedBox(width: 12),
                    Expanded(child: highlightFirstPart(direction, overflow: TextOverflow.fade))
                  ],
                );
              }),
          actions: [
            IconButton(
                onPressed: () {
                  Navigator.push<MapWidget>(context, MaterialPageRoute(builder: (context) {
                    return MapWidget([
                      _serviceJourneyDetails != null
                          ? MapJourney(serviceJourneyDetails: _serviceJourneyDetails)
                          : MapJourney(journeyDetailsRef: widget.detailsReference)
                    ]);
                  }));
                },
                icon: const Icon(Icons.map))
          ],
        ),
        body: SystemGestureArea(
          MediaQuery.of(context).systemGestureInsets,
          child: RefreshIndicator(
            onRefresh: () => _handleRefresh(),
            child: StreamBuilder<ServiceJourneyDetailsWithTrafficSituations>(
              builder: (context, journeyDetailWithTs) {
                if (journeyDetailWithTs.connectionState == ConnectionState.waiting) return loadingPage();
                if (!journeyDetailWithTs.hasData) {
                  return ErrorPage(_updateJourneyDetails, error: journeyDetailWithTs.error);
                }
                var firstStop = journeyDetailWithTs.data!.serviceJourneyDetails.firstCall!;
                var lastStop = journeyDetailWithTs.data!.serviceJourneyDetails.lastCall!;
                return CustomScrollView(
                  slivers: [
                    if (!firstStop.time.isSameDayAs(DateTime.now()) && !lastStop.time.isSameDayAs(DateTime.now()))
                      dateBar(firstStop.time, margin: 15, showTime: false),
                    SliverSafeArea(
                        sliver: trafficSituationList(journeyDetailWithTs.data!.importantTs,
                            boldTitle: true, padding: const EdgeInsets.fromLTRB(10, 10, 10, 0)),
                        bottom: false),
                    SliverSafeArea(
                        sliver: journeyDetailList(
                            journeyDetailWithTs.data!.serviceJourneyDetails, journeyDetailWithTs.data!.stopNoteIcons),
                        bottom: false),
                    SliverSafeArea(
                      sliver: trafficSituationList(journeyDetailWithTs.data!.normalTs,
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10)),
                    ),
                  ],
                );
              },
              stream: _streamController.stream,
            ),
          ),
        ));
  }

  Future<void> _updateJourneyDetails() async {
    try {
      var response = await getJourneyDetails(widget.detailsReference);
      _serviceJourneyDetails = response.serviceJourneyDetails;
      if (!_streamController.isClosed) _streamController.add(response);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        print(error);
        print(stackTrace);
      }
      if (!_streamController.isClosed) _streamController.addError(error);
    }
  }
}

bool _isAffectingThisDirection(TrafficSituation ts, Iterable<String> stopPointGids, String direction) {
  if (ts.affectedStopPoints.isEmpty || ts.title.contains('mot $direction')) return true;
  return ts.affectedStopPoints.any((stopPoint) => stopPointGids.contains(stopPoint.gid));
}

bool _isAffectingThisJourney(TrafficSituation ts, Iterable<ServiceJourney> serviceJourneys) {
  var gids = serviceJourneys.map((j) => j.gid);
  return ts.affectedJourneys.isEmpty || ts.affectedJourneys.any((j) => gids.contains(j.gid));
}

Future<ServiceJourneyDetailsWithTrafficSituations> getJourneyDetails(DetailsRef detailsReference) async {
  var response = PlaneraResa.details(detailsReference,
      {DepartureDetailsIncludeType.serviceJourneyCalls, DepartureDetailsIncludeType.serviceJourneyCoordinates});

  var serviceJourney = detailsReference.serviceJourney;

  var journeyTsReq = TrafficSituations.getTrafficSituationsForJourney(serviceJourney.gid).suppress();
  var lineTs = TrafficSituations.getTrafficSituationsForLine(lineIdFromJourneyId(serviceJourney.gid)).suppress();

  var serviceJourneysDetails = await response;
  var serviceJourneys = serviceJourneysDetails.serviceJourneys;

  // Get traffic information for all other service journeys
  if (serviceJourneys.length > 1) {
    for (var journey in serviceJourneys.where((j) => j.gid != serviceJourney.gid)) {
      journeyTsReq = journeyTsReq.then((ts) async =>
          ts?.followedBy((await TrafficSituations.getTrafficSituationsForJourney(journey.gid).suppress()) ?? []));
      if (lineIdFromJourneyId(serviceJourney.gid) != lineIdFromJourneyId(journey.gid)) {
        lineTs = lineTs.then((ts) async => ts?.followedBy(
            (await TrafficSituations.getTrafficSituationsForLine(lineIdFromJourneyId(journey.gid)).suppress()) ?? []));
      }
    }
    journeyTsReq = journeyTsReq.then((ts) => ts?.toSet());
    lineTs = lineTs.then((ts) => ts?.toSet());
  }

  var journeyTs = await journeyTsReq;

  var allStops = serviceJourneysDetails.allCalls.toList(growable: false);

  var stopPointGids = allStops.map((s) => s.stopPoint.gid).toList();
  var filteredLineTs = (await lineTs)
      ?.where((ts) =>
          isPresent(ts.startTime, ts.endTime, allStops.first.time, allStops.last.time) &&
          _isAffectingThisDirection(ts, stopPointGids, serviceJourneys.last.direction) &&
          _isAffectingThisJourney(ts, serviceJourneys) &&
          (journeyTs?.every((jts) => jts.situationNumber != ts.situationNumber) ?? true))
      .sortTs(allStops.first.time);
  Iterable<TS> severeTs = [
    journeyTs?.where((ts) => isPresent(
            ts.startTime, ts.endTime, allStops.first.time.startOfDay(), allStops.first.time.startOfNextDay())) ??
        [],
    filteredLineTs?.where((ts) => ts.severity == Severity.high) ?? []
  ].expand((ts) => ts);
  Iterable<TS> normalTs = filteredLineTs?.where((ts) => ts.severity != Severity.high).cast() ?? [];

  List<Severity?> stopNoteIcons = List.filled(allStops.length, null, growable: false);

  filteredLineTs?.followedBy(journeyTs ?? []).forEach((ts) {
    if (ts.affectedStopPoints.length >= stopPointGids.length) return;
    for (var stop in ts.affectedStopPoints) {
      int i = stopPointGids.indexWhere((stopPointGid) => stopAreaFromStopPoint(stopPointGid) == stop.stopAreaGid);
      if (i < 0) continue;
      stopNoteIcons[i] = maxOrNull(stopNoteIcons[i], ts.severity);
    }
  });

  var notes = <TS>{};
  Iterable<String> deviation = [];

  if (serviceJourney.isTrain) {
    List<Set<String>?> stopNotesLowPriority = List.filled(allStops.length, null, growable: false);
    List<Set<String>?> stopNotesNormalPriority = List.filled(allStops.length, null, growable: false);
    Map<String, int> locationSignatureToStopIdx = {};

    var trainJourney = await Trafikverket.getTrainJourney(
        serviceJourney.line.trainNumber!, allStops.first.plannedDepartureTime!, allStops.last.plannedArrivalTime!);
    if (trainJourney == null) {
      normalTs = normalTs.followedBy([Note('Kunde inte hämta information från Trafikverket')]);
    } else {
      List<JourneyPartNote> journeyPartNotes = [];

      setTrainInfo(trainJourney, allStops, stopNotesLowPriority, stopNotesNormalPriority, locationSignatureToStopIdx);

      for (int stop = 0; stop < allStops.length; stop++) {
        for (String description in stopNotesNormalPriority[stop] ?? {}) {
          if (journeyPartNotes.any((n) => n.match(description, stop))) continue;

          int end = stop;
          for (; stopNotesNormalPriority.tryElementAt(end + 1)?.contains(description) ?? false; end++) {}

          journeyPartNotes.add(JourneyPartNote(description, stop, min(end, allStops.length - 1), Severity.normal));
        }
      }

      for (int stop = 0; stop < allStops.length; stop++) {
        for (String description in stopNotesLowPriority[stop] ?? {}) {
          if (journeyPartNotes.any((n) => n.match(description, stop))) continue;
          if (description.contains('tannar i ') ||
              description.contains('tannar vid') ||
              description.contains('tannar även')) {
            continue;
          }

          int end = stop;
          for (; stopNotesLowPriority.tryElementAt(end + 1)?.contains(description) ?? false; end++) {}

          journeyPartNotes.add(JourneyPartNote(description, stop, min(end, allStops.length - 1), Severity.low));
        }
      }

      // Combine notes
      List<JourneyPartNote> combinedNotes = [];
      for (int i = 0; i < journeyPartNotes.length; i++) {
        var current = journeyPartNotes[i];
        var next = journeyPartNotes.tryElementAt(i + 1);

        String text = current.text;

        while (current.start == next?.start && current.end == next?.end && current.severity == next?.severity) {
          var lastChar = text.characters.last;
          if (lastChar == ',' || lastChar == '.') {
            text += ' ${next!.text}';
          } else {
            text += ', ${next!.text}';
          }
          next = journeyPartNotes.tryElementAt(++i + 1);
        }

        combinedNotes.add(JourneyPartNote(text, current.start, current.end, current.severity));
      }
      journeyPartNotes = combinedNotes;

      for (var note in journeyPartNotes) {
        String text;

        if (note.start == note.end) {
          text = '${shortStationName(allStops[note.start].stopPoint.name)}: ${note.text}';
          if (note.text != 'Spårändrat') {
            stopNoteIcons[note.start] = maxOrNull(stopNoteIcons[note.start], note.severity);
          }
        } else if (note.start == 0 && note.end >= allStops.length - 2) {
          text = note.text;
        } else if (note.text.contains('gäller') || note.text.contains('kontoladdning')) {
          text = note.text;
        } else {
          text = '${shortStationName(allStops[note.start].stopPoint.name)}–'
              '${shortStationName(allStops[note.end].stopPoint.name)}: ${note.text}';
          if (note.text != 'Spårändrat') {
            for (int i = note.start; i <= note.end; i++) {
              stopNoteIcons[i] = maxOrNull(stopNoteIcons[i], note.severity);
            }
          }
        }

        notes.add(Note(text, note.severity));
      }

      if (trainJourney.isNotEmpty) {
        notes
          ..addAll(trainJourney.map((t) => t.booking).expand((d) => d.map((text) => Note(text))))
          ..addAll(trainJourney.map((t) => t.service).expand((d) => d.map((text) => Note(text))))
          ..addAll(trainJourney.map((t) => t.trainComposition).expand((d) => d.map((text) => Note(text))));

        var trainMessages = await Trafikverket.getTrainMessage(
            trainJourney.map((t) => t.locationSignature).toSet(), allStops.first.time, allStops.last.time);

        if (trainMessages != null) {
          trainMessages = trainMessages.where(
              (msg) => msg.severities.keys.toSet().intersection(locationSignatureToStopIdx.keys.toSet()).length >= 3);
          notes.addAll(trainMessages);

          for (var msg in trainMessages.whereType<TrafficImpact>()) {
            if (msg.severities.keys.toSet().containsAll(locationSignatureToStopIdx.keys)) continue;

            msg.severities.forEach((sig, severity) {
              var idx = locationSignatureToStopIdx[sig];
              if (idx != null) stopNoteIcons[idx] = maxOrNull(stopNoteIcons[idx], severity);
            });
          }
        }

        normalTs = normalTs.followedBy(notes);
      }

      deviation = journeyPartNotes
          .where((note) => note.start == 0 && note.end >= allStops.length - 2 && note.severity == Severity.normal)
          .map((note) => note.text);
    }
  }

  return ServiceJourneyDetailsWithTrafficSituations(serviceJourneysDetails, severeTs.toSet(), normalTs.toSet(),
      stopNoteIcons.map((s) => s != null ? getNoteIcon(s) : null), deviation);
}

class JourneyPartNote {
  String text;
  int start;
  int end;
  Severity severity;

  JourneyPartNote(this.text, this.start, this.end, this.severity);

  bool match(String text, int stop) {
    return this.text == text && stop >= start && stop <= end;
  }
}

RenderObjectWidget journeyDetailList(ServiceJourneyDetails serviceJourneyDetails, Iterable<Icon?> stopNoteIcons,
    {void Function(BuildContext, Call)? onTap, void Function(BuildContext, Call)? onLongPress}) {
  Iterable<Call> allStops = serviceJourneyDetails.allCalls;

  List<int> startOfServiceIndexes = serviceJourneyDetails.serviceJourneys
      .map((serviceJourney) => serviceJourney.callsOnServiceJourney!.first.index)
      .toList(growable: false);
  bool useHintColor = allStops.any((s) => (s.estimatedDepartureTime ?? s.estimatedArrivalTime) != null);

  Set<int> firstOrLastStopIndexes = serviceJourneyDetails.serviceJourneys
      .map((serviceJourney) =>
          [serviceJourney.callsOnServiceJourney!.first.index, serviceJourney.callsOnServiceJourney!.last.index])
      .flattened
      .toSet();

  bool noteIconWithoutPlatform = IterableZip([allStops, stopNoteIcons]).every((pair) {
    var (call, icon) = (pair[0] as Call, pair[1] as Icon?);
    return icon == null || call.platform.isEmpty;
  });

  return SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    sliver: SeparatedSliverList(
      itemCount: allStops.length,
      separatorBuilder: (context, i) => const Divider(height: 0),
      itemBuilder: (context, i) {
        var stop = allStops.elementAt(i);
        var isFirstOrLastStop = firstOrLastStopIndexes.contains(stop.index);
        var isTrain = serviceJourneyDetails.serviceJourneys.first.isTrain;
        var row = InkWell(
            onTap: onTap != null
                ? () => onTap(context, stop)
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => DepartureBoardResultWidget(StopLocation.fromStopPoint(stop.stopPoint),
                            stop.improvedArrivalTimeEstimation, departureBoardOptions))),
            onLongPress: onLongPress != null
                ? () => onLongPress(context, stop)
                : () => Navigator.push<MapWidget>(
                    context,
                    MaterialPageRoute(
                        builder: (context) => MapWidget([MapJourney(serviceJourneyDetails: serviceJourneyDetails)],
                            focusStopPoints: [stop.stopPoint.gid]))),
            child: stopRowFromStop(stop,
                alightingOnly: stop.platform.isEmpty &&
                    !stop.isCancelled &&
                    !isFirstOrLastStop &&
                    !isTrain &&
                    (validTimeInterval == null ||
                        (stop.plannedDepartureTime?.isBefore(validTimeInterval!.validUntil) ?? true)),
                boardingOnly: stop.plannedArrivalTime == null && !stop.isCancelled && !isFirstOrLastStop && !isTrain,
                noteIcon: stopNoteIcons.elementAt(i),
                noteIconWithoutPlatform: noteIconWithoutPlatform,
                constraints: const BoxConstraints(minHeight: 32),
                useHintColor: useHintColor));
        if (startOfServiceIndexes.length > 1 && startOfServiceIndexes.contains(stop.index)) {
          var serviceJourney =
              serviceJourneyDetails.serviceJourneys.elementAt(startOfServiceIndexes.indexOf(stop.index));
          var text = Padding(
              padding: const EdgeInsets.all(15),
              child: Text(
                  (StringBuffer(i == 0 ? 'Börjar' : 'Fortsätter')
                        ..write(' som linje ')
                        ..write(serviceJourney.line.name)
                        ..write(' mot ')
                        ..write(serviceJourney.direction))
                      .toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).hintColor)));
          return Column(children: i == 0 ? [text, const Divider(height: 0), row] : [row, text]);
        }
        return row;
      },
    ),
  );
}

class ServiceJourneyDetailsWithTrafficSituations {
  ServiceJourneyDetails serviceJourneyDetails;
  Iterable<TS> importantTs;
  Iterable<TS> normalTs;
  Iterable<Icon?> stopNoteIcons;
  Iterable<String> deviation;

  ServiceJourneyDetailsWithTrafficSituations(
      this.serviceJourneyDetails, this.importantTs, this.normalTs, this.stopNoteIcons, this.deviation);
}
