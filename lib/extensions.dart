import 'dart:ui';

import 'package:intl/intl.dart';
import 'package:maplibre_gl/mapbox_gl.dart';

import 'network/traffic_situations.dart';

extension IterableExt<T> on Iterable<T> {
  T? tryElementAt(int index) => (index >= 0 && index < length) ? elementAt(index) : null;
}

extension ListExt<T> on List<T> {
  List<T> addIf(bool predicate, T? value) {
    if (predicate && value != null) add(value);
    return this;
  }

  List<T> insertIf(bool predicate, int index, T? value) {
    if (predicate && value != null) insert(index, value);
    return this;
  }
}

extension StringOptExt on String? {
  bool get isNullOrEmpty => this == null || this!.isEmpty;
}

extension StringExt on String {
  String capitalize() => isEmpty ? this : this[0].toUpperCase() + substring(1);

  String uncapitalize() => isEmpty ? this : this[0].toLowerCase() + substring(1);

  String firstPart() => split(',').first;
}

extension StringIterableExt on Iterable<String> {
  String joinNaturally() {
    if (length <= 1) return join();
    return '${toList(growable: false).getRange(0, length - 1).join(', ')} och $last';
  }
}

extension BoolIterableExt on Iterable<bool> {
  bool all() => every((b) => b);
}

extension ColorExt on Color {
  String toHexCode() => '#${(value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

extension DurationExt on Duration {
  int minutesRounded() {
    return (inMilliseconds / 60000).round();
  }

  int hoursRounded() {
    return (inMilliseconds / 3600000).round();
  }
}

extension TimeExt on DateTime {
  String time() {
    return DateFormat.Hm().format(this);
  }

  DateTime startOfDay() {
    return DateTime(year, month, day);
  }

  DateTime startOfNextDay() {
    return DateTime(year, month, day + 1);
  }

  bool isSameDayAs(DateTime other) {
    return day == other.day && month == other.month && year == other.year;
  }

  bool isSameTransportDayAs(DateTime other) {
    const startOfTransportDay = Duration(hours: 4); // 04:00
    return subtract(startOfTransportDay).isSameDayAs(other.subtract(startOfTransportDay));
  }

  String toRfc3339String() {
    return '${DateFormat('yyyy-MM-ddTHH:mm:ss').format(toLocal())}+0${timeZoneOffset.inHours}:00';
  }
}

extension LatLngExt on LatLng {
  bool inBounds(LatLngBounds bounds) =>
      latitude >= bounds.southwest.latitude &&
      latitude <= bounds.northeast.latitude &&
      longitude >= bounds.southwest.longitude &&
      longitude <= bounds.northeast.longitude;
}

extension StringBufferExt on StringBuffer {
  void writeIf(bool predicate, Object? object) {
    if (predicate) write(object);
  }
}

extension TrafficInformationExt on Iterable<TrafficSituation> {
  Iterable<TrafficSituation> sortTs(DateTime dateTime) {
    var list = toList(growable: false)
      ..sort((a, b) {
        int cmp = b.severity.compareTo(a.severity);
        if (cmp != 0) return cmp;
        return (dateTime.difference(a.startTime).abs() - dateTime.difference(b.startTime).abs()).inHours;
      });
    return list;
  }
}

extension FutureExt<T> on Future<T> {
  Future<T?> suppress() {
    return then((value) => Future<T?>.value(value)).catchError((_) => null);
  }
}

extension LatLngBoundsExt on LatLngBounds {
  LatLngBounds pad(double bufferRatio) {
    var heightBuffer = (southwest.latitude - northeast.latitude).abs() * bufferRatio;
    var widthBuffer = (southwest.longitude - northeast.longitude).abs() * bufferRatio;

    return LatLngBounds(
        southwest: LatLng(southwest.latitude - heightBuffer, southwest.longitude - widthBuffer),
        northeast: LatLng(northeast.latitude + heightBuffer, northeast.longitude + widthBuffer));
  }

  LatLngBounds minSize(double minSize) {
    var heightBuffer = (southwest.latitude - northeast.latitude).abs();
    var widthBuffer = (southwest.longitude - northeast.longitude).abs();

    heightBuffer = heightBuffer < minSize ? (minSize - heightBuffer) / 2 : 0;
    widthBuffer = widthBuffer < minSize ? (minSize - widthBuffer) / 2 : 0;

    return LatLngBounds(
        southwest: LatLng(southwest.latitude - heightBuffer, southwest.longitude - widthBuffer),
        northeast: LatLng(northeast.latitude + heightBuffer, northeast.longitude + widthBuffer));
  }
}

extension BoolExt on bool {
  bool implies(bool other) => !this || other;
}
