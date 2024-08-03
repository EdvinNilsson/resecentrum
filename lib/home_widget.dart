import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'departure_board_result_widget.dart';
import 'departure_board_widget.dart';
import 'extensions.dart';
import 'location_searcher.dart';
import 'main.dart';
import 'map_widget.dart';
import 'network/planera_resa.dart';
import 'options_panel.dart';
import 'traffic_information_widget.dart';
import 'trip_result_widget.dart';
import 'trip_widget.dart';
import 'utils.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<StatefulWidget> createState() => HomeState();
}

class HomeState extends State<Home> {
  int _currentIndex = mainBox.get('tab', defaultValue: 0);
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  final GlobalKey<MapWidgetState> _mapKey = GlobalKey();
  Location? _searchedLocation;

  late final List<Widget> _tabs;

  final List<String> _pageTitles = ['Sök resa', 'Nästa tur', 'Trafikinformation', 'Karta'];

  @override
  void initState() {
    super.initState();
    _tabs = [
      TripWidget(),
      DepartureBoardWidget(),
      const TrafficInformationWidget(),
      MapWidget(const [], key: _mapKey),
    ];
    _initDeepLinks();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var appbar = AppBar(
      centerTitle: true,
      title: Text(_pageTitles[_currentIndex]),
    );
    var landscape = MediaQuery.of(context).orientation == Orientation.landscape;
    return Scaffold(
      appBar: appbar,
      body: SafeArea(
        child: Row(
          children: [
            if (landscape)
              NavigationRail(
                onDestinationSelected: _onTabTapped,
                labelType: NavigationRailLabelType.all,
                destinations: const [
                  NavigationRailDestination(icon: Icon(Icons.tram), label: Text('Sök resa')),
                  NavigationRailDestination(icon: Icon(Icons.departure_board), label: Text('Nästa tur')),
                  NavigationRailDestination(icon: Icon(Icons.error_outline), label: Text('Trafikinfo')),
                  NavigationRailDestination(icon: Icon(Icons.map), label: Text('Karta')),
                ],
                selectedIndex: _currentIndex,
              ),
            Expanded(child: _tabs[_currentIndex]),
          ],
        ),
      ),
      bottomNavigationBar: !landscape
          ? NavigationBar(
              onDestinationSelected: _onTabTapped,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.tram), label: 'Sök resa'),
                NavigationDestination(icon: Icon(Icons.departure_board), label: 'Nästa tur'),
                NavigationDestination(icon: Icon(Icons.error_outline), label: 'Trafikinfo'),
                NavigationDestination(icon: Icon(Icons.map), label: 'Karta'),
              ],
              selectedIndex: _currentIndex,
            )
          : null,
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
      double? lng = parseDouble(splits.tryElementAt(1));
      if (lat != null && lng != null) {
        try {
          var location = await getLocationFromCoord(LatLng(lat, lng), stopMaxDist: 100);
          setTripLocation(location, isOrigin: false);
        } on DisplayableError catch (e) {
          if (!context.mounted) return;
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

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleLink(uri);
    });
  }
}
