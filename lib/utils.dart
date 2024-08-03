import 'dart:async';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' hide binarySearch;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:maplibre_gl/maplibre_gl.dart' hide Line;
import 'package:url_launcher/url_launcher.dart';

import 'extensions.dart';
import 'network/mgate.dart';
import 'network/planera_resa.dart';
import 'network/trafikverket.dart';
import 'network/vehicle_positions.dart';

typedef Json = Map<String, dynamic>;

String getDelayString(int? delay, {DepartureState? state}) {
  if (state == DepartureState.unknownTime) return '+?';
  if (delay == null) return '';
  String str = delay.abs() < 60 ? delay.toString() : '${delay ~/ 60}h${delay % 60 != 0 ? delay.abs() % 60 : ''}';
  return delay < 0 ? str : '+$str';
}

bool hasDeparted(VehiclePosition vehicle, LatLng position) {
  var distance = distanceBetween(vehicle.position, position);
  if ((distance > 150 || vehicle.speedOrZero > 20) &&
      vehicle.updatedAt.difference(DateTime.now()) < const Duration(minutes: 1)) return true;
  return false;
}

Text _countdownText(String text, {TextStyle? style}) =>
    Text(text, textAlign: TextAlign.center, style: style ?? const TextStyle(fontWeight: FontWeight.bold));

Widget getCountdown(Departure departure) {
  return Builder(builder: (context) {
    if (departure.state == DepartureState.replacementBus) {
      return _countdownText('Buss', style: TextStyle(color: orange(context)));
    }
    if (departure.state == DepartureState.replacementTaxi) {
      return _countdownText('Taxi', style: const TextStyle(color: Colors.red));
    }
    if (departure.isCancelled) return _countdownText('Inst.', style: const TextStyle(color: Colors.red));
    if (departure.state == DepartureState.unknownTime) return _countdownText('?');
    if (departure.state == DepartureState.departed) return _countdownText('Avg.', style: const TextStyle());
    if (departure.state == DepartureState.atStation) return _countdownText('nu');

    var realtime = departure.estimatedTime != null;
    var timeLeft = departure.time.difference(DateTime.now());
    var minutesLeft = timeLeft.minutesRounded();
    if (minutesLeft.abs() >= 100) {
      if (minutesLeft.abs() >= 5940) {
        int daysLeft = departure.time.startOfDay().difference(DateTime.now().startOfDay()).inDays;
        return _countdownText('${daysLeft}d');
      } else {
        return _countdownText('${timeLeft.hoursRounded()}h');
      }
    }
    if (!realtime && minutesLeft > 0) return _countdownText('ca $minutesLeft');
    if (minutesLeft == 0 || minutesLeft == -1) return _countdownText('nu');
    return _countdownText(minutesLeft.toString());
  });
}

int? getDelay(DateTime dateTime, DateTime? rtDateTime) => rtDateTime?.difference(dateTime).inMinutes;

String getDurationString(Duration duration) {
  return duration.inHours > 0
      ? (duration.minutesRounded() % 60 == 0
          ? '${duration.inHours} h'
          : '${duration.inHours} h ${duration.minutesRounded() % 60} min')
      : '${duration.minutesRounded()} min';
}

String getDistanceString(int distance) {
  return distance < 1000 ? '${distance.round()} m' : '${NumberFormat('#.#').format(distance / 1000)} km';
}

String getTripCountdown(DateTime? departureTime, TripLeg? leg, bool isDeparted) {
  if (departureTime == null) return '';
  var timeLeft = departureTime.difference(DateTime.now());
  var minutesLeft = timeLeft.minutesRounded();
  if (minutesLeft.abs() > 1440) return ', ${DateFormat.MMMMEEEEd().format(departureTime)}';
  if (leg?.depState.state == DepartureState.unknownTime) return ', invänta tid';
  if (minutesLeft < -1 || (isDeparted && leg?.estimatedDepartureTime == null)) return ', avgått';
  if (minutesLeft > 0) return ', om ${getDurationString(timeLeft)}';
  return ', nu';
}

Widget stopRowFromStop(Call stop,
    {bool bold = false,
    bool alightingOnly = false,
    bool boardingOnly = false,
    Icon? noteIcon,
    bool noteIconWithoutPlatform = false,
    BoxConstraints? constraints,
    bool useHintColor = false}) {
  return Builder(builder: (context) {
    var textSpans = <TextSpan>[];

    void addTimeText(DateTime time, DateTime? rtTime, bool cancelled, DepartureState state) {
      TextStyle style = TextStyle(color: rtTime == null && useHintColor ? Theme.of(context).hintColor : null);
      if (state == DepartureState.replacementBus) {
        style = style.copyWith(color: orange(context));
      } else if (cancelled) {
        style = style.merge(cancelledTextStyle);
      }

      textSpans.add(TextSpan(text: time.time(), style: style.copyWith(fontWeight: FontWeight.bold)));
      if (rtTime != null) {
        textSpans.add(TextSpan(text: getDelayString(getDelay(time, rtTime), state: state), style: style));
      }
    }

    if (stop.plannedDepartureTime != null &&
        stop.plannedArrivalTime != null &&
        (stop.plannedDepartureTime != stop.plannedArrivalTime ||
            ((stop.isDepartureCancelled != stop.isArrivalCancelled || stop.arrState.state != stop.depState.state) &&
                !alightingOnly &&
                !boardingOnly) ||
            (stop.estimatedDepartureTime != null &&
                stop.estimatedArrivalTime != null &&
                stop.estimatedDepartureTime!.difference(stop.estimatedArrivalTime!) > const Duration(minutes: 1)))) {
      addTimeText(stop.plannedArrivalTime!, stop.estimatedArrivalTime, stop.isArrivalCancelled, stop.arrState.state);
      textSpans.add(const TextSpan(text: '\n'));
      addTimeText(
          stop.plannedDepartureTime!, stop.estimatedDepartureTime, stop.isDepartureCancelled, stop.depState.state);
    } else {
      addTimeText(
          stop.plannedDepartureTime ?? stop.plannedArrivalTime!,
          stop.estimatedDepartureTime ?? stop.estimatedArrivalTime,
          stop.plannedDepartureTime != null ? stop.isDepartureCancelled : stop.isArrivalCancelled,
          stop.plannedDepartureTime == null ? stop.arrState.state : stop.depState.state);
    }

    var text = Text.rich(TextSpan(text: '', children: textSpans));

    return stopRow(text, stop.stopPoint.name, stop.plannedPlatform, stop.estimatedPlatform,
        bold: bold,
        alightingOnly: alightingOnly,
        boardingOnly: boardingOnly,
        noteIcon: noteIcon,
        noteIconWithoutPlatform: noteIconWithoutPlatform,
        constraints: constraints,
        rtInfo: !useHintColor || (stop.estimatedDepartureTime ?? stop.estimatedArrivalTime) != null);
  });
}

