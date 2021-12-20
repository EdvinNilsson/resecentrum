import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import 'extensions.dart';
import 'favorites.dart';
import 'reseplaneraren.dart';
import 'utils.dart';

class LocationSearcherWidget extends StatelessWidget {
  BuildContext? _context;
  Suggestions? _lastSuggestions;
  final String _hintText;
  final bool _onlyStops;
  Location? _initialLocation;

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
              data: Theme.of(context).copyWith(
                  textSelectionTheme:
                      TextSelectionThemeData(selectionColor: darken(Theme.of(context).primaryColor, 0.1))),
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
                          _initialSuggestions('');
                        },
                        icon: const Icon(Icons.clear, color: Colors.white60))),
                style: const TextStyle(fontSize: 18, color: Colors.white),
              ))),
      body: StreamBuilder<Suggestions?>(
        builder: (context, option) {
          if (option.connectionState == ConnectionState.waiting) return loadingPage();
          if (!option.hasData) return errorPage(() => _getSuggestions(_textController.text));
          return CustomScrollView(
            slivers: [
              SeparatedSliverList(
                itemCount: option.data!._favorites.length,
                itemBuilder: (context, i) {
                  var location = option.data!._favorites.elementAt(i);
                  return SuggestionWidget(location, () => _onSelected(location));
                },
                separatorBuilder: (context, index) {
                  return const Divider(height: 1);
                },
              ),
              const SliverToBoxAdapter(child: Divider(height: 1)),
              SeparatedSliverList(
                itemCount: option.data!._online.length,
                itemBuilder: (context, i) {
                  var location = option.data!._online.elementAt(i);
                  return SuggestionWidget(location, () => _onSelected(location));
                },
                separatorBuilder: (context, index) {
                  return const Divider(height: 1);
                },
              )
            ],
          );
        },
        stream: _streamController.stream,
      ),
    );
  }

  Timer? _debounce;

  void _onChanged(String value) {
    _getLocalSuggestions(value);
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _getSuggestions(value);
    });
  }

  void _onSubmitted(String value) async {
    var firstLocation = _lastSuggestions?._favorites.tryElementAt(0) ?? _lastSuggestions?._online.tryElementAt(0);
    if (firstLocation != null) _onSelected(firstLocation);
  }

  void _onSelected(Location location) {
    _textController.text = location.name;
    Navigator.pop(_context!, location);
  }

  void _initialSuggestions(String input) {
    if (isFavoritesEmpty) {
      _getSuggestions(input, initial: true);
    } else {
      _getLocalSuggestions('');
      _lastSuggestions?._online = {};
    }
  }

  void _getLocalSuggestions(String input) {
    var result = searchLocation(input);
    if (_onlyStops) result = result.whereType<StopLocation>();
    if (_initialLocation != null) {
      result = result.toList()..insert(0, _initialLocation!);
      _initialLocation = null;
    }
    _lastSuggestions = Suggestions(result.toSet(), _lastSuggestions?._online ?? {});
    _streamController.add(_lastSuggestions);
  }

  void _getSuggestions(String input, {bool initial = false}) async {
    Iterable<Location>? response = await reseplaneraren.getLocationByName(input, onlyStops: _onlyStops);
    if (response == null) {
      if (initial) _streamController.add(null);
      return;
    }
    _lastSuggestions = Suggestions(_lastSuggestions?._favorites ?? {}, response.toSet());
    _streamController.add(_lastSuggestions);
  }
}

IconData _getLocationIcon(Location location) {
  if (location is StopLocation) return Icons.directions_bus;
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

  const SuggestionWidget(this._location, this._onTap, {this.onLongPress, this.callOnFavoriteChange = true, Key? key})
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
  final Set<Location> _favorites;
  Set<Location> _online;

  Suggestions(this._favorites, this._online) {
    _online = _online.difference(_favorites);
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
    widget._textController.text = widget._controller._location?.name ?? '';
    widget._controller.addListener(() {
      if (!mounted) return;
      setState(() {
        widget._textController.text = widget._controller._location?.name ?? '';
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
                    widget._textController.text, widget._hintText, widget.onlyStops, widget._controller.location),
                transitionDuration: const Duration(seconds: 0),
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
