import 'dart:async';

import 'package:flutter/material.dart';

import 'map_widget.dart';
import 'reseplaneraren.dart';
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

  JourneyDetail? journeyDetail;

  JourneyDetailWidget(this.journeyDetailRef, this.sname, this.fgColor, this.bgColor, this.direction, this.journeyId,
      this.type, this.name, this.journeyNumber,
      {Key? key})
      : super(key: key);

  final StreamController<JourneyDetailWithTrafficSituations?> _streamController = StreamController();

  Future<void> _handleRefresh() async => _updateJourneyDetail();

  @override
  Widget build(BuildContext context) {
    _updateJourneyDetail();
    var bgLuminance = Theme.of(context).primaryColor.computeLuminance();
    return Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              lineIcon(sname, fgColor, bgColor, bgLuminance, type, name, journeyNumber, context),
              const SizedBox(width: 12),
              Expanded(child: highlightFirstPart(direction, overflow: TextOverflow.fade))
            ],
          ),
          actions: [
            IconButton(
                onPressed: () async {
                  await Navigator.push<MapWidget>(context, MaterialPageRoute(builder: (context) {
                    return MapWidget([
                      journeyDetail != null
                          ? MapJourney(journeyDetail: journeyDetail)
                          : MapJourney(journeyDetailRef: journeyDetailRef)
                    ]);
                  }));
                },
                icon: const Icon(Icons.map))
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () => _handleRefresh(),
          child: StreamBuilder<JourneyDetailWithTrafficSituations?>(
            builder: (context, journeyDetailWithTs) {
              if (journeyDetailWithTs.connectionState == ConnectionState.waiting) return loadingPage();
              if (!journeyDetailWithTs.hasData) return errorPage(() => {_updateJourneyDetail()});
              return CustomScrollView(
                slivers: [
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
        ));
  }

  void _updateJourneyDetail() async {
    var response = await getJourneyDetail(journeyDetailRef, journeyId);
    journeyDetail = response?.journeyDetail;
    _streamController.add(response);
  }
}

bool _isAffectingThisDirection(TrafficSituation ts, Iterable<int> stopIds, Direction direction) {
  if (ts.affectedStopPoints.isEmpty || ts.title.contains('mot ${direction.direction}')) return true;
  return ts.affectedStopPoints.any((s) => stopIds.contains(s.gid));
}

Future<JourneyDetailWithTrafficSituations?> getJourneyDetail(String journeyDetailRef, String journeyId) async {
  var response = reseplaneraren.getJourneyDetail(journeyDetailRef);

  var journeyTs = reseplaneraren.getTrafficSituationsByJourneyId(journeyId);
  var lineTs = reseplaneraren.getTrafficSituationsByLineId(lineIdFromJourneyId(journeyId));

  var journeyDetail = await response;

  if (journeyDetail != null) {
    var stopIds = journeyDetail.stop.map((s) => s.id).toList();
    var filteredLineTs = (await lineTs)?.where((ts) =>
        isPresent(
            ts.startTime, ts.endTime, journeyDetail.stop.first.getDateTime(), journeyDetail.stop.last.getDateTime()) &&
        _isAffectingThisDirection(ts, stopIds, journeyDetail.direction.last));
    filteredLineTs = filteredLineTs?.toList()
      ?..sort((a, b) => getNotePriority(a.severity).compareTo(getNotePriority(b.severity)));
    var severeTs =
        [await journeyTs ?? [], filteredLineTs?.where((ts) => ts.severity == 'severe') ?? []].expand((ts) => ts);
    var normalTs = filteredLineTs?.where((ts) => ts.severity != 'severe') ?? [];

    List<String?> stopNoteIcons = List.filled(journeyDetail.stop.length, null, growable: false);

    filteredLineTs?.forEach((ts) {
      if (ts.affectedStopPoints.length >= stopIds.length) return;
      for (var stop in ts.affectedStopPoints) {
        int i = stopIds.indexWhere((id) => stopAreaFromStopId(id) == stop.stopAreaGid);
        if (i < 0) continue;
        if (stopNoteIcons[i] == null) {
          stopNoteIcons[i] = ts.severity;
        } else if (getNotePriority(ts.severity) < getNotePriority(stopNoteIcons[i]!)) {
          stopNoteIcons[i] = ts.severity;
        }
      }
    });

    return JourneyDetailWithTrafficSituations(
        journeyDetail, severeTs, normalTs, stopNoteIcons.map((s) => s != null ? getNoteIcon(s) : null));
  } else {
    return null;
  }
}

RenderObjectWidget journeyDetailList(JourneyDetail journeyDetail, Iterable<Icon?> stopNoteIcons) {
  List<int> lineChanges = [];

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
        var row = stopRowFromStop(stop,
            alightingOnly: stop.rtDepTime == null &&
                stop.rtArrTime != null &&
                !journeyDetail.journeyId.map((e) => e.routeIdxTo).contains(stop.routeIdx),
            boardingOnly: stop.rtDepTime != null &&
                stop.rtArrTime == null &&
                !journeyDetail.journeyId.map((e) => e.routeIdxFrom).contains(stop.routeIdx) &&
                journeyDetail.stop.elementAt(i - 1).rtDepTime != null,
            noteIcon: stopNoteIcons.elementAt(i),
            constraints: const BoxConstraints(minHeight: 32));
        if ((stop.rtDepTime ?? stop.rtArrTime) == null) {
          row = Opacity(opacity: 0.8, child: row);
        }
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
                            ..write(getValueAtRouteIdx(journeyDetail.direction, stop.routeIdx).direction)
                            ..write('.'))
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
  Iterable<TrafficSituation> importantTs;
  Iterable<TrafficSituation> normalTs;
  Iterable<Icon?> stopNoteIcons;

  JourneyDetailWithTrafficSituations(this.journeyDetail, this.importantTs, this.normalTs, this.stopNoteIcons);
}