Widget simpleTimeWidget(DateTime dateTime, int? delay, bool cancelled, DepartureState? state,
    {bool bold = true, bool multiline = false, bool useHintColor = false, bool walk = false}) {
  return Builder(builder: (context) {
    TextStyle style = cancelled
        ? state == DepartureState.replacementBus
            ? TextStyle(color: orange(context))
            : cancelledTextStyle
        : TextStyle(
            color: useHintColor &&
                    delay == null &&
                    dateTime.isSameTransportDayAs(DateTime.now()) &&
                    walk.implies(dateTime.isBefore(DateTime.now()))
                ? Theme.of(context).hintColor
                : null);

    String delayString = getDelayString(delay, state: state);
    var children = [
      Text(dateTime.time(), style: bold ? style.copyWith(fontWeight: FontWeight.bold) : style),
      if (delayString.isNotEmpty) Text(delayString, style: style),
    ];

    return multiline
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)
        : Row(children: children);
  });
}

Widget stopRow(Widget time, String name, String? plannedPlatform, String? estimatedPlatform,
    {bool bold = false,
    bool alightingOnly = false,
    bool boardingOnly = false,
    Icon? noteIcon,
    bool noteIconWithoutPlatform = false,
    BoxConstraints? constraints,
    bool rtInfo = true}) {
  String stopName = name.firstPart();
  if (alightingOnly) stopName = '$stopName (endast avstigning)';
  if (boardingOnly) stopName = '$stopName (endast påstigning)';
  return Builder(builder: (context) {
    return Container(
        constraints: constraints,
        margin: const EdgeInsets.all(5),
        child: Row(
          children: [
            Container(
                constraints: const BoxConstraints(minWidth: 64), margin: const EdgeInsets.only(right: 10), child: time),
            Expanded(
                child: Text(stopName,
                    overflow: TextOverflow.fade,
                    style: TextStyle(
                        fontWeight: bold ? FontWeight.bold : null,
                        color: !rtInfo ? Theme.of(context).hintColor : null))),
            if (noteIcon != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                child: noteIcon,
              ),
            if (!noteIconWithoutPlatform || !plannedPlatform.isNullOrEmpty)
              Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  child: estimatedPlatform != null
                      ? trackChange(estimatedPlatform)
                      : Text(estimatedPlatform ?? plannedPlatform ?? '',
                          textAlign: TextAlign.right,
                          style: !rtInfo ? TextStyle(color: Theme.of(context).hintColor) : null))
          ],
        ));
  });
}

Widget accessibilityIcon(bool isWheelchairAccessible, DateTime? estimatedTime,
        {EdgeInsetsGeometry? margin, TransportMode? transportMode}) =>
    !isWheelchairAccessible && estimatedTime != null && transportMode != TransportMode.train
        ? Container(margin: margin, child: const Icon(Icons.not_accessible))
        : Container();

Icon getNoteIcon(Severity severity, {bool infoOutline = true}) => switch (severity) {
      Severity.low => Icon(infoOutline ? Icons.info_outline : Icons.info),
      Severity.high => const Icon(Icons.warning, color: Colors.red),
      _ => const Icon(Icons.error, color: Colors.orange)
    };

T? maxOrNull<T>(Comparable<T>? a, T? b) {
  if (a == null) return b;
  if (b == null) return a as T;
  return (a.compareTo(b) > 0 ? a : b) as T;
}

var _toGoPattern = RegExp(r'appen (västtrafik|) ?to ?go', multiLine: true, caseSensitive: false);

String? removeToGoMentions(String? text) => text?.replaceAll(_toGoPattern, 'appen');

void buyTicket(BuildContext context, String from, String to) async {
  var uri = Uri.parse('vttogo://s/?f=$from&t=$to');
  if (await launchUrl(uri)) return;
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kunde inte öppna appen Västtrafik To Go')));
}

abstract class TS {
  Widget display(BuildContext context, {bool boldTitle = false, bool showAffectedStop = false});
}

Widget displayTSs(Iterable<TS> ts) {
  if (ts.isEmpty) return Container();
  return Builder(builder: (BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Column(children: ts.map((t) => t.display(context)).toList(growable: false)),
    );
  });
}

