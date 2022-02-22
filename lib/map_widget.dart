import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/mapbox_gl.dart';

import 'departure_board_result_widget.dart';
import 'departure_board_widget.dart';
import 'extensions.dart';
import 'home_widget.dart';
import 'journey_detail_widget.dart';
import 'reseplaneraren.dart';
import 'utils.dart';
import 'vehicle_positions_service.dart';

class MapWidget extends StatefulWidget {
  final List<MapJourney> _mapJourneys;
  final List<int> focusStops;

  const MapWidget(this._mapJourneys, {this.focusStops = const [], Key? key}) : super(key: key);

  @override
  State createState() => MapWidgetState();
}

class MapWidgetState extends State<MapWidget> with WidgetsBindingObserver {
  late MaplibreMapController _mapController;

  final List<JourneyDetail> _journeyDetails = [];
  final Map<String, JourneyDetail> _journeyDetailById = {};
  final List<String> _journeyIds = [];
  final List<Vehicle> _vehicles = [];
  final List<MapFocusable<Stop>> _stops = [];
  final List<MapFocusable<Walk>> _walks = [];

  Timer? _timer;

  final LatLngBounds _mapBounds =
      LatLngBounds(southwest: const LatLng(55.02652, 10.54138), northeast: const LatLng(69.06643, 24.22472));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance!.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance!.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_timer == null) return;
    if (state != AppLifecycleState.resumed && _timer!.isActive) {
      _timer?.cancel();
    } else if (state == AppLifecycleState.resumed && !_timer!.isActive) {
      _initTimer();
    }
  }

  void _onMapCreated(MaplibreMapController controller) {
    _mapController = controller;
  }

  @override
  Widget build(BuildContext context) {
    return MaplibreMap(
        onMapCreated: _onMapCreated,
        onCameraIdle: widget._mapJourneys.isEmpty ? _onCameraIdle : null,
        trackCameraPosition: widget._mapJourneys.isEmpty,
        initialCameraPosition:
            CameraPosition(target: const LatLng(57.70, 11.97), zoom: widget._mapJourneys.isEmpty ? 13 : 11),
        cameraTargetBounds: CameraTargetBounds(_mapBounds),
        onStyleLoadedCallback: _onStyleLoadedCallback,
        styleString: 'https://osm.vasttrafik.se/styles/osm_vt_basic/style.json',
        myLocationEnabled: true,
        myLocationRenderMode: MyLocationRenderMode.NORMAL,
        onUserLocationUpdated: widget._mapJourneys.isEmpty ? _onUserLocationUpdated : null,
        annotationOrder: const [AnnotationType.fill, AnnotationType.line, AnnotationType.circle, AnnotationType.symbol],
        onMapClick: _onMapTap,
        onMapLongClick: (point, coord) => _onMapTap(point, coord, longClick: true),
        compassViewMargins: !kIsWeb && Platform.isAndroid
            ? math.Point(MediaQuery.of(context).padding.right + 8, MediaQuery.of(context).padding.top + 8)
            : const math.Point(8, 8),
        attributionButtonMargins: const math.Point(-100, -100),
        logoViewMargins: const math.Point(-100, -100));
  }

  void _onStyleLoadedCallback() {
    for (var mapJourney in widget._mapJourneys) {
      if (mapJourney.journeyDetail != null) {
        _addJourneyDetail(mapJourney.journeyDetail!, mapJourney.journeyPart, mapJourney.focus);
      } else if (mapJourney.journeyDetailRef != null) {
        _getJourneyDetailAndAdd(mapJourney.journeyDetailRef!, mapJourney.journeyPart, mapJourney.focus);
      } else if (mapJourney.walk) {
        _addWalk(mapJourney);
      }
    }

    _addImageFromAsset('bus', 'assets/bus.png', true);
    _addImageFromAsset('boat', 'assets/boat.png', true);
    _addImageFromAsset('tram', 'assets/tram.png', true);
    _addImageFromAsset('train', 'assets/train.png', true);
    _addImageFromAsset('railway', 'assets/railway.png', true);

    _initTimer();
  }

  void _initTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), _updatePosition);
    _updatePosition(_timer!);
  }

  Future<void> _updateJourneyDetail(
      StreamController streamController, Departure departure, Wrapper<JourneyDetail> journeyDetail) async {
    var response = await getJourneyDetail(departure.journeyDetailRef, departure.journeyId);
    journeyDetail.element = response?.journeyDetail;
    streamController.add(response);
  }

  Future<void> _addImageFromAsset(String name, String assetName, bool sdf) async {
    final ByteData bytes = await rootBundle.load(assetName);
    final Uint8List list = bytes.buffer.asUint8List();
    return _mapController.addImage(name, list, sdf);
  }

  bool _updatingNearbyStops = false;

  void _onCameraIdle() async {
    if (_updatingNearbyStops) return;
    _updatingNearbyStops = true;
    await _updateNearbyStops();
    _updatingNearbyStops = false;
  }

  bool _initialLocation = true;

  void _onUserLocationUpdated(UserLocation location) async {
    if (_initialLocation) {
      if (!location.position.inBounds(_mapBounds)) return;
      _initialLocation = false;
      await _mapController.animateCamera(CameraUpdate.newLatLng(location.position));
      _updateNearbyStops();
    }
  }

  void _onMapTap(math.Point<double> point, LatLng coord, {bool longClick = false}) async {
    if (!longClick) {
      List<math.Point<num>> points =
          await _mapController.toScreenLocationBatch(_stops.map((stop) => LatLng(stop.item.lat, stop.item.lon)));

      var touchRadius = math.pow(48 * _devicePixelRatio(context), 2);

      for (int i = 0; i < _stops.length; i++) {
        if (points[i].squaredDistanceTo(point) < touchRadius) {
          Stop stop = _stops[i].item;
          DateTime? dateTime = stop.getDateTime().isAfter(DateTime.now()) ? stop.getDateTime() : null;
          _showDepartureSheet(stopRowFromStop(stop), stopAreaFromStopId(stop.id), stop.lat, stop.lon,
              dateTime: dateTime);
          return;
        }
      }

      points = await _mapController.toScreenLocationBatch(_stopLocations.map((stop) => LatLng(stop.lat, stop.lon)));

      for (int i = 0; i < points.length; i++) {
        if (points[i].squaredDistanceTo(point) < touchRadius) {
          var stopLocation = _stopLocations.elementAt(i);
          _showDepartureSheet(
              highlightFirstPart(stopLocation.name), stopLocation.id, stopLocation.lat, stopLocation.lon,
              extraSliver: SliverSafeArea(
                bottom: false,
                sliver: SliverToBoxAdapter(
                    child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 5, 10, 0),
                  child: _locationOptionsWidget(stopLocation),
                )),
              ));
          return;
        }
      }
    }

    if (widget._mapJourneys.isEmpty) {
      var address = await reseplaneraren.getLocationNearbyAddress(coord.latitude, coord.longitude);
      if (address == null || !address.isValid) return;
      _marker = await _mapController.addCircle(CircleOptions(
          geometry: LatLng(address.lat, address.lon),
          circleColor: Colors.red.toHexCode(),
          circleRadius: 5,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 3));
      await _showAddressSheet(address);
      if (_marker != null) _mapController.removeCircle(_marker!);
    }
  }

  void _addJourneyDetail(JourneyDetail journeyDetail, JourneyPart? journeyPart, bool focus) {
    IdxJourneyPart? idxJourneyPart;
    if (journeyPart != null) {
      idxJourneyPart = journeyPart is FromStopIdJourneyPart
          ? IdxJourneyPart(journeyDetail.stop.firstWhere((stop) => stop.id == journeyPart.stopId).routeIdx,
              journeyDetail.stop.last.routeIdx)
          : journeyPart as IdxJourneyPart;
    }
    _addStops(journeyDetail, idxJourneyPart, focus);
    _addPolylines(journeyDetail, idxJourneyPart);
    _journeyDetails.add(journeyDetail);
    for (var journey in journeyDetail.journeyId) {
      _journeyIds.add(journey.id);
      _journeyDetailById[journey.id] = journeyDetail;
    }

    _updateBounds();
  }

  void _updateBounds() {
    if (_journeyDetails.length + _walks.length != widget._mapJourneys.length) return;
    var bound = _getBounds();
    if (bound == null) return;
    _mapController.animateCamera(CameraUpdate.newLatLngBounds(bound));
  }

  LatLngBounds? _getBounds() {
    Iterable<LatLng> points;
    if (widget._mapJourneys.any((mapJourney) => mapJourney.focus) || widget.focusStops.isNotEmpty) {
      var focusStops =
          widget.focusStops.map((id) => _journeyDetails.expand((jd) => jd.stop).firstWhere((stop) => stop.id == id));
      var allFocusedStops = _stops.where((stop) => stop.focus).map((stop) => stop.item).followedBy(focusStops);
      points = allFocusedStops.map((stop) => LatLng(stop.lat, stop.lon)).followedBy(
          _walks.where((walk) => walk.focus).map((walk) => [walk.item.start, walk.item.end]).expand((x) => x));
    } else {
      points = _stops
          .map((stop) => LatLng(stop.item.lat, stop.item.lon))
          .followedBy(_walks.map((walk) => [walk.item.start, walk.item.end]).expand((x) => x));
    }
    LatLngBounds? bounds = fromPoints(points);
    bounds = pad(bounds, 0.08);
    bounds = minSize(bounds, 0.0015);
    return bounds;
  }

  void _getJourneyDetailAndAdd(String journeyDetailRef, JourneyPart? journeyPart, bool focus) async {
    var response = await reseplaneraren.getJourneyDetail(journeyDetailRef);
    if (response == null) return;
    _addJourneyDetail(response, journeyPart, focus);
  }

  void _addWalk(MapJourney mapJourney) async {
    Iterable<Iterable<Point>>? geometry =
        mapJourney.geometry ?? await reseplaneraren.getGeometry(mapJourney.geometryRef!);
    if (geometry == null) return;
    for (var polyline in geometry) {
      _mapController.addLine(LineOptions(
          geometry: polyline.map((p) => LatLng(p.lat, p.lon)).toList(),
          lineColor: '#000000',
          lineOpacity: 0.5,
          lineWidth: 5,
          lineBlur: 2));
    }
    var start = geometry.first.first, end = geometry.last.last;
    _walks.add(MapFocusable(Walk(LatLng(start.lat, start.lon), LatLng(end.lat, end.lon)), mapJourney.focus));
    _updateBounds();
  }

  void _addPolylines(JourneyDetail journeyDetail, IdxJourneyPart? journeyPart) async {
    Iterable<Iterable<Point>>? geometry = await reseplaneraren.getGeometry(journeyDetail.geometryRef);
    if (geometry == null) return;

    if (journeyPart != null) {
      Stop firstStop = journeyDetail.stop.firstWhere((stop) => stop.routeIdx == journeyPart.fromIdx);
      Stop lastStop = journeyDetail.stop.firstWhere((stop) => stop.routeIdx == journeyPart.toIdx);

      for (var points in geometry) {
        bool draw = false;
        List<LatLng> pointsList = [];
        for (var point in points) {
          if (point.lon == firstStop.lon && point.lat == firstStop.lat) {
            if (draw) pointsList.clear();
            draw = true;
          }

          if (draw) pointsList.add(LatLng(point.lat, point.lon));

          if (draw && point.lon == lastStop.lon && point.lat == lastStop.lat) break;
        }

        _addLine(pointsList, journeyDetail.fgColor, journeyDetail.bgColor);
      }
    } else {
      for (var points in geometry) {
        var line = points.map((p) => LatLng(p.lat, p.lon)).toList();
        _addLine(line, journeyDetail.fgColor, journeyDetail.bgColor);
      }
    }
  }

  void _addLine(List<LatLng> points, Color color, Color borderColor) {
    List<LineOptions> lines = [
      LineOptions(geometry: points, lineColor: color.toHexCode(), lineWidth: 1, lineGapWidth: 5),
      LineOptions(geometry: points, lineColor: borderColor.toHexCode(), lineWidth: 5)
    ];
    if (kIsWeb) {
      for (var line in lines) {
        _mapController.addLine(line);
      }
    } else {
      _mapController.addLines(lines);
    }
  }

  void _addStops(JourneyDetail journeyDetail, IdxJourneyPart? journeyPart, bool focus) {
    Iterable<Stop> stops = journeyPart == null
        ? journeyDetail.stop
        : journeyDetail.stop
            .where((stop) => stop.routeIdx >= journeyPart.fromIdx && stop.routeIdx <= journeyPart.toIdx);

    _stops.addAll(stops.map((stop) => MapFocusable(stop, focus)));

    for (var stop in stops) {
      _mapController.addCircle(CircleOptions(
          geometry: LatLng(stop.lat, stop.lon),
          circleColor: journeyDetail.fgColor.toHexCode(),
          circleRadius: 5,
          circleStrokeColor: journeyDetail.bgColor.toHexCode(),
          circleStrokeWidth: 3));
    }
  }

  Vehicle? _getVehicle(VehiclePosition vehiclePosition) {
    for (var vehicle in _vehicles) {
      if (vehicle.journeyId == vehiclePosition.journeyId) {
        return vehicle;
      }
    }
    return null;
  }

  bool _isOutdated(VehiclePosition vehiclePosition) {
    if (!vehiclePosition.dataStillRelevant) return true;
    Duration diff = DateTime.now().difference(vehiclePosition.updatedAt);
    bool still = vehiclePosition.atStop || vehiclePosition.speed < 10;
    return diff > Duration(minutes: still ? 5 : 1);
  }

  void _updatePosition(Timer timer) async {
    if (_journeyDetails.isEmpty) return;
    var response = await vehiclePositionsService.getPositions(_journeyIds);

    if (!mounted) return;

    if (response == null) {
      for (var vehicle in _vehicles) {
        if (!vehicle.outdatedChanged(true)) continue;
        var opacity = 0.5;
        _mapController.updateCircle(
            await vehicle.bgCircle, CircleOptions(circleOpacity: opacity, circleStrokeOpacity: opacity));
        _mapController.updateSymbol(await vehicle.fgSymbol, SymbolOptions(iconOpacity: opacity));
      }
    } else {
      for (var vehiclePosition in response) {
        var vehicle = _getVehicle(vehiclePosition);
        var coord = LatLng(vehiclePosition.lat, vehiclePosition.long);
        bool outdated = _isOutdated(vehiclePosition);

        if (vehicle != null) {
          double? opacity = vehicle.outdatedChanged(outdated) ? (outdated ? 0.5 : 1) : null;
          _mapController.updateCircle(await vehicle.bgCircle,
              CircleOptions(geometry: coord, circleOpacity: opacity, circleStrokeOpacity: opacity));
          _mapController.updateSymbol(await vehicle.fgSymbol, SymbolOptions(geometry: coord, iconOpacity: opacity));
        } else {
          Color fgColor = _journeyDetailById[vehiclePosition.journeyId]!.fgColor;
          Color bgColor = _journeyDetailById[vehiclePosition.journeyId]!.bgColor;
          String type = _journeyDetailById[vehiclePosition.journeyId]!.journeyType.first.type;

          _vehicles.add(Vehicle(
              vehiclePosition.journeyId,
              outdated,
              _mapController.addCircle(CircleOptions(
                  geometry: coord,
                  circleColor: bgColor.toHexCode(),
                  circleStrokeColor: fgColor.toHexCode(),
                  circleRadius: 16,
                  circleStrokeWidth: 1.5,
                  circleOpacity: outdated ? 0.5 : null,
                  circleStrokeOpacity: outdated ? 0.5 : null)),
              _mapController.addSymbol(SymbolOptions(
                  geometry: coord,
                  iconImage: _getVehicleIconName(type),
                  iconColor: fgColor.toHexCode(),
                  iconSize: 0.25 * _devicePixelRatio(context),
                  iconOpacity: outdated ? 0.5 : null))));
        }
      }
    }
  }

  Circle? _marker;

  final Set<StopLocation> _stopLocations = {};
  final Map<int, Circle> _circleMap = {};

  Future<void> _updateNearbyStops() async {
    var coord = _mapController.cameraPosition?.target;
    if (coord == null) return;

    // Remove all stops when zoomed out
    if (_mapController.cameraPosition!.zoom < 12.5) {
      await _mapController.removeCircles(_circleMap.values);
      _circleMap.clear();
      _stopLocations.clear();
      return;
    }

    Set<StopLocation>? nearbyStops =
        (await reseplaneraren.getLocationNearbyStops(coord.latitude, coord.longitude, maxNo: 1000, maxDist: 3000))
            ?.where((stop) => stop.isStopArea)
            .toSet();
    if (nearbyStops == null || !mounted) return;

    String color = Theme.of(context).primaryColor.toHexCode();

    Set<StopLocation> add = nearbyStops.difference(_stopLocations);
    _stopLocations.addAll(add);

    var addedCircles = await _mapController.addCircles(add
        .map((stop) => CircleOptions(
            geometry: LatLng(stop.lat, stop.lon),
            circleColor: '#FFFFFF',
            circleStrokeColor: color,
            circleStrokeWidth: 3,
            circleRadius: 5))
        .toList(growable: false));

    for (int i = 0; i < add.length; i++) {
      _circleMap[add.elementAt(i).id] = addedCircles[i];
    }

    Set<StopLocation> remove = _stopLocations.difference(nearbyStops);
    _stopLocations.removeAll(remove);

    var circlesToRemove = remove.map((s) => _circleMap.remove(s.id)).cast<Circle>().toList(growable: false);

    await _mapController.removeCircles(circlesToRemove);
  }

  Widget _locationOptionsWidget(Location location) {
    return Row(
      children: [
        Expanded(
            child: ElevatedButton(
                child: const Text('Res härifrån'),
                onPressed: () {
                  Navigator.pop(context);
                  context.findAncestorStateOfType<HomeState>()?.setTripLocation(location, isOrigin: true);
                },
                onLongPress: () {
                  Navigator.pop(context);
                  context
                      .findAncestorStateOfType<HomeState>()
                      ?.setTripLocation(location, isOrigin: true, switchPage: false);
                })),
        const SizedBox(width: 10),
        Expanded(
            child: ElevatedButton(
                child: const Text('Res hit'),
                onPressed: () {
                  Navigator.pop(context);
                  context.findAncestorStateOfType<HomeState>()?.setTripLocation(location, isOrigin: false);
                },
                onLongPress: () {
                  Navigator.pop(context);
                  context
                      .findAncestorStateOfType<HomeState>()
                      ?.setTripLocation(location, isOrigin: false, switchPage: false);
                })),
      ],
    );
  }

  Future<void> _showAddressSheet(CoordLocation address) async {
    await showModalBottomSheet(
        context: context,
        builder: (context) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(title: highlightFirstPart(address.name), automaticallyImplyLeading: false),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: _locationOptionsWidget(address),
                ),
              ),
            ],
          );
        });
  }

  void _showDepartureSheet(Widget header, int stopId, double lat, double long,
      {DateTime? dateTime, Widget? extraSliver}) {
    final StreamController<DepartureBoardWithTrafficSituations?> streamController = StreamController();
    _updateDepartureBoard(streamController, stopId, dateTime);

    var _context = widget._mapJourneys.isEmpty ? Scaffold.of(context).context : context;

    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: cardBackgroundColor(context),
        builder: (context) {
          return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 2 / (1 + math.sqrt(5)),
              maxChildSize: 1 - MediaQuery.of(_context).padding.top / MediaQuery.of(_context).size.height,
              builder: (context, scrollController) {
                var appBar = SliverAppBar(title: header, pinned: true, automaticallyImplyLeading: false);
                return StreamBuilder<DepartureBoardWithTrafficSituations?>(
                  stream: streamController.stream,
                  builder: (context, departureBoardWithTs) {
                    if (!departureBoardWithTs.hasData) {
                      return CustomScrollView(
                          slivers: [
                        appBar,
                        SliverFillRemaining(
                            child: departureBoardWithTs.connectionState == ConnectionState.waiting
                                ? loadingPage()
                                : ErrorPage(() => _updateDepartureBoard(streamController, stopId, dateTime)))
                      ].insertIf(extraSliver != null, 1, extraSliver));
                    }
                    var bgLuminance = Theme.of(context).cardColor.computeLuminance();
                    return CustomScrollView(
                        controller: scrollController,
                        slivers: [
                          appBar,
                          SliverSafeArea(
                            sliver: departureBoardList(departureBoardWithTs.data!.departures, bgLuminance, lat, long,
                                onTap: (context, departure) {
                              Navigator.pop(context);
                              _showJourneyDetailSheet(departure);
                            }, onLongPress: (context, departure) {
                              Navigator.pop(context);
                              _showDepartureOnMap(departure, null);
                            }),
                            bottom: false,
                          ),
                          SliverSafeArea(
                            sliver: trafficSituationList(departureBoardWithTs.data!.ts,
                                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10), showAffectedStop: false),
                          )
                        ].insertIf(extraSliver != null, 1, extraSliver));
                  },
                );
              });
        });
  }

  Future<void> _updateDepartureBoard(StreamController streamController, int stopId, DateTime? dateTime) async {
    await getDepartureBoard(streamController, stopId, dateTime, departureBoardOptions, null);
  }

  void _showJourneyDetailSheet(Departure departure) {
    final StreamController<JourneyDetailWithTrafficSituations?> streamController = StreamController();
    Wrapper<JourneyDetail> journeyDetail = Wrapper(null);
    _updateJourneyDetail(streamController, departure, journeyDetail);

    var _context = widget._mapJourneys.isEmpty ? Scaffold.of(context).context : context;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 2 / (1 + math.sqrt(5)),
            maxChildSize: 1 - MediaQuery.of(_context).padding.top / MediaQuery.of(_context).size.height,
            builder: (context, scrollController) {
              return StreamBuilder<JourneyDetailWithTrafficSituations?>(
                  stream: streamController.stream,
                  builder: (context, journeyDetailWithTs) {
                    if (journeyDetailWithTs.connectionState == ConnectionState.waiting) return loadingPage();
                    if (!journeyDetailWithTs.hasData) {
                      return ErrorPage(() => _updateJourneyDetail(streamController, departure, journeyDetail));
                    }
                    var bgLuminance = Theme.of(context).cardColor.computeLuminance();
                    return CustomScrollView(controller: scrollController, slivers: [
                      SliverAppBar(
                          title: Row(
                            children: [
                              lineIconFromDeparture(departure, bgLuminance, context),
                              const SizedBox(width: 12),
                              Expanded(child: highlightFirstPart(departure.direction, overflow: TextOverflow.fade))
                            ],
                          ),
                          pinned: true,
                          automaticallyImplyLeading: false,
                          actions: [
                            IconButton(
                                onPressed: () async {
                                  Navigator.pop(context);
                                  _showDepartureOnMap(departure, journeyDetail.element);
                                },
                                icon: const Icon(Icons.map))
                          ]),
                      SliverSafeArea(
                          sliver: trafficSituationList(journeyDetailWithTs.data!.importantTs,
                              boldTitle: true, padding: const EdgeInsets.fromLTRB(10, 10, 10, 0)),
                          bottom: false),
                      SliverSafeArea(
                          sliver: journeyDetailList(
                              journeyDetailWithTs.data!.journeyDetail, journeyDetailWithTs.data!.stopNoteIcons),
                          bottom: false),
                      SliverSafeArea(
                        sliver: trafficSituationList(journeyDetailWithTs.data!.normalTs,
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10)),
                      ),
                    ]);
                  });
            });
      },
    );
  }

  void _showDepartureOnMap(Departure departure, JourneyDetail? journeyDetail) {
    if (_journeyIds.contains(departure.journeyId)) return;
    if (journeyDetail != null) {
      _addJourneyDetail(journeyDetail, FromStopIdJourneyPart(departure.stopId), false);
    } else {
      _getJourneyDetailAndAdd(departure.journeyDetailRef, FromStopIdJourneyPart(departure.stopId), false);
    }
  }

  double _devicePixelRatio(context) => (!kIsWeb && Platform.isAndroid ? MediaQuery.of(context).devicePixelRatio : 1);

  String _getVehicleIconName(String type) {
    switch (type) {
      case 'VAS':
        return 'train';
      case 'LDT':
        return 'railway';
      case 'REG':
        return 'railway';
      case 'BUS':
        return 'bus';
      case 'BOAT':
        return 'boat';
      case 'TRAM':
        return 'tram';
      default:
        return 'bus';
    }
  }
}

