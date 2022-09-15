import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uni_links/uni_links.dart';

import 'departure_board_result_widget.dart';
import 'departure_board_widget.dart';
import 'extensions.dart';
import 'main.dart';
import 'map_widget.dart';
import 'options_panel.dart';
import 'reseplaneraren.dart';
import 'traffic_information_widget.dart';
import 'trip_result_widget.dart';
import 'trip_widget.dart';
import 'utils.dart';

bool _initialUriIsHandled = false;

class Home extends StatefulWidget {
  const Home({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => HomeState();
}

class HomeState extends State<Home> {
  int _currentIndex = mainBox.get('tab', defaultValue: 0);
  StreamSubscription? _sub;

  final List<Widget> _tabs = [
    TripWidget(),
    DepartureBoardWidget(),
    const TrafficInformationWidget(),
    const MapWidget([]),
  ];

  final List<String> _pageTitles = ['Sök resa', 'Nästa tur', 'Trafikinformation', 'Karta'];

  @override
  void initState() {
    super.initState();
    _handleIncomingLinks();
    _handleInitialUri();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(_pageTitles[_currentIndex]),
      ),
      body: _tabs[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        onTap: _onTabTapped,
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.tram), label: 'Sök resa'),
          BottomNavigationBarItem(icon: Icon(Icons.departure_board), label: 'Nästa tur'),
          BottomNavigationBarItem(icon: Icon(Icons.error_outline), label: 'Trafikinfo'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Karta')
        ],
      ),
    );
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
    if (index < 2) mainBox.put('tab', index);
  }

  void setTripLocation(Location location, {required bool isOrigin, bool switchPage = true}) {
    TripWidget tripWidget = _tabs.firstWhere((tab) => tab is TripWidget) as TripWidget;

    if (switchPage) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      setState(() {
        _currentIndex = _tabs.indexOf(tripWidget);
      });
    }

    (isOrigin ? tripWidget.fromFieldController : tripWidget.toFieldController).setLocation(location);
  }

  void _handleLink(Uri uri) async {
    if (uri.scheme == 'geo') {
      var splits = uri.path.split(',');
      double? lat = parseDouble(splits.tryElementAt(0));
      double? lon = parseDouble(splits.tryElementAt(1));
      if (lat != null && lon != null) {
        try {
          var location = await getLocationFromCoord(lat, lon, stopMaxDist: 100);
          setTripLocation(location, isOrigin: false);
        } on DisplayableError catch (e) {
          noLocationFound(context, description: e.description ?? e.message);
        }
      }
    } else if (uri.scheme == 'resecentrum') {
      if (kDebugMode) print(uri);
      try {
        switch (uri.host) {
          case 'board':
            Location? stop = parseLocation(uri.queryParameters, null);
            StopLocation? direction = parseLocation(uri.queryParameters, 'dir') as StopLocation?;
            DepartureBoardOptions options = ParamDepartureBoardOptions(uri.queryParameters);

            if (stop == null) break;

            var route = MaterialPageRoute(builder: (context) {
              return DepartureBoardResultWidget(stop, null, options, direction: direction);
            });

            if (Navigator.canPop(context)) {
              Navigator.pushReplacement(context, route);
            } else {
              Navigator.push(context, route);
            }
            break;
          case 'trip':
            Location? from = parseLocation(uri.queryParameters, 'origin');
            Location? to = parseLocation(uri.queryParameters, 'dest');
            TripOptions options = ParamTripOptions(uri.queryParameters);

            if (from == null || to == null) break;

            var route = MaterialPageRoute(builder: (context) {
              return TripResultWidget(from, to, null, false, options);
            });

            if (Navigator.canPop(context)) {
              Navigator.pushReplacement(context, route);
            } else {
              Navigator.push(context, route);
            }
            break;
        }
      } catch (e) {
        if (kDebugMode) print(e);
      }
    }
  }

  void _handleIncomingLinks() {
    if (!kIsWeb) {
      _sub = uriLinkStream.listen((Uri? uri) {
        if (!mounted) return;
        if (uri != null) _handleLink(uri);
      }, onError: (Object e) {
        if (!mounted) return;
        if (kDebugMode) print(e);
      });
    }
  }

  Future<void> _handleInitialUri() async {
    if (!_initialUriIsHandled) {
      _initialUriIsHandled = true;
      try {
        final uri = await getInitialUri();
        if (uri != null) _handleLink(uri);
        if (!mounted) return;
      } on PlatformException {
        if (kDebugMode) print('failed to get initial uri');
      } on FormatException {
        if (!mounted) return;
        if (kDebugMode) print('malformed initial uri');
      }
    }
  }
}