const List<String> acronymWords = ['central', 'norra', 'södra', 'östra', 'västra'];
const List<String> excludeWords = ['station', '(tåg)', 'central', 'resecentrum', 'city'];
const String vowels = 'aeiouyåäö';

String shortStationName(String name, {bool useAcronyms = true}) {
  var splits = name.firstPart().split(' ');
  var result = <String>[];

  for (var word in splits) {
    if (useAcronyms && acronymWords.contains(word.toLowerCase())) {
      result.add(word.substring(0, 1).toUpperCase());
      continue;
    }
    if (excludeWords.contains(word.toLowerCase())) continue;
    result.add(word);
  }

  // Remove genitive case from station name.
  // For example, "Stenungsunds station" will be "Stenungsund" instead of "Stenungsunds".
  var stationName = result.firstOrNull;
  if (stationName != null && stationName.length >= 2) {
    if (stationName.characters.last == 's' && !vowels.contains(stationName[stationName.length - 2])) {
      result[0] = stationName.substring(0, stationName.length - 1);
    }
  }

  return result.join(' ');
}

BoxDecoration lineBoxDecoration(Line line, Color bgColor, BuildContext context) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(3),
    border: colorDiff2(line.backgroundColor, bgColor) < 60 * 60
        ? Border.all(color: line.foregroundColor, width: 0.5)
        : null,
    color: line.backgroundColor,
  );
}

Widget lineIconFromLine(Line line, Color bgColor, BuildContext context, {bool shortTrainName = true}) {
  return PhysicalModel(
    elevation: 1.5,
    color: line.backgroundColor,
    borderRadius: BorderRadius.circular(3),
    child: Container(
      padding: const EdgeInsets.all(5),
      constraints: const BoxConstraints(minWidth: 30),
      decoration: lineBoxDecoration(line, bgColor, context),
      child: Text(
        line.transportMode == TransportMode.train && line.shortName != line.designation
            ? '${shortTrainName ? line.shortName : line.name} ${line.trainNumber}'
            : line.shortName,
        style: TextStyle(color: line.foregroundColor, fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
    ),
  );
}

Widget trackChange(String estimatedPlatform) {
  var text = Text(
    estimatedPlatform,
    style: const TextStyle(color: Colors.black),
    textAlign: TextAlign.center,
  );

  return Stack(
    alignment: AlignmentDirectional.centerEnd,
    clipBehavior: Clip.none,
    children: [
      Positioned(
        right: -5,
        child: PhysicalModel(
          elevation: 1,
          color: Colors.yellow,
          borderRadius: BorderRadius.circular(3),
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), color: Colors.yellow),
            child: Opacity(opacity: 0, child: text),
          ),
        ),
      ),
      text,
    ],
  );
}

double colorDiff2(Color a, Color b) {
  var dr = (a.red - b.red), dg = (a.green - b.green), db = (a.blue - b.blue);
  var dl = (0.2126 * dr + 0.7152 * dg + 0.0722 * db) * 8;
  return dr * dr + 4 * dg * dg + db * db + dl * dl;
}

Color fromHex(String hexString) {
  return Color(int.parse(hexString.substring(1), radix: 16) + 0xFF000000);
}

Color? tryFromHex(String? hexString) {
  if (hexString == null) return null;
  return fromHex(hexString);
}

class DisplayableError {
  String message;
  String? description;
  IconData? icon;

  DisplayableError(this.message, {this.description, this.icon});
}

class DefaultError extends DisplayableError {
  DefaultError() : super('Ett oväntat fel inträffade');
}

class NoInternetError extends DisplayableError {
  NoInternetError(Object error)
      : super('Det är inte alltid trafiken rullar på som den ska',
            description: 'Kunde inte kontakta Västtrafik för tillfället', icon: Icons.cloud_off) {
    if (error is DioException && error.type == DioExceptionType.unknown) {
      message = 'Ingen internetanslutning';
      description = null;
    }
  }
}

class NoLocationError extends DisplayableError {
  NoLocationError([String? description])
      : super('Okänd nuvarande position', description: description, icon: Icons.location_off);
}

class ErrorPage extends StatefulWidget {
  final AsyncCallback onRefresh;
  final Object? error;

  const ErrorPage(this.onRefresh, {this.error, super.key});

  @override
  State<ErrorPage> createState() => _ErrorPageState();
}

class _ErrorPageState extends State<ErrorPage> {
  bool loading = false;

  @override
  Widget build(BuildContext context) {
    DisplayableError dError = widget.error is DisplayableError ? widget.error as DisplayableError : DefaultError();
    return loading
        ? loadingPage()
        : SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(dError.icon ?? Icons.error_outline, size: 32),
                const SizedBox(height: 12),
                Text(dError.message + (dError.description == null ? '' : '.'), textAlign: TextAlign.center),
                if (dError.description != null) Text('${dError.description}.', textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(
                    onPressed: () async {
                      setState(() => loading = true);
                      widget.onRefresh().whenComplete(() => setState(() => loading = false));
                    },
                    child: const Text('Försök igen'))
              ])),
            ),
          );
  }
}

Widget noDataPage(String title, {IconData? icon, String? description}) {
  return SafeArea(
    child: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon ?? Icons.directions_off, size: 32),
      const SizedBox(height: 16),
      Text(title),
      if (description != null) const SizedBox(height: 8),
      if (description != null) Text(description)
    ])),
  );
}

