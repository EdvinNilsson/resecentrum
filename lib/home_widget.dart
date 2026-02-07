import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'departure_board_result_widget.dart';
import 'departure_board_widget.dart';
import 'extensions.dart';
import 'favorites.dart';
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
  final GlobalKey<TrafficInformationState> _trafficInfoKey = GlobalKey();
  final GlobalKey<MapWidgetState> _mapKey = GlobalKey();
  Location? _searchedLocation;
  int? _lastTabIndex;

  late final List<Widget> _tabs;
  final List<({IconData icon, String label})> _tabNames = [
    (label: 'Sök resa', icon: Icons.tram),
    (label: 'Nästa tur', icon: Icons.departure_board),
    (label: 'Trafikinfo', icon: Icons.error_outline),
    (label: 'Karta', icon: Icons.map),
  ];

  final List<Widget?> _navigators = List.filled(4, null);
  final List<GlobalKey<NavigatorState>> _navigatorKeys = List.generate(4, (_) => GlobalKey<NavigatorState>());

  bool get canPop =>
      _lastTabIndex != null || Navigator.of(_navigatorKeys[_currentIndex].currentContext ?? context).canPop();

  @override
  void initState() {
    super.initState();
    _tabs = [
      TripWidget(),
      DepartureBoardWidget(),
      Scaffold(
        appBar: AppBar(centerTitle: true, title: Text('Trafikinformation')),
        body: TrafficInformationWidget(key: _trafficInfoKey),
      ),
      Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text('Karta'),
          actions: [
            IconButton(
              onPressed: () async {
                Location? result = await Navigator.push(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) =>
                          LocationSearcherWidget(_searchedLocation?.name ?? '', 'Sök plats', false, _searchedLocation),
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                    ));
                if (result == null) return;
                _searchedLocation = result;
                _mapKey.currentState?.highlightLocation(result);
              },
              icon: const Icon(Icons.search),
            )
          ],
        ),
        body: MapWidget(const [], key: _mapKey),
      ),
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
    var landscape = MediaQuery.of(context).orientation == Orientation.landscape;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onPop,
      child: Scaffold(
        body: SafeArea(
          right: false,
          top: false,
          bottom: false,
          child: Row(
            children: [
              if (landscape)
                NavigationRail(
                  onDestinationSelected: _onTabTapped,
                  labelType: NavigationRailLabelType.all,
                  destinations: _tabNames
                      .map((tab) => NavigationRailDestination(icon: Icon(tab.icon), label: Text(tab.label)))
                      .toList(growable: false),
                  selectedIndex: _currentIndex,
                ),
              if (landscape) const VerticalDivider(width: 1),
              Expanded(
                child: Stack(children: [
                  _buildOffstageNavigator(0),
                  _buildOffstageNavigator(1),
                  _buildOffstageNavigator(2),
                  _buildVisibilityNavigator(3),
                ]),
              )
            ],
          ),
        ),
        bottomNavigationBar: !landscape
            ? NavigationBar(
                onDestinationSelected: _onTabTapped,
                destinations: _tabNames
                    .map((tab) => NavigationDestination(icon: Icon(tab.icon), label: tab.label))
                    .toList(growable: false),
                selectedIndex: _currentIndex,
              )
            : null,
      ),
    );
  }

  void _onPop(bool didPop, _) {
    if (didPop) return;

    final nav = _navigatorKeys[_currentIndex].currentState!;
    if (nav.canPop()) {
      nav.pop();
      return;
    }

    if (_lastTabIndex != null) {
      _onTabTapped(_lastTabIndex!);
      _lastTabIndex = null;
      var ctx = _navigatorKeys[_currentIndex].currentContext;
      if (ctx != null) NavigationNotification(canHandlePop: canPop).dispatch(ctx);
      return;
    }

    SystemNavigator.pop();
  }

  void _onTabTapped(int index) {
    if (index == _currentIndex) {
      _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);

      if (index == 2) {
        _trafficInfoKey.currentState?.scrollToTop();
      }
    } else {
      _lastTabIndex = _currentIndex;
      setState(() {
        _currentIndex = index;
      });
      var ctx = _navigatorKeys[_currentIndex].currentContext;
      if (ctx != null) NavigationNotification(canHandlePop: canPop).dispatch(ctx);
    }
    if (index < 2) {
      mainBox.put('tab', index);
      triggerFavoritesChange();
    }
  }

  Widget _buildOffstageNavigator(int index) {
    if (_currentIndex != index && _navigators[index] == null) return Container();
    return Offstage(
      offstage: _currentIndex != index,
      child: TickerMode(
        enabled: _currentIndex == index,
        child: _navigators[index] ??= Navigator(
          key: _navigatorKeys[index],
          observers: [HeroController()],
          onGenerateRoute: (settings) {
            return MaterialPageRoute(
              builder: (_) => _tabs[index],
            );
          },
        ),
      ),
    );
  }

  Widget _buildVisibilityNavigator(int index) {
    return Visibility(
      visible: _currentIndex == index,
      child: _navigators[index] ??= Navigator(
        key: _navigatorKeys[index],
        observers: [HeroController()],
        onGenerateRoute: (settings) {
          return MaterialPageRoute(
            builder: (_) => _tabs[index],
          );
        },
      ),
    );
  }

  void setTripLocation(Location location, {required bool isOrigin, bool switchPage = true}) {
    TripWidget tripWidget = _tabs.firstWhere((tab) => tab is TripWidget) as TripWidget;

    if (switchPage) {
      var pageIndex = _tabs.indexOf(tripWidget);
      Navigator.of(_navigatorKeys[pageIndex].currentContext ?? context).popUntil((route) => route.isFirst);
      _onTabTapped(pageIndex);
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
          if (!mounted) return;
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

            var tabIndex = _tabs.indexWhere((tab) => tab is DepartureBoardWidget);
            _onTabTapped(tabIndex);
            _openRoute(route, _navigatorKeys[tabIndex].currentContext ?? context);
            break;
          case 'trip':
            Location? from = parseLocation(uri.queryParameters, 'origin');
            Location? to = parseLocation(uri.queryParameters, 'dest');
            TripOptions options = ParamTripOptions(uri.queryParameters);

            if (from == null || to == null) break;

            var route = MaterialPageRoute(builder: (context) {
              return TripResultWidget(from, to, null, false, options);
            });

            var tabIndex = _tabs.indexWhere((tab) => tab is TripWidget);
            _onTabTapped(tabIndex);
            _openRoute(route, _navigatorKeys[tabIndex].currentContext ?? context);
            break;
        }
      } catch (e) {
        if (kDebugMode) print(e);
      }
    }
  }

  void _openRoute(Route route, BuildContext ctx) {
    Navigator.popUntil(context, (route) => route.isFirst);
    Navigator.push(ctx, route);
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleLink(uri);
    });
  }
}
