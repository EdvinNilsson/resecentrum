import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' hide binarySearch;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:maplibre_gl/mapbox_gl.dart';

import 'extensions.dart';
import 'map_widget.dart';
import 'reseplaneraren.dart';
import 'trafikverket.dart';
import 'vehicle_positions_service.dart';

String getDelayString(int? delay, {DepartureState? state}) {
  if (state == DepartureState.unknownTime) return '+?';
  if (delay == null) return '';
  String str = delay.abs() < 60 ? delay.toString() : '${delay ~/ 60}h${delay % 60 != 0 ? delay.abs() % 60 : ''}';
  return delay < 0 ? str : '+' + str;
}

bool hasDeparted(VehiclePosition vehicle, double lat, double long) {
  var distance = Geolocator.distanceBetween(vehicle.lat, vehicle.long, lat, long);
  if ((distance > 150 || vehicle.speed > 20) &&
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
      return _countdownText('Taxi', style: TextStyle(color: orange(context)));
    }
    if (departure.state == DepartureState.unknownTime) return _countdownText('?');
    if (departure.state == DepartureState.departed) return _countdownText('Avg.', style: const TextStyle());
    if (departure.state == DepartureState.atStation) return _countdownText('nu');
    if (departure.cancelled) return _countdownText('Inst.', style: const TextStyle(color: Colors.red));

    var realtime = departure.rtDateTime != null;
    var timeLeft = departure.getDateTime().difference(DateTime.now());
    var minutesLeft = timeLeft.minutesRounded();
    if (minutesLeft.abs() > 100) {
      return _countdownText(minutesLeft.abs() >= 5940 ? '${timeLeft.inDays}d' : '${timeLeft.hoursRounded()}h');
    }
    if (!realtime && minutesLeft > 0) return _countdownText('ca $minutesLeft');
    if (minutesLeft == 0 || minutesLeft == -1) return _countdownText('nu');
    return _countdownText(minutesLeft.toString());
  });
}

int? getDelay(DateTime dateTime, DateTime? rtDateTime) => rtDateTime?.difference(dateTime).inMinutes;

int? getDepartureDelay(Departure departure) => getDelay(departure.dateTime, departure.rtDateTime);

int? getTripLocationDelay(TripLocation departure) => getDelay(departure.dateTime, departure.rtDateTime);

Duration getTripTime(Trip trip) {
  DateTime startTime = trip.leg.first.origin.getDateTime();
  DateTime endTime = trip.leg.last.destination.getDateTime();
  return endTime.difference(startTime);
}

String getDurationString(Duration duration) {
  return duration.inHours > 0
      ? (duration.minutesRounded() % 60 == 0
          ? '${duration.inHours} h'
          : '${duration.inHours} h ${duration.minutesRounded() % 60} min')
      : '${duration.minutesRounded()} min';
}

String getTripCountdown(DateTime? departure) {
  if (departure == null) return '';
  var timeLeft = departure.difference(DateTime.now());
  var minutesLeft = timeLeft.minutesRounded();
  if (minutesLeft.abs() > 1440) return ', ' + DateFormat.MMMMEEEEd().format(departure);
  if (minutesLeft < -1) return ', avgått';
  if (minutesLeft > 0) return ', om ${getDurationString(timeLeft)}';
  return ', nu';
}