Widget noDataSliver(String message) {
  return Builder(builder: (context) {
    return SliverToBoxAdapter(
        child: Padding(
      padding: const EdgeInsets.all(20),
      child: Text(message, style: TextStyle(color: Theme.of(context).hintColor), textAlign: TextAlign.center),
    ));
  });
}

Widget loadingPage() {
  return const SafeArea(child: Center(child: CircularProgressIndicator.adaptive()));
}

Color? cardBackgroundColor(BuildContext context) => Theme.of(context).brightness == Brightness.light
    ? Theme.of(context).colorScheme.surfaceContainerLow
    : Theme.of(context).canvasColor;

Color orange(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light ? Colors.orange.shade800 : Colors.orange;

const TextStyle cancelledTextStyle =
    TextStyle(color: Colors.red, decoration: TextDecoration.lineThrough, decorationColor: Colors.red);

Widget iconAndText(IconData icon, String text,
    {double gap = 5, Color? iconColor, Color? textColor, bool expand = true}) {
  var textWidget = Text(text, style: TextStyle(color: textColor));
  return Row(children: [
    Icon(icon, color: iconColor),
    SizedBox(width: gap),
    expand ? Expanded(child: Align(alignment: Alignment.centerLeft, child: textWidget)) : textWidget,
  ]);
}

Widget tripTitle(String from, String to, {String? via}) {
  var textScalar = TextScaler.linear(via == null ? 0.8 : 0.7);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [highlightFirstPart(from, textScalar: textScalar), highlightFirstPart(to, textScalar: textScalar)].addIf(
        via != null,
        Text('via $via', textScaler: const TextScaler.linear(0.5), style: const TextStyle(color: Colors.white60))),
  );
}

class SegmentedControlController extends ValueNotifier<int> {
  SegmentedControlController(super.value);
}

class SegmentedControl extends StatefulWidget {
  final List<String> options;
  final SegmentedControlController? controller;

  const SegmentedControl(this.options, {this.controller, super.key});

  @override
  State<SegmentedControl> createState() => _SegmentedControlState();
}

class _SegmentedControlState extends State<SegmentedControl> {
  late Set<int> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {widget.controller?.value ?? 0};
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
      builder: (context, constraints) => SizedBox(
            width: constraints.maxWidth,
            child: SegmentedButton(
              segments: widget.options
                  .asMap()
                  .entries
                  .map((option) => ButtonSegment(value: option.key, label: Text(option.value)))
                  .toList(growable: false),
              selected: _selected,
              onSelectionChanged: (set) {
                setState(() {
                  _selected = set;
                  widget.controller?.value = set.first;
                });
              },
            ),
          ));
}

class DateTimeSelectorController extends ChangeNotifier {
  TimeOfDay? time;
  DateTime? date;
}

class DateTimeSelector extends StatefulWidget {
  final TextEditingController _timeInput = TextEditingController();
  final TextEditingController _dateInput = TextEditingController();
  final SegmentedControlController _segmentedControlController;
  final DateTimeSelectorController controller;

  DateTimeSelector(this._segmentedControlController, this.controller, {super.key});

  @override
  State<DateTimeSelector> createState() => _DateTimeSelectorState();
}

ValidTimeInterval? validTimeInterval;

class _DateTimeSelectorState extends State<DateTimeSelector> {
  void listener() {
    if (validTimeInterval == null && widget._segmentedControlController.value != 0) updateTimeTableInfo();
  }

  @override
  void initState() {
    super.initState();
    widget._segmentedControlController.addListener(listener);
  }

  @override
  void dispose() {
    super.dispose();
    widget._segmentedControlController.removeListener(listener);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: ValueListenableBuilder<int>(
        valueListenable: widget._segmentedControlController,
        builder: (BuildContext context, int value, Widget? child) {
          if (value != 0) {
            widget.controller.time ??= TimeOfDay.now();
            widget._timeInput.text = widget.controller.time!.format(context);
            widget.controller.date ??= DateTime.now();
            widget._dateInput.text = DateFormat.yMMMMEEEEd().format(widget.controller.date!);
          } else {
            widget.controller.time = null;
            widget.controller.date = null;
          }
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: value != 0
                ? Column(
                    children: [
                      TextField(
                        controller: widget._timeInput,
                        decoration: const InputDecoration(
                          icon: Icon(Icons.access_time),
                          labelText: 'Välj tid',
                        ),
                        readOnly: true,
                        onTap: () async {
                          var pickedTime = await showTimePicker(
                              initialTime: widget.controller.time ?? TimeOfDay.now(), context: context);
                          if (pickedTime == null || !context.mounted) return;
                          setState(() {
                            widget._timeInput.text = pickedTime.format(context);
                            widget.controller.time = pickedTime;
                          });
                        },
                      ),
                      TextField(
                        controller: widget._dateInput,
                        decoration: const InputDecoration(icon: Icon(Icons.date_range), labelText: 'Välj datum'),
                        readOnly: true,
                        onTap: () async {
                          var pickedDate = await showDatePicker(
                            initialDate: widget.controller.date ?? DateTime.now(),
                            firstDate:
                                validTimeInterval?.validFrom ?? DateTime.now().subtract(const Duration(days: 60)),
                            lastDate: validTimeInterval?.validUntil ?? DateTime.now().add(const Duration(days: 90)),
                            context: context,
                          );
                          if (pickedDate == null) return;
                          setState(() {
                            widget._dateInput.text = DateFormat.yMMMMEEEEd().format(pickedDate);
                            widget.controller.date = pickedDate;
                          });
                        },
                      ),
                    ],
                  )
                : Container(),
          );
        },
      ),
    );
  }

  void updateTimeTableInfo() async {
    validTimeInterval = await PlaneraResa.validTimeInterval().suppress();
  }
}

