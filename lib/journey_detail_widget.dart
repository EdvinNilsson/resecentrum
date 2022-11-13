import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'departure_board_result_widget.dart';
import 'departure_board_widget.dart';
import 'extensions.dart';
import 'map_widget.dart';
import 'reseplaneraren.dart';
import 'trafikverket.dart';
import 'utils.dart';

class JourneyDetailWidget extends StatelessWidget {
  final String journeyDetailRef;
  final String sname;
  final Color fgColor;
  final Color bgColor;
  final String type;
  final String name;
  final int? journeyNumber;
  final String direction;
  final String journeyId;
  final int evaId;
  final DateTime evaDateTime;

  JourneyDetail? journeyDetail;

  JourneyDetailWidget(this.journeyDetailRef, this.sname, this.fgColor, this.bgColor, this.direction, this.journeyId,
      this.type, this.name, this.journeyNumber, this.evaId, this.evaDateTime,
      {Key? key})
      : super(key: key);

  final StreamController<JourneyDetailWithTrafficSituations> _streamController = StreamController.broadcast();

  Future<void> _handleRefresh() async => _updateJourneyDetail();

  @override
  Widget build(BuildContext context) {
    _updateJourneyDetail();
    var bgLuminance = Theme.of(context).primaryColor.computeLuminance();
    return Scaffold(
        appBar: AppBar(
          title: StreamBuilder<JourneyDetailWithTrafficSituations>(
              stream: _streamController.stream,
              builder: (context, snapshot) {
                var journeyDetail = snapshot.data?.journeyDetail;
                var direction = this.direction;
                if (journeyDetail != null) {
                  var idx = journeyDetail.stop.firstWhere((s) => s.id == evaId).routeIdx;
                  direction =
                      getValueAtRouteIdxWithJid(journeyDetail.direction, idx, journeyId, journeyDetail.journeyId)
                          .direction;
                  if (snapshot.data!.deviation.isNotEmpty) direction += ', ${snapshot.data!.deviation.join(', ')}';
                }
                return Row(
                  children: [
                    lineIcon(sname, fgColor, bgColor, bgLuminance, type, name, journeyNumber, context),
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
                      journeyDetail != null
                          ? MapJourney(journeyDetail: journeyDetail)
                          : MapJourney(
                              journeyDetailRef: JourneyDetailRef(
                                  journeyDetailRef, journeyId, journeyNumber, type, evaId, evaDateTime))
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
            child: StreamBuilder<JourneyDetailWithTrafficSituations>(
              builder: (context, journeyDetailWithTs) {
                if (journeyDetailWithTs.connectionState == ConnectionState.waiting) return loadingPage();
                if (!journeyDetailWithTs.hasData) {
                  return ErrorPage(_updateJourneyDetail, error: journeyDetailWithTs.error);
                }
                return CustomScrollView(
                  slivers: [
                    if (!journeyDetailWithTs.data!.journeyDetail.stop.first.getDateTime().isSameDayAs(DateTime.now()) &&
                        !journeyDetailWithTs.data!.journeyDetail.stop.last.getDateTime().isSameDayAs(DateTime.now()))
                      dateBar(journeyDetailWithTs.data!.journeyDetail.stop.first.getDateTime(),
                          margin: 15, showTime: false),
                    SliverSafeArea(
                        sliver: trafficSituationList(journeyDetailWithTs.data!.importantTs,
                            boldTitle: true, padding: const EdgeInsets.fromLTRB(10, 10, 10, 0)),
                        bottom: false),
                    SliverSafeArea(
                        sliver: journeyDetailList(
                            journeyDetailWithTs.data!.journeyDetail, journeyDetailWithTs.data!.stopNoteIcons),
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

  Future<void> _updateJourneyDetail() async {
    try {
      var response = await getJourneyDetail(journeyDetailRef, journeyId, journeyNumber, type, evaId, evaDateTime);
      journeyDetail = response.journeyDetail;
      _streamController.add(response);
    } catch (error) {
      _streamController.addError(error);
    }
  }
}

bool _isAffectingThisDirection(TrafficSituation ts, Iterable<int> stopIds, Direction direction) {
  if (ts.affectedStopPoints.isEmpty || ts.title.contains('mot ${direction.direction}')) return true;
  return ts.affectedStopPoints.any((s) => stopIds.contains(s.gid));
}

bool _isAffectingThisJourney(TrafficSituation ts, Iterable<JourneyId> journeyIds) {
  var ids = journeyIds.map((j) => j.id);
  return ts.affectedJourneys.isEmpty || ts.affectedJourneys.any((j) => ids.contains(j.gid));
}

Future<JourneyDetailWithTrafficSituations> getJourneyDetail(
    String journeyDetailRef, String journeyId, int? journeyNumber, String type, int evaId, DateTime evaDateTime) async {
  var response = reseplaneraren.getJourneyDetail(journeyDetailRef);

  Future<void>? cancelledStops;
  if (!isTrainType(type)) cancelledStops = reseplaneraren.setCancelledStops(evaDateTime, evaId, response);

  var journeyTs = reseplaneraren.getTrafficSituationsByJourneyId(journeyId).suppress();
  var lineTs = reseplaneraren.getTrafficSituationsByLineId(lineIdFromJourneyId(journeyId)).suppress();

  var journeyDetail = await response;

  if (journeyDetail.journeyId.length > 1) {
    for (var journey in journeyDetail.journeyId.where((j) => j.id != journeyId)) {
      journeyTs = journeyTs.then((ts) async =>
          ts?.followedBy((await reseplaneraren.getTrafficSituationsByJourneyId(journey.id).suppress()) ?? []));
      lineTs = lineTs.then((ts) async => ts?.followedBy(
          (await reseplaneraren.getTrafficSituationsByLineId(lineIdFromJourneyId(journey.id)).suppress()) ?? []));
    }
    journeyTs = journeyTs.then((ts) => ts?.toSet());
    lineTs = lineTs.then((ts) => ts?.toSet());
  }

  var stopIds = journeyDetail.stop.map((s) => s.id).toList();
  var filteredLineTs = (await lineTs)
      ?.where((ts) =>
          isPresent(ts.startTime, ts.endTime, journeyDetail.stop.first.getDateTime(),
              journeyDetail.stop.last.getDateTime()) &&
          _isAffectingThisDirection(ts, stopIds, journeyDetail.direction.last) &&
          _isAffectingThisJourney(ts, journeyDetail.journeyId))
      .sortTs(journeyDetail.stop.first.getDateTime());
  Iterable<TS> severeTs = [
    (await journeyTs)?.where((ts) => isPresent(
            ts.startTime,
            ts.endTime,
            journeyDetail.stop.first.getDateTime().startOfDay(),
            journeyDetail.stop.first.getDateTime().startOfDay().add(const Duration(days: 1)))) ??
        [],
    filteredLineTs?.where((ts) => ts.severity == 'severe') ?? []
  ].expand((ts) => ts);
  Iterable<TS> normalTs = filteredLineTs?.where((ts) => ts.severity != 'severe').cast() ?? [];

  List<String?> stopNoteIcons = List.filled(journeyDetail.stop.length, null, growable: false);

  filteredLineTs?.forEach((ts) {
    if (ts.affectedStopPoints.length >= stopIds.length) return;
    for (var stop in ts.affectedStopPoints) {
      int i = stopIds.indexWhere((id) => stopAreaFromStopId(id) == stop.stopAreaGid);
      if (i < 0) continue;
      stopNoteIcons[i] = getHighestPriority(stopNoteIcons[i], ts.severity);
    }
  });

  var notes = <TS>{};
  Iterable<String> deviation = [];

  if (isTrainType(type)) {
    List<Set<String>?> stopNotesLowPriority = List.filled(journeyDetail.stop.length, null, growable: false);
    List<Set<String>?> stopNotesNormalPriority = List.filled(journeyDetail.stop.length, null, growable: false);
    var trainJourney = await trafikverket.getTrainJourney(
        journeyNumber!, journeyDetail.stop.first.depDateTime!, journeyDetail.stop.last.arrDateTime!);
    if (trainJourney == null) {
      normalTs = normalTs.followedBy([Note(0, 'low', 'Kunde inte hämta information från Trafikverket')]);
    } else {
      List<Stop> stops = journeyDetail.stop.toList(growable: false);

      List<JourneyPartNote> journeyPartNotes = [];

      setTrainInfo(trainJourney, stops, stopNotesLowPriority, stopNotesNormalPriority);

      for (int stop = 0; stop < journeyDetail.stop.length; stop++) {
        for (String description in stopNotesNormalPriority[stop] ?? {}) {
          if (journeyPartNotes.any((n) => n.match(description, stop))) continue;

          int end = stop;
          for (; stopNotesNormalPriority.tryElementAt(end + 1)?.contains(description) ?? false; end++) {}

          journeyPartNotes.add(JourneyPartNote(description, stop, min(end, stops.length - 1), 'normal'));
        }
      }

      for (int stop = 0; stop < journeyDetail.stop.length; stop++) {
        for (String description in stopNotesLowPriority[stop] ?? {}) {
          if (journeyPartNotes.any((n) => n.match(description, stop))) continue;
          if (description.contains('tannar i ') ||
              description.contains('tannar vid') ||
              description.contains('tannar även')) continue;

          int end = stop;
          for (; stopNotesLowPriority.tryElementAt(end + 1)?.contains(description) ?? false; end++) {}

          journeyPartNotes.add(JourneyPartNote(description, stop, min(end, stops.length - 1), 'low'));
        }
      }

      // Combine notes
      List<JourneyPartNote> combinedNotes = [];
      for (int i = 0; i < journeyPartNotes.length; i++) {
        var current = journeyPartNotes[i];
        var next = journeyPartNotes.tryElementAt(i + 1);

        String text = current.text;

        while (current.start == next?.start && current.end == next?.end && current.priority == next?.priority) {
          var lastChar = text.characters.last;
          if (lastChar == ',' || lastChar == '.') {
            text += ' ${next!.text}';
          } else {
            text += ', ${next!.text}';
          }
          next = journeyPartNotes.tryElementAt(++i + 1);
        }

        combinedNotes.add(JourneyPartNote(text, current.start, current.end, current.priority));
      }
      journeyPartNotes = combinedNotes;

      for (var note in journeyPartNotes) {
        String text;

        if (note.start == note.end) {
          text = '${shortStationName(stops[note.start].name)}: ${note.text}';
          if (note.text != 'Spårändrat') {
            stopNoteIcons[note.start] = getHighestPriority(stopNoteIcons[note.start], note.priority);
          }
        } else if (note.start == 0 && note.end >= stops.length - 2) {
          text = note.text;
        } else if (note.text.contains('gäller') || note.text.contains('kontoladdning')) {
          text = note.text;
        } else {
          text = '${shortStationName(stops[note.start].name)}–${shortStationName(stops[note.end].name)}: ${note.text}';
          if (note.text != 'Spårändrat') {
            for (int i = note.start; i <= note.end; i++) {
              stopNoteIcons[i] = getHighestPriority(stopNoteIcons[i], note.priority);
            }
          }
        }

        notes.add(Note(0, note.priority, text));
      }

      if (trainJourney.isNotEmpty) {
        var lastReport = trainJourney.lastWhereOrNull((t) => t.timeAtLocation != null);
        if (lastReport != null) {
          var lastStopIndex = stops.indexWhere((s) =>
              (lastReport.activityType == 'Ankomst' ? s.arrDateTime : s.depDateTime)
                  ?.isAtSameMomentAs(lastReport.advertisedTimeAtLocation) ??
              false);
          for (int i = 0; i < lastStopIndex; i++) {
            stops[i].rtArrTime = null;
            stops[i].rtDepTime = null;
          }
        }

        notes
          ..addAll(trainJourney.map((t) => t.booking).expand((d) => d.map((text) => Note(0, 'low', text))))
          ..addAll(trainJourney.map((t) => t.service).expand((d) => d.map((text) => Note(0, 'low', text))))
          ..addAll(trainJourney.map((t) => t.trainComposition).expand((d) => d.map((text) => Note(0, 'low', text))));

        notes.addAll((await trafikverket.getTrainMessage(
                trainJourney.map((t) => t.locationSignature), stops.first.getDateTime(), stops.last.getDateTime())) ??
            <TrainMessage>[]);

        normalTs = normalTs.followedBy(notes);
      }

      journeyDetail.stop = stops;

      deviation = journeyPartNotes
          .where((note) => note.start == 0 && note.end >= stops.length - 2 && note.priority == 'normal')
          .map((note) => note.text);
    }
  }

  await cancelledStops;

  return JourneyDetailWithTrafficSituations(journeyDetail, severeTs.toSet(), normalTs.toSet(),
      stopNoteIcons.map((s) => s != null ? getNoteIcon(s) : null), deviation);
}

class JourneyPartNote {
  String text;
  int start;
  int end;
  String priority;

  JourneyPartNote(this.text, this.start, this.end, this.priority);

  bool match(String text, int stop) {
    return this.text == text && stop >= start && stop <= end;
  }
}

RenderObjectWidget journeyDetailList(JourneyDetail journeyDetail, Iterable<Icon?> stopNoteIcons,
    {void Function(BuildContext, Stop)? onTap}) {
  List<int> lineChanges = [];
  bool useHintColor = journeyDetail.stop.any((s) => (s.rtArrTime ?? s.rtDepTime) != null);

  if (journeyDetail.journeyName.length > 1) {
    String? previousName = journeyDetail.journeyName.first.name;
    for (var journeyName in journeyDetail.journeyName) {
      if (journeyName.name != previousName) lineChanges.add(journeyName.routeIdxFrom);
      previousName = journeyName.name;
    }
  }

  return SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    sliver: SeparatedSliverList(
      itemCount: journeyDetail.stop.length,
      separatorBuilder: (context, i) => const Divider(height: 0),
      itemBuilder: (context, i) {
        var stop = journeyDetail.stop.elementAt(i);
        var row = InkWell(
            onTap: onTap != null
                ? () => onTap(context, stop)
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => DepartureBoardResultWidget(
                            StopLocation.fromStop(stop), stop.getDateTime(), departureBoardOptions))),
            child: stopRowFromStop(stop,
                alightingOnly: stop.rtDepTime == null &&
                    stop.rtArrTime != null &&
                    !journeyDetail.journeyId.map((e) => e.routeIdxTo).contains(stop.routeIdx),
                boardingOnly: stop.rtDepTime != null &&
                    stop.rtArrTime == null &&
                    !journeyDetail.journeyId.map((e) => e.routeIdxFrom).contains(stop.routeIdx) &&
                    journeyDetail.stop.elementAt(i - 1).rtDepTime != null,
                noteIcon: stopNoteIcons.elementAt(i),
                constraints: const BoxConstraints(minHeight: 32),
                useHintColor: useHintColor));
        if (lineChanges.isNotEmpty) {
          int j = lineChanges.indexOf(stop.routeIdx);
          if (j >= 0 || i == 0) {
            return Column(children: [
              Padding(
                  padding: const EdgeInsets.all(15),
                  child: Text(
                      (StringBuffer(i == 0 ? 'Börjar' : 'Fortsätter')
                            ..write(' som linje ')
                            ..write(getValueAtRouteIdx(journeyDetail.journeyName, stop.routeIdx).name)
                            ..write(' mot ')
                            ..write(getValueAtRouteIdx(journeyDetail.direction, stop.routeIdx).direction))
                          .toString(),
                      textAlign: TextAlign.center)),
              const Divider(height: 0),
              row
            ]);
          }
        }
        return row;
      },
    ),
  );
}

class JourneyDetailWithTrafficSituations {
  JourneyDetail journeyDetail;
  Iterable<TS> importantTs;
  Iterable<TS> normalTs;
  Iterable<Icon?> stopNoteIcons;
  Iterable<String> deviation;

  JourneyDetailWithTrafficSituations(
      this.journeyDetail, this.importantTs, this.normalTs, this.stopNoteIcons, this.deviation);
}
