import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

import 'extensions.dart';
import 'favorites.dart';
import 'reseplaneraren.dart';
import 'utils.dart';

class LocationSearcherWidget extends StatelessWidget {
  late BuildContext _context;
  Suggestions? _lastSuggestions;
  final String _hintText;
  final bool _onlyStops;
  final Location? _initialLocation;

  final TextEditingController _textController = RichTextEditingController();
  final StreamController<Suggestions?> _streamController = StreamController();

  LocationSearcherWidget(String currentText, this._hintText, this._onlyStops, this._initialLocation, {Key? key})
      : super(key: key) {
    if (currentText.isNotEmpty) {
      _textController.text = currentText;
      _textController.selection = TextSelection(baseOffset: 0, extentOffset: currentText.length);
    }
    _initialSuggestions(currentText);
  }

  @override
  Widget build(BuildContext context) {
    _context = context;
    return Scaffold(
      appBar: AppBar(
          title: Theme(
              data: Theme.of(context)
                  .copyWith(textSelectionTheme: const TextSelectionThemeData(selectionColor: Colors.black26)),
              child: TextField(
                controller: _textController,
                onChanged: _onChanged,
                onSubmitted: _onSubmitted,
                autofocus: true,
                cursorColor: Colors.white,
                keyboardType: TextInputType.streetAddress,
                decoration: InputDecoration(
                    hintText: _hintText,
                    hintStyle: const TextStyle(color: Colors.white60),
                    suffixIcon: IconButton(
                        onPressed: () {
                          _textController.clear();
                          _onChanged('');
                        },
                        icon: const Icon(Icons.clear, color: Colors.white60))),
                style: const TextStyle(fontSize: 18, color: Colors.white),
              ))),
      body: StreamBuilder<Suggestions?>(
        builder: (context, option) {
          if (option.connectionState == ConnectionState.waiting) return loadingPage();
          if (!option.hasData) return ErrorPage(() => _getSuggestions(_textController.text), error: option.error);
          var suggestions = option.data!.suggestions;
          if (suggestions.isEmpty) {
            return _lastSuggestions?._online == null ? loadingPage() : noDataPage('Inga resultat', icon: Icons.search);
          }
          return CustomScrollView(
            slivers: [
              SliverSafeArea(
                  sliver: SeparatedSliverList(
                itemBuilder: (context, i) {
                  var location = suggestions.elementAt(i);

                  String? distanceText;
                  if (option.data!.showDistance) {
                    int distance = Geolocator.distanceBetween(
                            location.lat, location.lon, _initialLocation!.lat, _initialLocation!.lon)
                        .round();
                    distanceText =
                        distance < 1000 ? '${distance.round()} m' : '${NumberFormat('#.#').format(distance / 1000)} km';
                  }

                  return SuggestionWidget(location, () => _onSelected(location), extraText: distanceText);
                },
                separatorBuilder: (context, i) => const Divider(height: 1),
                itemCount: suggestions.length,
                addEndingSeparator: true,
              ))
            ],
          );
        },
        stream: _streamController.stream,
      ),
    );
  }

  Timer? _debounce;
  Future<void>? suggestionsFuture;
  String? nextSearch;

  void _onChanged(String value, {localSearch = true}) {
    if (localSearch) _getLocalSuggestions(value);

    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 100), () {
      if (suggestionsFuture != null) nextSearch = value;

      suggestionsFuture ??= _getSuggestions(value).then((_) async {
        suggestionsFuture = null;
        if (nextSearch != null) {
          _onChanged(nextSearch!, localSearch: false);
          nextSearch = null;
        }
      });
    });
  }

  void _onSubmitted(String value) async {
    var firstLocation = _lastSuggestions?._offline.tryElementAt(0) ?? _lastSuggestions?._online?.tryElementAt(0);
    if (firstLocation != null) _onSelected(firstLocation);
  }

  void _onSelected(Location location) {
    _textController.text = location.name;
    Navigator.pop(_context, location);
  }

  void _initialSuggestions(String input) async {
    if (_initialLocation is CurrentLocation && await _getNearbyStops()) {
    } else if (isFavoritesEmpty) {
      _getSuggestions(input);
    } else {
      _getLocalSuggestions('', initial: true);
      _lastSuggestions?._online = null;
    }
  }

  void _getLocalSuggestions(String input, {bool initial = false}) {
    var result = searchLocation(input);
    if (_onlyStops) result = result.whereType<StopLocation>().cast<Location>();
    if (initial && _initialLocation != null && _initialLocation is! CurrentLocation) {
      result = {_initialLocation!}.followedBy(result);
    }
    if (result.isEmpty && _lastSuggestions?.suggestions.isEmpty == true) return;
    _lastSuggestions = Suggestions(result.toSet(), _lastSuggestions?._online);
    _streamController.add(_lastSuggestions);
  }

  Future<void> _getSuggestions(String input) async {
    Iterable<Location>? response;
    try {
      response = await reseplaneraren.getLocationByName(input, onlyStops: _onlyStops);
    } catch (error) {
      if (_lastSuggestions?._offline.isEmpty ?? true) {
        _streamController.addError(error);
        return;
      }
    }
    _lastSuggestions = Suggestions(_lastSuggestions?._offline ?? {}, response?.toSet());
    _streamController.add(_lastSuggestions);
  }

  Future<bool> _getNearbyStops() async {
    var currentLocation = (_initialLocation as CurrentLocation);
    Location? location;

    try {
      location = currentLocation.cachedLocation ?? await currentLocation.location(onlyStops: _onlyStops);
    } catch (e) {
      if (e is DisplayableError) {
        noLocationFound(_context, onlyStops: _onlyStops, plural: true, description: e.description ?? e.message);
      }
      return false;
    }

    if (location == null) return false;

    Iterable<StopLocation>? response;
    try {
      response = await reseplaneraren.getLocationNearbyStops(currentLocation.lat, currentLocation.lon,
          maxNo: 100, maxDist: 3000);
    } catch (error) {
      _streamController.addError(error);
      return false;
    }

    var stops = response.where((s) => s.isStopArea);

    _lastSuggestions = Suggestions(location is CoordLocation ? {location} : {}, stops.toSet(), showDistance: true);
    _streamController.add(_lastSuggestions);

    return true;
  }
}