Widget stopRowFromStop(Stop stop,
    {bool bold = false,
    bool alightingOnly = false,
    bool boardingOnly = false,
    Icon? noteIcon,
    BoxConstraints? constraints,
    bool useHintColor = false}) {
  return Builder(builder: (context) {
    var textSpans = <TextSpan>[];

    void addTimeText(DateTime time, DateTime? rtTime, bool cancelled) {
      TextStyle style = TextStyle(color: rtTime == null && useHintColor ? Theme.of(context).hintColor : null);
      if (cancelled) {
        style = style.copyWith(color: Colors.red, decoration: TextDecoration.lineThrough);
        if (stop.state == DepartureState.replacementTaxi || stop.state == DepartureState.replacementBus) {
          style = style.copyWith(color: orange(context));
        }
      }

      textSpans.add(TextSpan(text: time.time(), style: style.copyWith(fontWeight: FontWeight.bold)));
      if (rtTime != null) {
        textSpans.add(TextSpan(text: getDelayString(getDelay(time, rtTime), state: stop.state), style: style));
      }
    }

    if (stop.depDateTime != null &&
        stop.arrDateTime != null &&
        (stop.depDateTime != stop.arrDateTime || stop.depCancelled != stop.arrCancelled)) {
      addTimeText(stop.arrDateTime!, stop.rtArrTime, stop.arrCancelled);
      textSpans.add(const TextSpan(text: '\n'));
      addTimeText(stop.depDateTime!, stop.rtDepTime, stop.depCancelled);
    } else {
      addTimeText(stop.depDateTime ?? stop.arrDateTime!, stop.rtDepTime ?? stop.rtArrTime,
          stop.depDateTime != null ? stop.depCancelled : stop.arrCancelled);
    }

    var text = Text.rich(TextSpan(text: '', children: textSpans));

    return stopRow(text, stop.name, stop.track, stop.rtTrack,
        bold: bold,
        alightingOnly: alightingOnly,
        boardingOnly: boardingOnly,
        noteIcon: noteIcon,
        constraints: constraints,
        rtInfo: !useHintColor || (stop.rtDepTime ?? stop.rtArrTime) != null);
  });
}

Widget simpleTimeWidget(DateTime dateTime, int? delay, bool cancelled) {
  return Row(
    children: [
      Text(dateTime.time(),
          style: cancelled
              ? cancelledTextStyle.copyWith(fontWeight: FontWeight.bold)
              : const TextStyle(fontWeight: FontWeight.bold)),
      Text(getDelayString(delay), style: cancelled ? cancelledTextStyle : null)
    ],
  );
}

Widget stopRow(Widget time, String name, String? track, String? rtTrack,
    {bool bold = false,
    bool alightingOnly = false,
    bool boardingOnly = false,
    Icon? noteIcon,
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
                child: time,
                constraints: const BoxConstraints(minWidth: 64),
                margin: const EdgeInsets.fromLTRB(0, 0, 10, 0)),
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
            Container(
                constraints: const BoxConstraints(minWidth: 20),
                child: rtTrack != null
                    ? trackChange(rtTrack)
                    : Text(rtTrack ?? track ?? '',
                        textAlign: TextAlign.right,
                        style: !rtInfo ? TextStyle(color: Theme.of(context).hintColor) : null))
          ],
        ));
  });
}

Widget accessibilityIcon(String? accessibility, DateTime? rtDateTime, {EdgeInsetsGeometry? margin}) {
  return accessibility == null && rtDateTime != null
      ? Container(child: const Icon(Icons.not_accessible), margin: margin)
      : Container();
}

Icon getNoteIcon(String severity) {
  switch (severity) {
    case 'slight':
    case 'low':
      return const Icon(Icons.info_outline);
    case 'severe':
    case 'high':
      return const Icon(Icons.warning, color: Colors.red);
    default:
      return const Icon(Icons.error, color: Colors.orange);
  }
}

int getNotePriority(String severity) {
  switch (severity) {
    case 'slight':
    case 'low':
      return 2;
    case 'severe':
    case 'high':
      return 0;
    default:
      return 1;
  }
}

String? getHighestPriority(String? a, String? b) {
  if (a == null) return b;
  if (b == null) return a;
  return getNotePriority(a) < getNotePriority(b) ? a : b;
}

var _toGoPattern = RegExp(r'appen (västtrafik|) ?to ?go', multiLine: true, caseSensitive: false);

String? removeToGoMentions(String? text) => text?.replaceAll(_toGoPattern, 'appen');

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

String shortStationName(String name, {bool useAcronyms = true}) {
  var splits = name.firstPart().split(' ');
  var result = [];

  for (var word in splits) {
    if (useAcronyms && acronymWords.contains(word.toLowerCase())) {
      result.add(word.substring(0, 1).toUpperCase());
      continue;
    }
    if (excludeWords.contains(word.toLowerCase())) continue;
    result.add(word);
  }

  return result.join(' ');
}

BoxDecoration lineBoxDecoration(Color bgColor, Color fgColor, double bgLuminance, BuildContext context) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(3),
    border: (bgColor.computeLuminance() - bgLuminance).abs() < 0.01 ? Border.all(color: fgColor, width: 0.5) : null,
    color: bgColor,
  );
}