DateTime? getDateTimeFromSelector(
    DateTimeSelectorController dateTimeSelectorController, SegmentedControlController segmentedControlController) {
  if (segmentedControlController.value != 0) {
    var d = dateTimeSelectorController.date ?? DateTime.now();
    var t = dateTimeSelectorController.time ?? TimeOfDay.now();
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  } else {
    return null;
  }
}

Widget dateBar(DateTime dateTime, {bool showTime = true, double margin = 20}) {
  return SliverSafeArea(
    sliver: SliverPadding(
        sliver: SliverToBoxAdapter(child: Builder(builder: (context) {
          var format = DateFormat.MMMMEEEEd();
          if (showTime) format.add_Hm();
          return Text(format.format(dateTime), style: Theme.of(context).textTheme.bodySmall);
        })),
        padding: EdgeInsets.fromLTRB(margin, 10, margin, 0)),
    bottom: false,
  );
}

LatLngBounds? fromPoints(Iterable<LatLng> points) {
  if (points.isEmpty) return null;

  double? minX, maxX, minY, maxY;

  for (var point in points) {
    double x = point.longitude;
    double y = point.latitude;

    if (minX == null || minX > x) minX = x;
    if (minY == null || minY > y) minY = y;
    if (maxX == null || maxX < x) maxX = x;
    if (maxY == null || maxY < y) maxY = y;
  }

  return LatLngBounds(southwest: LatLng(minY!, minX!), northeast: LatLng(maxY!, maxX!));
}

LatLngBounds? minBounds(LatLngBounds? a, b) {
  if (a == null) return b;
  if (b == null) return a;

  return LatLngBounds(
      southwest:
          LatLng(max(a.southwest.latitude, b.southwest.latitude), max(a.southwest.longitude, b.southwest.longitude)),
      northeast:
          LatLng(min(a.northeast.latitude, b.northeast.latitude), min(a.northeast.longitude, b.northeast.longitude)));
}

double distanceBetween(LatLng a, LatLng b) =>
    Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude);

Future<Position> getPosition() async {
  bool serviceEnabled;
  LocationPermission permission;

  serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) return Future.error(NoLocationError('Platstjänst är avaktiverat'));

  permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.deniedForever || permission == LocationPermission.denied) {
    return Future.error(NoLocationError('Saknar behörighet för platstjänst'));
  }

  try {
    return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  } catch (e) {
    return Future.error(NoLocationError());
  }
}

Future<Location> getLocationFromCoord(LatLng position, {bool onlyStops = false, int? stopMaxDist}) async {
  Future<Iterable<StopLocation>> stopReq = PlaneraResa.locationsByCoordinates(position,
          types: {LocationType.stoparea, LocationType.stoppoint}, radiusInMeters: stopMaxDist)
      .then((location) => location.cast());

  Future<CoordLocation?>? addressReq;
  if (!onlyStops) addressReq = MGate.getLocationNearbyAddress(position);

  var stop = (await stopReq).firstOrNull;
  if (stop != null && !stop.isStopArea) {
    stop = (await stopReq).firstWhereOrNull((s) => s.name == stop!.name && s.isStopArea) ?? stop
      ..toStopArea();
  }
  if (stop != null) return stop;
  if (!onlyStops) {
    var address = await addressReq;
    if (address != null) return address;
  }
  throw NoLocationError('Ingen ${onlyStops ? 'hållplats' : 'adress eller hållplats'} hittades inom sökradien');
}

void noLocationFound(BuildContext context, {bool onlyStops = false, String? description, bool plural = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text((StringBuffer('Kunde inte hitta ')
            ..writeIf(!plural, 'en ')
            ..write('närliggande ')
            ..writeIf(!onlyStops, plural ? 'adresser eller ' : 'adress eller ')
            ..write(plural ? 'hållplatser' : 'hållplats')
            ..writeIf(description != null, '. $description.'))
          .toString())));
}

String lineIdFromJourneyId(String journeyId) => '${journeyId.substring(0, 3)}1${journeyId.substring(4, 11)}00000';

String stopAreaFromStopPoint(String stopPointGid) =>
    '${stopPointGid.substring(0, 3)}1${stopPointGid.substring(4, 13)}000';

class SeparatedSliverList extends SliverList {
  SeparatedSliverList(
      {super.key,
      required IndexedWidgetBuilder itemBuilder,
      required IndexedWidgetBuilder separatorBuilder,
      required itemCount,
      bool addEndingSeparator = false})
      : super(
            delegate: SliverChildBuilderDelegate((BuildContext context, int index) {
          final int itemIndex = index ~/ 2;
          if (itemIndex >= itemCount) return null;
          if (index.isEven) {
            return itemBuilder(context, itemIndex);
          } else {
            return separatorBuilder(context, itemIndex);
          }
        }, childCount: itemCount * 2 - (addEndingSeparator ? 0 : 1)));
}

RenderObjectWidget trafficSituationList(Iterable<TS> ts,
    {bool boldTitle = false, EdgeInsetsGeometry padding = const EdgeInsets.all(10), bool showAffectedStop = true}) {
  if (ts.isEmpty) return SliverToBoxAdapter(child: Container());
  return SliverPadding(
    padding: padding,
    sliver: SliverList(
      delegate: SliverChildBuilderDelegate((context, i) {
        return ts.elementAt(i).display(context, boldTitle: boldTitle, showAffectedStop: showAffectedStop);
      }, childCount: ts.length),
    ),
  );
}

