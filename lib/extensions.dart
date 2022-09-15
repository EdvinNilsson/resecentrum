import 'dart:ui';

import 'package:intl/intl.dart';
import 'package:maplibre_gl/mapbox_gl.dart';

import 'reseplaneraren.dart';
import 'utils.dart';

extension IterableExt<T> on Iterable<T> {
  T? tryElementAt(int index) {
    try {
      return elementAt(index);
    } catch (e) {
      return null;
    }
  }
}

extension ListExt<T> on List<T> {
  List<T> addIf(bool predicate, T? value) {
    if (predicate) add(value!);
    return this;
  }

  List<T> insertIf(bool predicate, int index, T? value) {
    if (predicate) insert(index, value!);
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
    return toList(growable: false).getRange(0, length - 1).join(', ') + (length > 1 ? ' och ' : '') + last;
  }
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

  DateTime startONextDay() {
    return DateTime(year, month, day + 1);
  }

  bool isSameDayAs(DateTime other) {
    return day == other.day && month == other.month && year == other.year;
  }
}

extension LatLngExt on LatLng {
  bool inBounds(LatLngBounds bounds) =>
      latitude >= bounds.southwest.latitude &&
      latitude <= bounds.northeast.latitude &&
      longitude >= bounds.southwest.longitude &&
      longitude <= bounds.northeast.longitude;
}

extension TrafficInformationExt on Iterable<TrafficSituation> {
  Iterable<TrafficSituation> sortTs(DateTime dateTime) {
    var list = toList(growable: false)
      ..sort((a, b) {
        int cmp = getNotePriority(a.severity).compareTo(getNotePriority(b.severity));
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