Leg? nextLeg(List<Leg> legs, int current) =>
    legs.getRange(current + 1, legs.length).firstWhereOrNull((l) => l.type != 'WALK');

Widget lineIconFromDeparture(Departure departure, double bgLuminance, BuildContext context) {
  return lineIcon(departure.sname, departure.fgColor, departure.bgColor, bgLuminance, departure.type, departure.name,
      departure.journeyNumber, context);
}

Widget lineIconFromLeg(Leg leg, double bgLuminance, BuildContext context) {
  return lineIcon(leg.sname ?? leg.name, leg.fgColor ?? Colors.white, leg.bgColor ?? Colors.black, bgLuminance,
      leg.type, leg.name, leg.journeyNumber, context);
}

Widget lineIcon(String sname, Color fgColor, Color bgColor, double bgLuminance, String type, String name,
    int? journeyNumber, BuildContext context) {
  return PhysicalModel(
    elevation: 1.5,
    color: bgColor,
    borderRadius: BorderRadius.circular(3),
    child: Container(
      padding: const EdgeInsets.all(5),
      constraints: const BoxConstraints(minWidth: 30),
      decoration: lineBoxDecoration(bgColor, fgColor, bgLuminance, context),
      child: Text(
        isTrainType(type)
            ? '${(name.split(' ').where((t) => int.tryParse(t) == null)).join(' ')} $journeyNumber'
            : sname,
        style: TextStyle(color: fgColor, fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
    ),
  );
}

Widget trackChange(String rtTrack) {
  var text = Text(
    rtTrack,
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
            child: Opacity(child: text, opacity: 0),
          ),
        ),
      ),
      text,
    ],
  );
}

bool isTrainType(String type) {
  return type == 'VAS' || type == 'LDT' || type == 'REG';
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
    if (error is DioError && error.type == DioErrorType.other ||
        error is WebResourceError && error.errorType == WebResourceErrorType.hostLookup) {
      message = 'Ingen internetanslutning';
      description = null;
    }
  }
}

class NoLocationError extends DisplayableError {
  NoLocationError([String? description])
      : super('Okänd nuvarande position', description: description, icon: Icons.location_off);
}

class HafasError extends DisplayableError {
  HafasError(String errorCode, errorText) : super(errorText) {
    switch (errorCode) {
      case 'R0001':
      case 'R0002':
      case 'H9320':
        message = 'Ogiltig förfrågan';
        break;
      case 'H9380':
        message = 'Startplats, via-hållplats eller destination ligger för nära varandra';
        break;
      case 'R0007':
      case 'S1':
        message = 'Kommunikationsproblem';
        break;
      case 'H9360':
        message = 'Datum ligger utanför tillåten sökperiod';
        break;
      case 'H9300':
        message = 'Okänd destination';
        break;
      case 'H9280':
        message = 'Okänd via-hållplats';
        break;
      case 'H9260':
        message = 'Okänd startplats';
        break;
      case 'H900':
        message = 'Sökningen kunde inte genomföras p.g.a. tidtabellsbyte';
        break;
      case 'H892':
        message = 'Sökningen är för komplex (var god ange färre via-hållplatser)';
        break;
      case 'H891':
        message = 'Ingen resväg hittades (var god ange en via-hållplats)';
        break;
      case 'H895':
      case 'H9381':
        message = 'Startplatsen och destinationen ligger för nära varandra';
        break;
      case 'H9220':
        message = 'Kunde inte hitta en hållplats tillräckligt nära den angivna adressen';
        break;
    }
  }
}

void checkHafasError(dynamic data) {
  if (data['error'] != null) {
    throw HafasError(data['error'].split(' ').first, data['errorText']);
  }
}

class ErrorPage extends StatefulWidget {
  final AsyncCallback onRefresh;
  final Object? error;