bool isPresent(DateTime startTime, DateTime? endTime, DateTime start, DateTime end) {
  return startTime.isBefore(end) && (endTime?.isAfter(start) ?? true);
}

Widget highlightFirstPart(String text, {TextStyle? style, TextScaler? textScalar, TextOverflow? overflow}) {
  return Builder(
      builder: (BuildContext context) => Text.rich(highlightFirstPartSpan(text, style, context),
          style: style, overflow: overflow, textScaler: textScalar));
}

TextSpan highlightFirstPartSpan(String text, TextStyle? style, BuildContext context) {
  var textParts = text.split(',');
  style ??= DefaultTextStyle.of(context).style;
  var color = style.color ?? DefaultTextStyle.of(context).style.color;
  return TextSpan(
      text: textParts.first,
      style: style,
      children: textParts.length == 1
          ? null
          : [
              TextSpan(text: ',${textParts.sublist(1).join(',')}', style: style.copyWith(color: color?.withAlpha(153)))
            ]);
}

void setTrainInfo(Iterable<TrainAnnouncement> trainJourney, List<Call> stops, List<Set<String>?>? stopNotesLowPriority,
    List<Set<String>?>? stopNotesNormalPriority) {
  for (int i = 0, stop = 0; i < trainJourney.length && stop < stops.length; i++) {
    var activity = trainJourney.elementAt(i);
    var next = trainJourney.tryElementAt(i + 1);
    if (activity.activityType == 'Ankomst') {
      if (!(stops[stop].plannedArrivalTime?.isAtSameMomentAs(activity.advertisedTimeAtLocation) ?? false)) {
        if (stops[stop].plannedArrivalTime?.isBefore(activity.advertisedTimeAtLocation) ?? false) {
          stop++;
          i--;
        }
        continue;
      }
      stops[stop].estimatedArrivalTime = activity.estimatedTimeAtLocation ??
          activity.plannedEstimatedTimeAtLocation ??
          activity.advertisedTimeAtLocation;
      if (activity.timeAtLocation != null) stops[stop].estimatedArrivalTime = null;
      if (activity.trackAtLocation != null) stops[stop].plannedPlatform = activity.trackAtLocation!;
      if (activity.deviation.contains('Spårändrat')) stops[stop].estimatedPlatform = activity.trackAtLocation;
      stops[stop].isArrivalCancelled = activity.canceled;
      setDepartureState(activity, stops[stop].arrState);
    } else {
      if (!(stops[stop].plannedDepartureTime?.isAtSameMomentAs(activity.advertisedTimeAtLocation) ?? false)) {
        if (stops[stop].plannedDepartureTime?.isBefore(activity.advertisedTimeAtLocation) ?? false) {
          stop++;
          i--;
        }
        continue;
      }
      stops[stop].estimatedDepartureTime = activity.estimatedTimeAtLocation ??
          activity.plannedEstimatedTimeAtLocation ??
          activity.advertisedTimeAtLocation;
      if (activity.timeAtLocation != null) stops[stop].estimatedDepartureTime = null;
      if (activity.trackAtLocation != null) stops[stop].plannedPlatform = activity.trackAtLocation!;
      if (activity.deviation.contains('Spårändrat')) stops[stop].estimatedPlatform = activity.trackAtLocation;
      stops[stop].isDepartureCancelled = activity.canceled;
      setDepartureState(activity, stops[stop].depState);

      if (stops[stop].arrState.state == DepartureState.normal && stops[stop].depState.state != DepartureState.normal) {
        stops[stop].arrState.state = stops[stop].depState.state;
      }

      if (stops[stop].isDepartureCancelled &&
          !stops[stop].isArrivalCancelled &&
          stops.take(stop).every((s) => s.isDepartureCancelled)) {
        stops[stop].isArrivalCancelled = true;
      }
    }

    if (stopNotesLowPriority != null && stopNotesNormalPriority != null) {
      if (stopNotesLowPriority[stop] == null) stopNotesLowPriority[stop] = {};
      stopNotesLowPriority[stop]?.addAll(activity.otherInformation);
      if (stopNotesNormalPriority[stop] == null) stopNotesNormalPriority[stop] = {};
      stopNotesNormalPriority[stop]?.addAll(activity.deviation);
    }

    if (!(next?.advertisedTimeAtLocation
            .isAtSameMomentAs(stops[stop].plannedDepartureTime ?? stops[stop].plannedArrivalTime!) ??
        true)) {
      stop++;
    }
  }

  var lastReport = trainJourney.lastWhereOrNull((t) => t.timeAtLocation != null);
  if (lastReport != null) {
    var lastStopIndex = stops.indexWhere((s) =>
        (lastReport.activityType == 'Ankomst' ? s.plannedArrivalTime : s.plannedDepartureTime)
            ?.isAtSameMomentAs(lastReport.advertisedTimeAtLocation) ??
        false);
    for (int i = 0; i < lastStopIndex; i++) {
      stops[i].estimatedArrivalTime = null;
      stops[i].estimatedDepartureTime = null;
    }
  }
}