IconData _getLocationIcon(Location location) {
  if (location is StopLocation) return getStopIcon(location.id.toString());
  if (location is CoordLocation && location.type == 'POI') {
    return Icons.account_balance;
  }
  return Icons.place;
}

class SuggestionWidget extends StatefulWidget {
  final Location _location;
  final VoidCallback _onTap;
  final VoidCallback? onLongPress;
  final bool callOnFavoriteChange;
  final String? extraText;

  const SuggestionWidget(this._location, this._onTap,
      {this.onLongPress, this.callOnFavoriteChange = true, this.extraText, Key? key})
      : super(key: key);

  @override
  State<SuggestionWidget> createState() => _SuggestionWidgetState();
}

class _SuggestionWidgetState extends State<SuggestionWidget> {
  _SuggestionWidgetState();

  @override
  Widget build(BuildContext context) {
    var favorite = isLocationFavorite(widget._location);
    return InkWell(
      onTap: widget._onTap,
      onLongPress: widget.onLongPress,
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(_getLocationIcon(widget._location), color: Theme.of(context).hintColor),
          const SizedBox(width: 12),
          Expanded(child: highlightFirstPart(widget._location.name)),
          if (widget.extraText != null) Text(widget.extraText!, style: TextStyle(color: Theme.of(context).hintColor)),
          IconButton(
              icon: Icon(favorite ? Icons.star : Icons.star_border,
                  color: favorite ? Theme.of(context).primaryColor : Theme.of(context).hintColor),
              onPressed: () {
                if (favorite) {
                  removeFavoriteLocation(widget._location, callOnChange: widget.callOnFavoriteChange);
                } else {
                  addFavoriteLocation(widget._location, callOnChange: widget.callOnFavoriteChange);
                }
                setState(() {});
              })
        ],
      ),
    );
  }
}

class Suggestions {
  final Set<Location> _offline;
  Set<Location>? _online;
  final bool showDistance;

  Iterable<Location> get suggestions => _offline.followedBy(_online ?? {});

  Suggestions(this._offline, this._online, {this.showDistance = false}) {
    if (_online == null) return;
    var groupByFavorite = _online!.difference(_offline).groupSetsBy((l) => isLocationFavorite(l));
    _online = (groupByFavorite[true] ?? {}).union(groupByFavorite[false] ?? {});
  }
}

class LocationFieldController extends ChangeNotifier {
  Location? _location;
  String? _errorText;
  final String _key;
  final Box _box;

  LocationFieldController(this._key, this._box) {
    _location = _box.get(_key);
  }

  Location? get location => _location;

  void setErrorText(String? errorText) {
    _errorText = errorText;
    notifyListeners();
  }

  void clearError() => setErrorText(null);

  void setLocation(Location? location) {
    _location = location;
    _box.put(_key, _location);
    if (_location != null) {
      clearError();
    } else {
      notifyListeners();
    }
  }

  void update() => notifyListeners();

  void clearLocation() => setLocation(null);
}

class LocationField extends StatefulWidget {
  final TextEditingController _textController;
  final String _hintText;
  final bool onlyStops;
  final Widget? suffixIcon;
  final LocationFieldController _controller;
  final FocusNode? focusNode;

  const LocationField(this._controller, this._textController, this._hintText,
      {this.suffixIcon, this.onlyStops = false, this.focusNode, Key? key})
      : super(key: key);

  @override
  State<LocationField> createState() => _LocationFieldState();
}

class _LocationFieldState extends State<LocationField> {
  @override
  void initState() {
    widget._textController.text = widget._controller._location?.getName() ?? '';
    if (widget._controller.location is CurrentLocation) {
      var currentLocation = widget._controller.location as CurrentLocation;
      currentLocation.onNameChange = () => widget._controller.update();
      currentLocation.location(onlyStops: widget.onlyStops);
    }
    widget._controller.addListener(() {
      if (!mounted) return;
      setState(() {
        widget._textController.text = widget._controller._location?.getName() ?? '';
      });
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
        controller: widget._textController,
        decoration: InputDecoration(
            hintText: widget._hintText, suffixIcon: widget.suffixIcon, errorText: widget._controller._errorText),
        readOnly: true,
        autofocus: true,
        focusNode: widget.focusNode,
        onTap: () async {
          Location? result = await Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => LocationSearcherWidget(
                    widget._controller._location is CurrentLocation
                        ? (widget._controller._location as CurrentLocation).cachedLocation?.name ?? ''
                        : widget._textController.text,
                    widget._hintText,
                    widget.onlyStops,
                    widget._controller.location),
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              ));
          if (result == null) return;
          widget._controller.setLocation(result);
        });
  }
}

class RichTextEditingController extends TextEditingController {
  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    return highlightFirstPartSpan(text, style, context);
  }
}