  const ErrorPage(this.onRefresh, {this.error, Key? key}) : super(key: key);

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
                ElevatedButton(
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

Widget noDataPage(String message) {
  return SafeArea(
    child: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.directions_off, size: 32),
      const SizedBox(height: 16),
      Text(message),
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

Color? cardBackgroundColor(BuildContext context) {
  return Theme.of(context).brightness == Brightness.light ? Colors.grey.shade100 : Theme.of(context).canvasColor;
}

Color orange(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light ? Colors.orange.shade800 : Colors.orange;

const TextStyle cancelledTextStyle = TextStyle(color: Colors.red, decoration: TextDecoration.lineThrough);

Widget iconAndText(IconData icon, String text, {double gap = 5, Color? iconColor, Color? textColor}) {
  return Row(children: [
    Icon(icon, color: iconColor),
    SizedBox(width: gap),
    Text(text, style: TextStyle(color: textColor)),
  ]);
}

Widget tripTitle(String from, String to, {String? via}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [highlightFirstPart(from, textScaleFactor: 0.8), highlightFirstPart(to, textScaleFactor: 0.8)]
        .addIf(via != null, Text('via $via', textScaleFactor: 0.6, style: const TextStyle(color: Colors.white60))),
  );
}

class SegmentedControlController extends ValueNotifier<int> {
  SegmentedControlController(int value) : super(value);
}

class SegmentedControl extends StatefulWidget {
  final List<String> options;
  final SegmentedControlController? controller;

  const SegmentedControl(this.options, {this.controller, Key? key}) : super(key: key);

  @override
  State<SegmentedControl> createState() => _SegmentedControlState();
}

class _SegmentedControlState extends State<SegmentedControl> {
  late List<bool> _selections;

  @override
  void initState() {
    super.initState();
    selectOption(widget.controller?.value ?? 0);
  }

  void selectOption(int index) {
    _selections = List.generate(widget.options.length, (_) => false);
    _selections[index] = true;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return ToggleButtons(
        renderBorder: true,
        color: Theme.of(context).hintColor,
        constraints: BoxConstraints.expand(
            width: (constraints.maxWidth - widget.options.length - 1) / widget.options.length, height: 48),
        children: widget.options
            .asMap()
            .entries
            .map((option) => Text(option.value,
                style: _selections[option.key] ? const TextStyle(fontWeight: FontWeight.bold) : null))
            .toList(growable: false),
        isSelected: _selections,
        onPressed: (int index) {
          setState(() {
            selectOption(index);
            widget.controller?.value = index;
          });
        },
      );
    });
  }
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

  DateTimeSelector(this._segmentedControlController, this.controller, {Key? key}) : super(key: key);

  @override
  State<DateTimeSelector> createState() => _DateTimeSelectorState();
}

class _DateTimeSelectorState extends State<DateTimeSelector> {
  static TimetableInfo? _timetableInfo;

  void listener() {
    if (_timetableInfo == null && widget._segmentedControlController.value != 0) updateTimeTableInfo();
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
                          if (pickedTime == null) return;
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
                            firstDate: _timetableInfo?.dateBegin ?? DateTime.now().subtract(const Duration(days: 60)),
                            lastDate: _timetableInfo?.dateEnd ?? DateTime.now().add(const Duration(days: 90)),
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
    _timetableInfo = await reseplaneraren.getSystemInfo().suppress();
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

LatLngBounds? fromPoints(Iterable<LatLng> points) {
  if (points.isNotEmpty) {
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
  return null;
}

LatLngBounds? pad(LatLngBounds? bounds, double bufferRatio) {
  if (bounds == null) return null;

  var heightBuffer = (bounds.southwest.latitude - bounds.northeast.latitude).abs() * bufferRatio;
  var widthBuffer = (bounds.southwest.longitude - bounds.northeast.longitude).abs() * bufferRatio;

  return LatLngBounds(
      southwest: LatLng(bounds.southwest.latitude - heightBuffer, bounds.southwest.longitude - widthBuffer),
      northeast: LatLng(bounds.northeast.latitude + heightBuffer, bounds.northeast.longitude + widthBuffer));
}

LatLngBounds? minSize(LatLngBounds? bounds, double minSize) {
  if (bounds == null) return null;

  var heightBuffer = (bounds.southwest.latitude - bounds.northeast.latitude).abs();
  var widthBuffer = (bounds.southwest.longitude - bounds.northeast.longitude).abs();

  heightBuffer = heightBuffer < minSize ? (minSize - heightBuffer) / 2 : 0;
  widthBuffer = widthBuffer < minSize ? (minSize - widthBuffer) / 2 : 0;

  return LatLngBounds(
      southwest: LatLng(bounds.southwest.latitude - heightBuffer, bounds.southwest.longitude - widthBuffer),
      northeast: LatLng(bounds.northeast.latitude + heightBuffer, bounds.northeast.longitude + widthBuffer));
}

String addLineIfNotEmpty(String text) => text.isEmpty ? text : '\n' + text;

Color darken(Color color, double amount) {
  assert(amount >= 0 && amount <= 1);

  final hsl = HSLColor.fromColor(color);
  final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));

  return hslDark.toColor();
}

Future<Location?> getLocation({bool onlyStops = false, int? stopMaxDist}) async {
  bool serviceEnabled;
  LocationPermission permission;

  serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) return null;

  permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      return null;
    }
  }

  if (permission == LocationPermission.deniedForever) return null;

  Position pos;
  try {
    pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  } catch (e) {
    return null;
  }

  return getLocationFromCoord(pos.latitude, pos.longitude, onlyStops: onlyStops, stopMaxDist: stopMaxDist);
}

Future<Location?> getLocationFromCoord(double latitude, double longitude,
    {bool onlyStops = false, int? stopMaxDist}) async {
  var stopReq = reseplaneraren.getLocationNearbyStops(latitude, longitude, maxDist: stopMaxDist);

  Future<CoordLocation?>? addressReq;
  if (!onlyStops) addressReq = reseplaneraren.getLocationNearbyAddress(latitude, longitude);
  var stop = (await stopReq)?.firstWhereOrNull((stop) => stop.isStopArea);
  // If no stop area was found, convert a stop point into a stop area.
  if (stop == null) {
    stop = (await stopReq)?.firstWhereOrNull((stop) => stop.id >= 9022000000000000);
    stop?.id = stopAreaFromStopId(stop.id);
    stop?.track = null;
  }
  if (stop != null) return stop;
  if (!onlyStops) {
    var address = await addressReq;
    if (address?.isValid ?? false) return address;
  }
  return null;
}

void noLocationFound(BuildContext context, {bool onlyStops = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Kunde inte hitta en närliggande ${!onlyStops ? 'adress eller ' : ''}hållplats')));
}

String lineIdFromJourneyId(String journeyId) => '${journeyId.substring(0, 3)}1${journeyId.substring(4, 11)}00000';

int stopAreaFromStopId(int stopId) => stopId - stopId % 1000 - 1000000000000;

class SeparatedSliverList extends SliverList {
  SeparatedSliverList({
    Key? key,
    required IndexedWidgetBuilder itemBuilder,
    required IndexedWidgetBuilder separatorBuilder,
    required itemCount,
  }) : super(
            key: key,
            delegate: SliverChildBuilderDelegate((BuildContext context, int index) {
              final int itemIndex = index ~/ 2;
              if (itemIndex >= itemCount) return null;
              if (index.isEven) {
                return itemBuilder(context, itemIndex);
              } else {
                return separatorBuilder(context, itemIndex);
              }
            }, childCount: itemCount * 2 - 1));
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

Widget highlightFirstPart(String text, {TextStyle? style, double? textScaleFactor, TextOverflow? overflow}) {
  return Builder(
      builder: (BuildContext context) => Text.rich(highlightFirstPartSpan(text, style, context),
          style: style, overflow: overflow, textScaleFactor: textScaleFactor));
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
              TextSpan(text: ',' + textParts.sublist(1).join(','), style: style.copyWith(color: color?.withAlpha(153)))
            ]);
}