Future<void> setTripLegTrainInfo(Iterable<Journey> journeys) async {
  if (journeys.any((journey) => journey.tripLegs.any((leg) => leg.serviceJourney.isTrain))) {
    var trainLegs = journeys.expand((journey) => journey.tripLegs).where((leg) => leg.serviceJourney.isTrain);
    var trainActivities = await Trafikverket.getTrainTrips(trainLegs
        .map((l) => TrainLegRef(l.serviceJourney.line.trainNumber!, l.plannedDepartureTime, l.plannedArrivalTime))
        .toSet());

    for (TrainAnnouncement activity in trainActivities ?? []) {
      if (activity.activityType == 'Ankomst') {
        var legs = trainLegs.where((leg) =>
            leg.serviceJourney.line.trainNumber! == activity.advertisedTrainIdent &&
            leg.plannedArrivalTime.isAtSameMomentAs(activity.advertisedTimeAtLocation));
        for (var leg in legs) {
          leg.estimatedArrivalTime = activity.estimatedTimeAtLocation ??
              activity.plannedEstimatedTimeAtLocation ??
              activity.advertisedTimeAtLocation;
          leg.destination.stopPoint.plannedPlatform = activity.trackAtLocation;
          if (activity.timeAtLocation != null) leg.estimatedArrivalTime = null;
          if (activity.deviation.contains('Spårändrat')) {
            leg.destination.stopPoint.estimatedPlatform = activity.trackAtLocation;
          }
          leg.destination.isCancelled = activity.canceled;
          setDepartureState(activity, leg.arrState);
        }
      } else {
        var legs = trainLegs.where((leg) =>
            leg.serviceJourney.line.trainNumber! == activity.advertisedTrainIdent &&
            leg.plannedDepartureTime.isAtSameMomentAs(activity.advertisedTimeAtLocation));
        for (var leg in legs) {
          leg.estimatedDepartureTime = activity.estimatedTimeAtLocation ??
              activity.plannedEstimatedTimeAtLocation ??
              activity.advertisedTimeAtLocation;
          leg.origin.stopPoint.plannedPlatform = activity.trackAtLocation;
          if (activity.timeAtLocation != null) leg.estimatedDepartureTime = null;
          if (activity.deviation.contains('Spårändrat')) {
            leg.origin.stopPoint.estimatedPlatform = activity.trackAtLocation;
          }
          leg.origin.isCancelled = activity.canceled;
          setDepartureState(activity, leg.depState);
          if (activity.deviation.isNotEmpty) leg.serviceJourney.direction += ', ${activity.deviation.join(', ')}';
        }
      }
    }

    for (var trainLeg in trainLegs) {
      trainLeg.isCancelled |= trainLeg.origin.isCancelled && trainLeg.destination.isCancelled;
      trainLeg.isPartCancelled |= trainLeg.origin.isCancelled ^ trainLeg.destination.isCancelled;
    }
  }
}

Future<ServiceJourneyDetails?> getJourneyDetailExtra(DetailsRef ref) async {
  var response = PlaneraResa.details(
      ref, {DepartureDetailsIncludeType.serviceJourneyCalls, DepartureDetailsIncludeType.serviceJourneyCoordinates});

  var journeyDetails = await response;

  if (ref.serviceJourney.isTrain) {
    await Trafikverket.getTrainJourney(ref.serviceJourney.line.trainNumber!,
            journeyDetails.firstCall!.plannedDepartureTime!, journeyDetails.lastCall!.plannedArrivalTime!)
        .then((trainJourney) {
      if (trainJourney == null) return;
      var allStops = journeyDetails.allCalls.toList(growable: false);
      setTrainInfo(trainJourney, allStops, null, null);
    });
  }

  return journeyDetails;
}

void setDepartureState(TrainAnnouncement activity, DepartureStateMixin departure) {
  if (activity.deviation.contains('Invänta tid')) departure.state = DepartureState.unknownTime;
  if (activity.canceled) {
    if (activity.deviation.any((d) => d.contains('Taxi'))) departure.state = DepartureState.replacementTaxi;
    if (activity.deviation.any((d) => d.contains('Buss'))) departure.state = DepartureState.replacementBus;
  }
}

class SystemGestureArea extends StatelessWidget {
  final Widget child;
  final EdgeInsets systemGestureInsets;

  const SystemGestureArea(this.systemGestureInsets, {required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
            bottom: 0,
            child: Container(
                color: Colors.transparent,
                width: MediaQuery.of(context).size.width,
                height: systemGestureInsets.bottom))
      ],
    );
  }
}

const List<int> tramStops = [
  1050, 1200, 1450, 1620, 1690, 1745, 1850, 1900, 2150, 2170, 2200, 2210, 2370, 2470, 2540, 2630, 2670, 2730, 2790,
  3040, 3060, 3360, 3620, 3880, 4320, 4370, 4527, 4700, 4730, 4780, 4810, 4870, 5110, 5140, 5170, 5220, 5330, 5531,
  5630, 5660, 5710, 5740, 5763, 6040, 6260, 6570, 7150, 7172, 7200, 7270, 7280, 7320, 7370, 7750, 8590 // tramStops
];

const List<int> trainStops = [
  2672, 4525, 6605, 8000, 12115, 12610, 12711, 13100, 13715, 14212, 14715, 15010, 15280, 15300, 16100, 16200, 16300,
  16410, 16611, 17115, 17117, 17130, 17165, 17210, 17280, 17510, 17610, 18116, 18410, 18530, 19110, 19115, 19131, 19820,
  21120, 21293, 21510, 22110, 22220, 22310, 25120, 25210, 26110, 26140, 26210, 27306, 30001, 30145, 31010, 31328, 31331,
  31332, 31385, 32010, 34001, 34123, 34124, 34125, 34126, 34254, 34255, 34289, 35004, 37010, 37234, 37375, 37376, 37386,
  40010, 40206, 40217, 40218, 41010, 41280, 41291, 43111, 44801, 45500, 52602, 61900, 62717, 66021, 66105, 66134, 66135,
  72010, 72017, 72021, 74000, 75000, 75045, 75047, 75048, 75053, 75054, 78000, 78158, 79003, 80800, 80801, 80802, 81600,
  82177, 82900, 82902, 82903, 82904, 85044, 86500, 88000, 88002, 88009, 88016, 88020, 89020 // trainStops
];