class MapJourney {
  String? journeyDetailRef;
  JourneyDetail? journeyDetail;
  JourneyPart? journeyPart;
  String? geometryRef;
  Iterable<Iterable<Point>>? geometry;
  late bool walk;
  bool focus;

  MapJourney(
      {this.journeyDetailRef,
      this.journeyDetail,
      this.journeyPart,
      this.geometryRef,
      this.geometry,
      bool? walk,
      this.focus = false}) {
    this.walk = walk ?? false;
  }
}

abstract class JourneyPart {}

class IdxJourneyPart extends JourneyPart {
  int fromIdx;
  int toIdx;

  IdxJourneyPart(this.fromIdx, this.toIdx);
}

class FromStopIdJourneyPart extends JourneyPart {
  int stopId;

  FromStopIdJourneyPart(this.stopId);
}

class MapFocusable<T> {
  final T item;
  final bool focus;

  MapFocusable(this.item, this.focus);
}

class Vehicle {
  String journeyId;
  Future<Circle> bgCircle;
  Future<Symbol> fgSymbol;
  late bool _outdated;

  bool outdatedChanged(bool outdated) {
    var changed = _outdated != outdated;
    _outdated = outdated;
    return changed;
  }

  Vehicle(this.journeyId, this._outdated, this.bgCircle, this.fgSymbol);
}

class Walk {
  final LatLng start;
  final LatLng end;

  Walk(this.start, this.end);
}
