import 'package:diacritic/diacritic.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import 'main.dart';
import 'network/planera_resa.dart';

part 'favorites.g.dart';

@HiveType(typeId: 2)
class TripHistory {
  @HiveField(0)
  late final Location from;
  @HiveField(1)
  late final Location to;
  @HiveField(2)
  late final Location? via;
  @HiveField(3)
  bool favorite = false;

  TripHistory();

  TripHistory.from(this.from, this.to, this.via);

  @override
  bool operator ==(Object other) => (other is TripHistory) && hashCode == other.hashCode;

  @override
  int get hashCode => from.name.hashCode + 3 * to.name.hashCode + 5 * (via?.name.hashCode ?? 0);
}

bool get isFavoritesEmpty => favoriteLocationsBox.isEmpty;

String _term(String prefix) {
  return removeDiacritics(prefix.toLowerCase().replaceAll('å', '{').replaceAll('ä', '|').replaceAll('ö', '}'))
      .replaceAll(',', ' ');
}

VoidCallback? onFavoriteChange;

void addFavoriteLocation(Location location, {bool callOnChange = true}) {
  String term = _term(location.name);
  favoriteLocationsBox.put(term, location);
  if (callOnChange) onFavoriteChange?.call();
}

void removeFavoriteLocation(Location location, {bool callOnChange = true}) {
  String term = _term(location.name);
  favoriteLocationsBox.delete(term);
  if (callOnChange) onFavoriteChange?.call();
}

bool isLocationFavorite(Location location) {
  String term = _term(location.name);
  return favoriteLocationsBox.containsKey(term) && favoriteLocationsBox.get(term).runtimeType == location.runtimeType;
}

Iterable<Location> get allFavoriteLocations {
  return favoriteLocationsBox.values;
}

Iterable<Location> searchLocation(String term) {
  String prefix = _term(term);
  Iterable<String> keys = favoriteLocationsBox.keys.cast<String>();
  int comparator(a, b) => _getPrefix(a, prefix.length).compareTo(_getPrefix(b, prefix.length));
  var firstIndex = _firstIndexOf<String>(keys, prefix, comparator);
  if (firstIndex < 0) return [];
  var lastIndex = _lastIndexOf<String>(keys, prefix, comparator);

  return Iterable<int>.generate(lastIndex - firstIndex + 1, (n) => firstIndex + n)
      .map((n) => favoriteLocationsBox.getAt(n)!);
}

String _getPrefix(String word, int len) {
  if (word.length <= len) return word;
  return word.substring(0, len);
}

List<TripHistory> _trips = List<TripHistory>.from(tripBox.get('trips', defaultValue: <TripHistory>[]));

void addTripHistory(Location from, Location to, Location? via) {
  var element = TripHistory.from(from, to, via);
  int elementIndex = _trips.indexOf(element);
  if (elementIndex >= 0) {
    if (_trips[elementIndex].favorite) return;
    _trips.remove(element);
  }
  int lastFavoriteIndex = _trips.lastIndexWhere((t) => t.favorite);
  _trips.insert(lastFavoriteIndex + 1, element);
  if (_trips.length > 20) {
    int removeIndex = _trips.lastIndexWhere((t) => !t.favorite);
    _trips.removeAt(removeIndex);
  }
  tripBox.put('trips', _trips);
}

void undoTripDeletion(int index, TripHistory trip) {
  _trips.insert(index, trip);
  tripBox.put('trips', _trips);
}

void removeTripHistory(TripHistory element) {
  _trips.remove(element);
  tripBox.put('trips', _trips);
}

void reorderTripHistory(int oldIndex, int newIndex) {
  var temp = _trips.removeAt(oldIndex);
  if (newIndex > oldIndex) newIndex--;
  _trips.insert(newIndex, temp);
  tripBox.put('trips', _trips);
}

bool isTripFavorite(TripHistory trip) {
  int index = _trips.indexOf(trip);
  return index < 0 ? false : _trips[index].favorite;
}

void setTripFavorite(TripHistory trip, bool favorite) {
  int index = _trips.indexOf(trip);
  if (index < 0) return;
  _trips[index].favorite = favorite;
  tripBox.put('trips', _trips);
}

Iterable<TripHistory> get tripHistory => _trips;

void moveFavoriteTripToTop() {
  var favoriteTrips = _trips.where((trip) => trip.favorite);
  var historyTrips = _trips.where((trip) => !trip.favorite);
  _trips = favoriteTrips.followedBy(historyTrips).toList();
}

int _firstIndexOf<T>(Iterable<T> a, T key, Comparator<T> comparator) {
  int lo = 0, hi = a.length - 1, lowest = -1;

  while (lo <= hi) {
    int mid = (lo + hi) ~/ 2;
    int comparison = comparator(a.elementAt(mid), key);
    if (comparison > 0) {
      hi = mid - 1;
    } else if (comparison < 0) {
      lo = mid + 1;
    } else {
      lowest = mid;
      hi = mid - 1;
    }
  }
  return lowest;
}

int _lastIndexOf<T>(Iterable<T> a, T key, Comparator<T> comparator) {
  int lo = 0, hi = a.length - 1, highest = -1;

  while (lo <= hi) {
    int mid = (lo + hi) ~/ 2;
    int comparison = comparator(a.elementAt(mid), key);
    if (comparison > 0) {
      hi = mid - 1;
    } else if (comparison < 0) {
      lo = mid + 1;
    } else {
      highest = mid;
      lo = mid + 1;
    }
  }
  return highest;
}