const List<int> boatStops = [
  1031, 1033, 1034, 1035, 1036, 1038, 1039, 1043, 1044, 1045, 1048, 1049, 1061, 1062, 1064, 1066, 2239, 3895, 4381,
  4420, 4493, 6030, 9620, 11213, 11310, 11430, 11616, 11617, 11710, 11750, 11810, 11850, 11910, 14290, 14294, 14295,
  14296, 14297, 14310, 14312, 14315, 14590, 14592, 14662, 15120, 15530, 15534, 15535, 15536, 15537, 15546, 15547, 15548,
  15690, 15696, 15721, 15725, 15746, 15807, 15932, 23112, 23509, 23518, 23542, 25226, 25292, 25298, 25302, 26115, 26180,
  26190, 26410, 26411, 26420, 26421, 26422, 26430 // boatStops
];

IconData getStopIcon(StopLocation stop) {
  if (!stop.isStopArea) return Icons.location_city;
  int extId = int.parse(stop.gid.substring(7, 13));
  if (binarySearch(tramStops, extId) >= 0) return Icons.tram;
  if (binarySearch(trainStops, extId) >= 0) return Icons.directions_train;
  if (binarySearch(boatStops, extId) >= 0) return Icons.directions_boat;
  return Icons.directions_bus;
}

String getStopIconString(StopLocation stop) {
  return switch (getStopIcon(stop)) {
    Icons.tram => 'tram',
    Icons.directions_train => 'train',
    Icons.directions_boat => 'boat',
    _ => 'bus'
  };
}

Iterable<T> merge<T>(List<T> a, List<T> b, Comparator<T> comparator) {
  List<T> result = [];

  int i = 0, j = 0;
  while (i < a.length && j < b.length) {
    if (comparator(a[i], b[j]) < 0) {
      result.add(a[i++]);
    } else {
      result.add(b[j++]);
    }
  }

  if (i < a.length) {
    result.addAll(a.getRange(i, a.length));
  } else {
    result.addAll(b.getRange(j, b.length));
  }

  return result;
}

class CustomScrollBehavior extends ScrollBehavior {
  const CustomScrollBehavior(this.androidSdkVersion) : super();
  final int? androidSdkVersion;

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    switch (getPlatform(context)) {
      case TargetPlatform.android:
        return androidSdkVersion != null && androidSdkVersion! >= 31
            ? StretchingOverscrollIndicator(
                axisDirection: details.direction,
                child: child,
              )
            : GlowingOverscrollIndicator(
                axisDirection: details.direction,
                color: Theme.of(context).colorScheme.secondary,
                child: child,
              );
      default:
        return child;
    }
  }
}

class Wrapper<T> {
  T? element;

  Wrapper(this.element);
}

enum MenuAction { addToHomeScreen, buyTicket, showEarlierJourneys, showEarlierDepartures, showMoreDepartures }

const platform = MethodChannel('ga.edvin.resecentrum');

Future<void> createShortcut(BuildContext context, String uri, String label, String icon, String? summary) async {
  var textController = TextEditingController(text: label);
  var valid = ValueNotifier<bool>(true);
  showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Lägg till på hemskärmen'),
          content: Container(
            constraints: const BoxConstraints(maxWidth: 360),
            width: MediaQuery.of(context).size.width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  onChanged: (value) => valid.value = value.isNotEmpty,
                  controller: textController,
                  decoration: const InputDecoration(hintText: 'Ange genvägsnamn'),
                ),
                if (summary != null) const SizedBox(height: 10),
                if (summary != null)
                  Text(summary,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).hintColor))
              ],
            ),
          ),
          actions: [
            TextButton(
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
              onPressed: () => Navigator.pop(context),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: valid,
              builder: (BuildContext context, value, Widget? child) => TextButton(
                onPressed: value
                    ? () {
                        platform
                            .invokeMethod('createShortcut', {'uri': uri, 'label': textController.text, 'icon': icon});
                        Navigator.pop(context);
                      }
                    : null,
                child: const Text('LÄGG TILL'),
              ),
            ),
          ],
        );
      });
}

Future<int?> androidSdk() => platform.invokeMethod<int>('sdk');

Location? parseLocation(Map<String, String> params, String? prefix) {
  try {
    if (params.containsKey(addPrefix('id', prefix))) {
      return StopLocation.fromParams(params, prefix);
    } else if (params.containsKey(addPrefix('type', prefix))) {
      return CoordLocation.fromParams(params, prefix);
    } else if (params.containsKey(addPrefix('currentLocation', prefix))) {
      return CurrentLocation();
    }
  } catch (error, stackTrace) {
    if (kDebugMode) {
      print(error);
      print(stackTrace);
    }
  }
  return null;
}

String addPrefix(String str, String? prefix) {
  return prefix == null ? str : prefix + str.capitalize();
}

double truncatedMean(List<int> sortedList, double cutoffRatio) {
  var start = (sortedList.length * cutoffRatio).ceil();
  var end = (sortedList.length * (1.0 - cutoffRatio)).floor();
  if (start >= end) return sortedList.average;
  return sortedList.getRange(start, end).average;
}