void setTrainInfo(Iterable<TrainAnnouncement> trainJourney, List<Stop> stops, List<Set<String>?>? stopNotesLowPriority,
    List<Set<String>?>? stopNotesNormalPriority) {
  for (int i = 0, stop = 0; i < trainJourney.length && stop < stops.length; i++) {
    var activity = trainJourney.elementAt(i);
    var next = trainJourney.tryElementAt(i + 1);
    if (activity.activityType == 'Ankomst') {
      if (!(stops[stop].arrDateTime?.isAtSameMomentAs(activity.advertisedTimeAtLocation) ?? false)) {
        if (stops[stop].arrDateTime?.isBefore(activity.advertisedTimeAtLocation) ?? false) {
          stop++;
          i--;
        }
        continue;
      }
      stops[stop].rtArrTime = activity.estimatedTimeAtLocation ??
          activity.plannedEstimatedTimeAtLocation ??
          activity.advertisedTimeAtLocation;
      if (activity.timeAtLocation != null) stops[stop].rtArrTime = null;
      if (activity.trackAtLocation != null) stops[stop].track = activity.trackAtLocation;
      if (activity.deviation.contains('Spårändrat')) stops[stop].rtTrack = activity.trackAtLocation;
      stops[stop].arrCancelled |= activity.canceled;
    } else {
      if (!(stops[stop].depDateTime?.isAtSameMomentAs(activity.advertisedTimeAtLocation) ?? false)) {
        if (stops[stop].depDateTime?.isBefore(activity.advertisedTimeAtLocation) ?? false) {
          stop++;
          i--;
        }
        continue;
      }
      stops[stop].rtDepTime = activity.estimatedTimeAtLocation ??
          activity.plannedEstimatedTimeAtLocation ??
          activity.advertisedTimeAtLocation;
      if (activity.timeAtLocation != null) stops[stop].rtDepTime = null;
      if (activity.trackAtLocation != null) stops[stop].track = activity.trackAtLocation;
      if (activity.deviation.contains('Spårändrat')) stops[stop].rtTrack = activity.trackAtLocation;
      stops[stop].depCancelled |= activity.canceled;
    }

    if (activity.deviation.contains('Invänta tid')) stops[stop].state = DepartureState.unknownTime;
    if (activity.deviation.contains('Taxi ersätter')) stops[stop].state = DepartureState.replacementTaxi;
    if (activity.deviation.contains('Buss ersätter')) stops[stop].state = DepartureState.replacementBus;

    if (stopNotesLowPriority != null && stopNotesNormalPriority != null) {
      if (stopNotesLowPriority[stop] == null) stopNotesLowPriority[stop] = {};
      stopNotesLowPriority[stop]?.addAll(activity.otherInformation);
      if (stopNotesNormalPriority[stop] == null) stopNotesNormalPriority[stop] = {};
      stopNotesNormalPriority[stop]?.addAll(activity.deviation);
    }

    if (!(next?.advertisedTimeAtLocation.isAtSameMomentAs(stops[stop].depDateTime ?? stops[stop].arrDateTime!) ??
        true)) {
      stop++;
    }
  }
}

Future<JourneyDetail?> getJourneyDetailExtra(JourneyDetailRef ref) async {
  var response = reseplaneraren.getJourneyDetail(ref.ref);

  if (!isTrainType(ref.type)) {
    await reseplaneraren.setCancelledStops(ref.evaDateTime, ref.evaId, response, ref.journeyId);
  }

  var journeyDetail = await response;
  if (journeyDetail == null) return null;

  if (isTrainType(ref.type)) {
    await trafikverket
        .getTrainJourney(
            ref.journeyNumber!, journeyDetail.stop.first.depDateTime!, journeyDetail.stop.last.arrDateTime!)
        .then((trainJourney) {
      if (trainJourney == null) return;
      var stops = journeyDetail.stop.toList(growable: false);
      setTrainInfo(trainJourney, stops, null, null);
      journeyDetail.stop = stops;
    });
  }

  return journeyDetail;
}

class SystemGestureArea extends StatelessWidget {
  final Widget child;
  final EdgeInsets systemGestureInsets;

  const SystemGestureArea(this.systemGestureInsets, {required this.child, Key? key}) : super(key: key);

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

IconData getStopIcon(String stopId) {
  int extId = int.parse(stopId.substring(7, 13));
  if (binarySearch(tramStops, extId) >= 0) return Icons.tram;
  if (binarySearch(trainStops, extId) >= 0) return Icons.directions_train;
  if (binarySearch(boatStops, extId) >= 0) return Icons.directions_boat;
  return Icons.directions_bus;
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
    result.addAll(a.getRange(i, a.length - 1));
  } else {
    result.addAll(b.getRange(j, b.length - 1));
  }

  return result;
}

class Wrapper<T> {
  T? element;

  Wrapper(this.element);
}
