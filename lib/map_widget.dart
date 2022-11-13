import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
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

  final dynamic _walksGeoJson = {'type': 'FeatureCollection', 'features': []};
  final dynamic _linesGeoJson = {'type': 'FeatureCollection', 'features': []};
  final dynamic _lineStopsGeoJson = {'type': 'FeatureCollection', 'features': []};
  final dynamic _stopsGeoJson = {'type': 'FeatureCollection', 'features': []};

  late final double devicePixelRatio;
  late final Color primaryColor;

  Timer? _timer;
  Ticker? _ticker;

  static CameraPosition? _lastPosition;

  Future<Iterable<VehiclePosition>?>? _initialVehiclePosition;

  final LatLngBounds _mapBounds =
      LatLngBounds(southwest: const LatLng(55.02652, 10.54138), northeast: const LatLng(69.06643, 24.22472));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance!.addObserver(this);
    var focusJourneyIds = widget._mapJourneys.map((j) => j.focusJid).whereNotNull();
    if (focusJourneyIds.isNotEmpty) {
      _initialVehiclePosition = vehiclePositionsService.getPositions(focusJourneyIds.toList(growable: false));
    }
  }

  @override
  void didChangeDependencies() {
    devicePixelRatio = !kIsWeb ? MediaQuery.of(context).devicePixelRatio : 1;
    primaryColor = Theme.of(context).primaryColor;
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    if (widget._mapJourneys.isEmpty) _lastPosition = _mapController.cameraPosition;
    WidgetsBinding.instance!.removeObserver(this);
    _timer?.cancel();
    _ticker?.stop();
    _ticker?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _timer?.isActive == true) {
      _timer?.cancel();
    } else if (state == AppLifecycleState.resumed && _timer?.isActive == false) {
      _initTimer();
    }
  }

  void _onMapCreated(MaplibreMapController controller) {
    _mapController = controller;
    _mapController.onFeatureTapped.add(_onFeatureTap);
  }

  @override
  Widget build(BuildContext context) {
    return MaplibreMap(
      onMapCreated: _onMapCreated,
      onCameraIdle: widget._mapJourneys.isEmpty ? _onCameraIdle : null,
      trackCameraPosition: widget._mapJourneys.isEmpty,
      initialCameraPosition: (widget._mapJourneys.isEmpty ? _lastPosition : null) ??
          CameraPosition(target: const LatLng(57.70, 11.97), zoom: widget._mapJourneys.isEmpty ? 13 : 11),
      cameraTargetBounds: CameraTargetBounds(_mapBounds),
      onStyleLoadedCallback: _onStyleLoadedCallback,
      styleString: 'https://osm.vasttrafik.se/styles/osm_vt_basic/style.json',
      myLocationEnabled: true,
      myLocationRenderMode: MyLocationRenderMode.NORMAL,
      onUserLocationUpdated: widget._mapJourneys.isEmpty ? _onUserLocationUpdated : null,
      onMapClick: _onMapTap,
      minMaxZoomPreference: const MinMaxZoomPreference(4, null),
      onMapLongClick: (point, coord) => _onMapTap(point, coord, longClick: true),
      compassViewMargins: !kIsWeb && Platform.isAndroid
          ? math.Point(MediaQuery.of(context).padding.right + 8, MediaQuery.of(context).padding.top + 8)
          : const math.Point(8, 8),
      attributionButtonMargins: const math.Point(-100, -100),
    );
  }

  void _onStyleLoadedCallback() async {
    _addImageFromAsset('bus', 'assets/bus.png', true);
    _addImageFromAsset('boat', 'assets/boat.png', true);
    _addImageFromAsset('tram', 'assets/tram.png', true);
    _addImageFromAsset('train', 'assets/train.png', true);
    _addImageFromAsset('railway', 'assets/railway.png', true);

    await _mapController.addGeoJsonSource('walks', _walksGeoJson);
    await _mapController.addGeoJsonSource('lines', _linesGeoJson);
    await _mapController.addGeoJsonSource('line-stops', _lineStopsGeoJson);
    await _mapController.addGeoJsonSource('vehicles', _getVehicleGeoJson(Duration.zero));

    await _mapController.addLineLayer(
        'walks',
        'walks',
        const LineLayerProperties(
          lineColor: '#000000',
          lineOpacity: 0.5,
          lineWidth: 4,
          lineDasharray: [
            Expressions.literal,
            [1, 1 / 2]
          ],
        ),
        enableInteraction: false);

    await _mapController.addCircleLayer(
        'line-stops',
        'line-stops-bg',
        const CircleLayerProperties(
          circleRadius: 9,
          circleColor: [Expressions.get, 'fgColor'],
        ),
        enableInteraction: false);

    await _mapController.addLineLayer(
        'lines',
        'lines-border',
        const LineLayerProperties(
          lineColor: [Expressions.get, 'fgColor'],
          lineGapWidth: 5,
        ),
        enableInteraction: false);

    await _mapController.addLineLayer(
        'lines',
        'lines',
        const LineLayerProperties(
          lineColor: [Expressions.get, 'bgColor'],
          lineWidth: 5,
        ),
        enableInteraction: false);

    if (widget._mapJourneys.isEmpty) {
      await _mapController.addGeoJsonSource('stops', _stopsGeoJson);

      await _mapController.addCircleLayer(
          'stops',
          'stops',
          CircleLayerProperties(
            circleColor: '#FFFFFF',
            circleStrokeColor: primaryColor.toHexCode(),
            circleStrokeWidth: 3,
            circleRadius: [
              Expressions.interpolate,
              ['linear'],
              ['zoom'],
              12,
              2,
              12.5,
              5,
            ],
            circleOpacity: [
              Expressions.interpolate,
              ['linear'],
              ['zoom'],
              12,
              0,
              12.5,
              1,
            ],
            circleStrokeOpacity: [
              Expressions.interpolate,
              ['linear'],
              ['zoom'],
              12,
              0,
              12.5,
              1,
            ],
          ),
          minzoom: 12,
          enableInteraction: false);
    }

    await _mapController.addCircleLayer(
        'line-stops',
        'line-stops',
        const CircleLayerProperties(
          circleColor: [Expressions.get, 'fgColor'],
          circleRadius: 5,
          circleStrokeColor: [Expressions.get, 'bgColor'],
          circleStrokeWidth: 3,
        ),
        enableInteraction: false);

    await _mapController.addCircleLayer(
        'vehicles',
        'vehicles-circle',
        const CircleLayerProperties(
          circleColor: [Expressions.get, 'bgColor'],
          circleStrokeColor: [Expressions.get, 'fgColor'],
          circleRadius: 16,
          circleStrokeWidth: 1.5,
          circleOpacity: [
            Expressions.caseExpression,
            [Expressions.get, 'outdated'],
            0.5,
            1
          ],
          circleStrokeOpacity: [
            Expressions.caseExpression,
            [Expressions.get, 'outdated'],
            0.5,
            1
          ],
        ));

    await _mapController.addSymbolLayer(
      'vehicles',
      'vehicles-icon',
      SymbolLayerProperties(
        iconAllowOverlap: true,
        iconImage: [Expressions.get, 'icon'],
        iconSize: 0.25 * devicePixelRatio,
        iconColor: [Expressions.get, 'fgColor'],
        iconOpacity: [
          Expressions.caseExpression,
          [Expressions.get, 'outdated'],
          0.5,
          1
        ],
      ),
    );

    var futures = <Future>[];
    for (var mapJourney in widget._mapJourneys) {
      if (mapJourney.journeyDetail != null) {
        _addJourneyDetail(mapJourney.journeyDetail!, mapJourney.journeyPart, mapJourney.focus);
      } else if (mapJourney.futureJourneyDetail != null) {
        futures.add(mapJourney.futureJourneyDetail!.then((jd) {
          if (jd != null) _addJourneyDetail(jd, mapJourney.journeyPart, mapJourney.focus);
        }));
      } else if (mapJourney.walk) {
        _addWalk(mapJourney);
      }
    }

    await Future.wait(futures);

    var initialPosition = await _initialVehiclePosition;
    _initTimer(initialPosition);

    var refStops = widget._mapJourneys
        .map((j) => j.refStopId)
        .whereNotNull()
        .map((stopId) => _journeyDetails.expand((jd) => jd.stop).firstWhere((stop) => stop.id == stopId))
        .map((s) => LatLng(s.lat, s.lon));

    var vehiclePos = _vehicles.map((v) => LatLng(v.position.lat, v.position.long));

    LatLngBounds? bounds;

    if (refStops.isNotEmpty && vehiclePos.isNotEmpty) {
      bounds = minBounds(
              fromPoints(vehiclePos.followedBy(refStops))?.pad(0.2), _getBounds(extraPoints: vehiclePos)?.pad(0.08))
          ?.minSize(0.005);
    } else {
      bounds = _getBounds()?.pad(0.08).minSize(0.003);
    }

    if (bounds != null) _mapController.animateCamera(CameraUpdate.newLatLngBounds(bounds));

    _ticker = Ticker(_updateInterpolation);
    _ticker?.start();
  }

  Future<void> _initTimer([Iterable<VehiclePosition>? initialPosition]) async {
    _timer = Timer.periodic(const Duration(seconds: 1), _updatePosition);
    await _updatePosition(_timer!, initialPosition);
  }

  Future<void> _updateJourneyDetail(
      StreamController streamController, Departure departure, Wrapper<JourneyDetail> journeyDetail) async {
    try {
      var response = await getJourneyDetail(departure.journeyDetailRef, departure.journeyId, departure.journeyNumber,
          departure.type, departure.stopId, departure.dateTime);
      journeyDetail.element = response.journeyDetail;
      streamController.add(response);
    } catch (error) {
      streamController.addError(error);
    }
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
    if (_initialLocation && _lastPosition == null) {
      if (!location.position.inBounds(_mapBounds)) return;
      _initialLocation = false;
      await _mapController.animateCamera(CameraUpdate.newLatLng(location.position));
      _updateNearbyStops();
    }
  }

  void _onFeatureTap(dynamic featureId, math.Point<double> point, LatLng latLng) async {
    var vehicle = _vehicles.firstWhereOrNull((v) => v.journeyId == featureId);
    if (vehicle == null) return;
    _showVehicleSheet(vehicle);
  }

  Future<void> _showVehicleSheet(Vehicle vehicle) async {
    var jd = _journeyDetailById[vehicle.journeyId]!;

    double sqDist(s) =>
        (s.lat - vehicle.position.lat) * (s.lat - vehicle.position.lat) +
        (s.lon - vehicle.position.long) * (s.lon - vehicle.position.long);
    int routeIdx = jd.stop.reduce((a, b) => sqDist(a) < sqDist(b) ? a : b).routeIdx;

    var lineColor = getValueAtRouteIdxWithJid(jd.journeyColor, routeIdx, vehicle.journeyId, jd.journeyId);
    var name = getValueAtRouteIdxWithJid(jd.journeyName, routeIdx, vehicle.journeyId, jd.journeyId).name;
    var direction = getValueAtRouteIdxWithJid(jd.direction, routeIdx, vehicle.journeyId, jd.journeyId).direction;

    await showModalBottomSheet(
        context: context,
        builder: (context) {
          var bgLuminance = Theme.of(context).cardColor.computeLuminance();
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                  title: Row(
                    children: [
                      lineIcon(
                          name, lineColor.fg, lineColor.bg, bgLuminance, jd.journeyType.first.type, '', null, context),
                      const SizedBox(width: 12),
                      Expanded(child: highlightFirstPart(direction, overflow: TextOverflow.fade))
                    ],
                  ),
                  automaticallyImplyLeading: false),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: StreamBuilder<VehiclePosition>(
                      stream: vehicle.streamController.stream,
                      builder: (context, snapshot) {
                        var vehiclePosition = snapshot.data ?? vehicle.position;
                        return Column(children: [
                          Text('Senast uppdaterad: ${DateFormat.Hms().format(vehiclePosition.updatedAt)}'),
                          Text('Hastighet: ${vehiclePosition.speed.round()} km/h'),
                        ]);
                      }),
                ),
              ),
            ],
          );
        });
  }

  void _onMapTap(math.Point<double> point, LatLng coord, {bool longClick = false}) async {
    if (!longClick) {
      List<math.Point<num>> points =
          await _mapController.toScreenLocationBatch(_stops.map((stop) => LatLng(stop.item.lat, stop.item.lon)));

      var touchRadius = math.pow(48 * devicePixelRatio, 2);

      for (int i = 0; i < _stops.length; i++) {
        if (points[i].squaredDistanceTo(point) < touchRadius) {
          Stop stop = _stops[i].item;
          DateTime? dateTime = stop.getDateTime();
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
                  padding: const EdgeInsets.fromLTRB(8, 5, 8, 0),
                  child: _locationOptionsWidget(stopLocation),
                )),
              ));
          return;
        }
      }
    }

    if (widget._mapJourneys.isEmpty) {
      var address = await reseplaneraren.getLocationNearbyAddress(coord.latitude, coord.longitude);
      if (address == null) return;
      if (_marker != null) _mapController.removeCircle(_marker!);
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
    _addStops(journeyDetail, journeyPart, focus);
    _addPolylines(journeyDetail, journeyPart);
    _journeyDetails.add(journeyDetail);
    for (var journey in journeyDetail.journeyId) {
      _journeyIds.add(journey.id);
      _journeyDetailById[journey.id] = journeyDetail;
    }
  }

  LatLngBounds? _getBounds({Iterable<LatLng>? extraPoints}) {
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
    return fromPoints(points.followedBy(extraPoints ?? []));
  }

  Future<void> _getJourneyDetailAndAdd(JourneyDetailRef ref,
      {JourneyPart? journeyPart, bool focus = false, int? fromStopId}) async {
    var journeyDetail = await getJourneyDetailExtra(ref);
    if (journeyDetail == null) return;
    if (fromStopId != null) journeyPart = JourneyPart.fromStopId(fromStopId, journeyDetail);
    _addJourneyDetail(journeyDetail, journeyPart, focus);
  }

  void _addWalk(MapJourney mapJourney) async {
    Iterable<Point>? geometry =
        mapJourney.geometry ?? await reseplaneraren.getGeometry(mapJourney.geometryRef!).suppress();
    if (geometry == null) return;
    _walksGeoJson['features'].add({
      'type': 'Feature',
      'geometry': {
        'type': 'LineString',
        'coordinates': geometry.map((p) => [p.lon, p.lat]).toList(growable: false),
      }
    });

    _mapController.setGeoJsonSource('walks', _walksGeoJson);
    var start = geometry.first, end = geometry.last;
    _walks.add(MapFocusable(Walk(LatLng(start.lat, start.lon), LatLng(end.lat, end.lon)), mapJourney.focus));
  }

  void _addPolylines(JourneyDetail journeyDetail, JourneyPart? journeyPart) async {
    Iterable<Point>? geometry = await reseplaneraren.getGeometry(journeyDetail.geometryRef).suppress();
    if (geometry == null) return;

    if (journeyDetail.journeyColor.length > 1) {
      for (var part in journeyDetail.journeyColor) {
        var line = getJourneyPart(
            journeyDetail,
            JourneyPart(math.max(part.routeIdxFrom, journeyPart?.fromIdx ?? 0),
                math.min(part.routeIdxTo, journeyPart?.toIdx ?? part.routeIdxTo)),
            geometry);
        _addLine(line, part.fg, part.bg);
      }
    } else if (journeyPart != null) {
      var line = getJourneyPart(journeyDetail, journeyPart, geometry);
      _addLine(line, journeyDetail.journeyColor.first.fg, journeyDetail.journeyColor.first.bg);
    } else {
      var line = geometry.map((p) => LatLng(p.lat, p.lon)).toList();
      _addLine(line, journeyDetail.journeyColor.first.fg, journeyDetail.journeyColor.first.bg);
    }
  }

  List<LatLng> getJourneyPart(JourneyDetail journeyDetail, JourneyPart journeyPart, Iterable<Point> geometry) {
    if (journeyPart.toIdx <= journeyPart.fromIdx) return [];

    Stop firstStop = journeyDetail.stop.firstWhere((stop) => stop.routeIdx == journeyPart.fromIdx);
    Stop lastStop = journeyDetail.stop.lastWhere((stop) => stop.routeIdx == journeyPart.toIdx);

    bool draw = false;
    List<LatLng> line = [];
    for (var point in geometry) {
      if (point.lon == firstStop.lon && point.lat == firstStop.lat) {
        if (draw) line.clear();
        draw = true;
      }

      if (draw) line.add(LatLng(point.lat, point.lon));

      if (draw && point.lon == lastStop.lon && point.lat == lastStop.lat) break;
    }

    return line;
  }

  void _addLine(List<LatLng> points, Color fgColor, Color bgColor) {
    if (points.isEmpty) return;
    _linesGeoJson['features'].add({
      'type': 'Feature',
      'properties': {
        'fgColor': fgColor.toHexCode(),
        'bgColor': bgColor.toHexCode(),
      },
      'geometry': {
        'type': 'LineString',
        'coordinates': points.map((p) => p.toGeoJsonCoordinates()).toList(growable: false),
      }
    });
    _mapController.setGeoJsonSource('lines', _linesGeoJson);
  }

  void _addStops(JourneyDetail journeyDetail, JourneyPart? journeyPart, bool focus) {
    Iterable<Stop> stops = journeyPart == null
        ? journeyDetail.stop
        : journeyDetail.stop
            .where((stop) => stop.routeIdx >= journeyPart.fromIdx && stop.routeIdx <= journeyPart.toIdx);

    _stops.addAll(stops.map((stop) => MapFocusable(stop, focus)));

    for (var stop in stops) {
      _lineStopsGeoJson['features'].add({
        'type': 'Feature',
        'id': stop.id.toString(),
        'properties': {
          'fgColor': journeyDetail.fgColor.toHexCode(),
          'bgColor': journeyDetail.bgColor.toHexCode(),
        },
        'geometry': {
          'type': 'Point',
          'coordinates': [stop.lon, stop.lat],
        }
      });
    }
    _mapController.setGeoJsonSource('line-stops', _lineStopsGeoJson);
  }

  Duration? _lastUpdate;

  void _updateInterpolation(Duration elapsed) {
    if (!mounted) return;
    var deltaTime = (elapsed - (_lastUpdate ?? Duration.zero));
    _lastUpdate = elapsed;
    for (var feature in _getVehicleGeoJsonFeatures(deltaTime)) {
      _mapController.setGeoJsonFeature('vehicles', feature);
    }
  }

  double _quadratic(double a, b, c, x) => a * x * x + b * x + c;

  Map<String, dynamic> _getVehicleGeoJson(Duration deltaTime) {
    return {
      'type': 'FeatureCollection',
      'features': _getVehicleGeoJsonFeatures(deltaTime).toList(growable: false),
    };
  }

  Iterable<Map<String, dynamic>> _getVehicleGeoJsonFeatures(Duration deltaTime) {
    double dt = deltaTime.inMicroseconds / (Duration.microsecondsPerSecond * 2);
    return _vehicles.map((vehicle) {
      vehicle.t += dt;

      double x = vehicle.t;

      if (vehicle.t > 1) {
        if (vehicle.position.speed < 10 || vehicle.t > 2) {
          x = 1;
        } else {
          x = (vehicle.t - 1) / 2 + 1;
        }
      }

      vehicle.interpolatedPosition =
          LatLng(_quadratic(vehicle.ax, vehicle.bx, vehicle.cx, x), _quadratic(vehicle.ay, vehicle.by, vehicle.cy, x));

      return {
        'type': 'Feature',
        'properties': vehicle.properties,
        'id': vehicle.journeyId,
        'geometry': {'type': 'Point', 'coordinates': vehicle.interpolatedPosition.toGeoJsonCoordinates()}
      };
    });
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

  Future<void> _updatePosition(Timer timer, [Iterable<VehiclePosition>? initialPosition]) async {
    if (_journeyDetails.isEmpty) return;

    var response = initialPosition ?? await vehiclePositionsService.getPositions(_journeyIds);

    if (!mounted) return;

    if (response == null) {
      for (var vehicle in _vehicles) {
        vehicle.properties['outdated'] = true;
        vehicle.updatePosition(vehicle.position, true, teleport: true);
      }
    } else {
      for (var vehiclePosition in response) {
        var vehicle = _getVehicle(vehiclePosition);
        bool outdated = _isOutdated(vehiclePosition);

        if (vehicle != null) {
          vehicle.properties['outdated'] = outdated;
          vehicle.updatePosition(vehiclePosition, outdated);
        } else {
          var journeyDetail = _journeyDetailById[vehiclePosition.journeyId]!;

          var fgColor = journeyDetail.fgColor;
          var bgColor = journeyDetail.bgColor;
          var type = journeyDetail.journeyType.first.type;

          _vehicles.add(Vehicle(vehiclePosition.journeyId, outdated, vehiclePosition, type, bgColor, fgColor));

          await _mapController.setGeoJsonSource('vehicles', _getVehicleGeoJson(Duration.zero));
        }
      }
    }
  }

  Circle? _marker;

  final Set<StopLocation> _stopLocations = {};

  Future<void> _updateNearbyStops() async {
    var coord = _mapController.cameraPosition?.target;
    if (coord == null) return;

    Set<StopLocation>? nearbyStops = (await reseplaneraren
            .getLocationNearbyStops(coord.latitude, coord.longitude, maxNo: 1000, maxDist: 3000)
            .suppress())
        ?.where((stop) => stop.isStopArea)
        .toSet();
    if (nearbyStops == null || !mounted) return;

    Set<StopLocation> add = nearbyStops.difference(_stopLocations);
    _stopLocations.addAll(add);

    for (var stop in add) {
      _stopsGeoJson['features'].add({
        'type': 'Feature',
        'id': stop.id.toString(),
        'geometry': {
          'type': 'Point',
          'coordinates': [stop.lon, stop.lat],
        }
      });
    }
    _mapController.setGeoJsonSource('stops', _stopsGeoJson);
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
    _updateDepartureBoard(streamController, stopId, dateTime, lat, long);

    var ctx = widget._mapJourneys.isEmpty ? Scaffold.of(context).context : context;

    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: cardBackgroundColor(context),
        builder: (context) {
          return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 2 / (1 + math.sqrt(5)),
              maxChildSize: 1 - MediaQuery.of(ctx).padding.top / MediaQuery.of(ctx).size.height,
              builder: (context, scrollController) {
                var appBar = SliverAppBar(title: header, pinned: true, automaticallyImplyLeading: false);
                return StreamBuilder<DepartureBoardWithTrafficSituations?>(
                  stream: streamController.stream,
                  builder: (context, departureBoardWithTs) {
                    if (!departureBoardWithTs.hasData) {
                      return CustomScrollView(
                          controller: scrollController,
                          slivers: [
                            appBar,
                            SliverFillRemaining(
                                child: departureBoardWithTs.connectionState == ConnectionState.waiting
                                    ? loadingPage()
                                    : ErrorPage(
                                        () => _updateDepartureBoard(streamController, stopId, dateTime, lat, long),
                                        error: departureBoardWithTs.error))
                          ].insertIf(extraSliver != null, 1, extraSliver));
                    }
                    var bgLuminance = Theme.of(context).cardColor.computeLuminance();
                    return CustomScrollView(
                        controller: scrollController,
                        slivers: [
                          appBar,
                          SliverSafeArea(
                            sliver: departureBoardList(departureBoardWithTs.data!.departures, bgLuminance,
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

  Future<void> _updateDepartureBoard(
      StreamController streamController, int stopId, DateTime? dateTime, double lat, long) async {
    await getDepartureBoard(streamController, stopId, dateTime, departureBoardOptions, null, lat, long);
  }

  void _showJourneyDetailSheet(Departure departure) {
    final StreamController<JourneyDetailWithTrafficSituations> streamController = StreamController();
    Wrapper<JourneyDetail> journeyDetail = Wrapper(null);
    _updateJourneyDetail(streamController, departure, journeyDetail);

    var ctx = widget._mapJourneys.isEmpty ? Scaffold.of(context).context : context;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 2 / (1 + math.sqrt(5)),
            maxChildSize: 1 - MediaQuery.of(ctx).padding.top / MediaQuery.of(ctx).size.height,
            builder: (context, scrollController) {
              return StreamBuilder<JourneyDetailWithTrafficSituations>(
                  stream: streamController.stream,
                  builder: (context, journeyDetailWithTs) {
                    var bgLuminance = Theme.of(context).cardColor.computeLuminance();
                    var appBar = SliverAppBar(
                        title: Row(
                          children: [
                            lineIconFromDeparture(departure, bgLuminance, context),
                            const SizedBox(width: 12),
                            Expanded(child: highlightFirstPart(departure.getDirection(), overflow: TextOverflow.fade))
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
                        ]);
                    if (!journeyDetailWithTs.hasData) {
                      return CustomScrollView(controller: scrollController, slivers: [
                        appBar,
                        SliverFillRemaining(
                            child: journeyDetailWithTs.connectionState == ConnectionState.waiting
                                ? loadingPage()
                                : ErrorPage(() => _updateJourneyDetail(streamController, departure, journeyDetail),
                                    error: journeyDetailWithTs.error))
                      ]);
                    }
                    return CustomScrollView(controller: scrollController, slivers: [
                      appBar,
                      SliverSafeArea(
                          sliver: trafficSituationList(journeyDetailWithTs.data!.importantTs,
                              boldTitle: true, padding: const EdgeInsets.fromLTRB(10, 10, 10, 0)),
                          bottom: false),
                      SliverSafeArea(
                          sliver: journeyDetailList(
                              journeyDetailWithTs.data!.journeyDetail, journeyDetailWithTs.data!.stopNoteIcons,
                              onTap: (context, stop) {
                            Navigator.pop(context);
                            _showDepartureSheet(stopRowFromStop(stop), stop.id, stop.lat, stop.lon,
                                dateTime: stop.getDateTime());
                          }),
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
      _addJourneyDetail(journeyDetail, JourneyPart.fromStopId(departure.stopId, journeyDetail), false);
    } else {
      _getJourneyDetailAndAdd(JourneyDetailRef.fromDeparture(departure), fromStopId: departure.stopId);
    }
  }
}

class MapJourney {
  JourneyDetail? journeyDetail;
  JourneyPart? journeyPart;
  String? geometryRef;
  Iterable<Point>? geometry;
  late bool walk;
  bool focus;
  int? refStopId;
  String? focusJid;

  Future<JourneyDetail?>? futureJourneyDetail;

  MapJourney(
      {JourneyDetailRef? journeyDetailRef,
      this.journeyDetail,
      this.journeyPart,
      this.geometryRef,
      this.geometry,
      bool? walk,
      this.refStopId,
      this.focusJid,
      this.focus = false}) {
    this.walk = walk ?? false;
    if (journeyDetailRef != null) {
      futureJourneyDetail = getJourneyDetailExtra(journeyDetailRef);
    }
  }
}

class JourneyDetailRef {
  late final String ref;
  late final String journeyId;
  late final int? journeyNumber;
  late final String type;
  late final int evaId;
  late final DateTime evaDateTime;

  JourneyDetailRef(this.ref, this.journeyId, this.journeyNumber, this.type, this.evaId, this.evaDateTime);

  JourneyDetailRef.fromDeparture(Departure departure) {
    ref = departure.journeyDetailRef;
    journeyId = departure.journeyId;
    journeyNumber = departure.journeyNumber;
    type = departure.type;
    evaId = departure.stopId;
    evaDateTime = departure.dateTime;
  }

  JourneyDetailRef.fromLeg(Leg leg) {
    ref = leg.journeyDetailRef!;
    journeyId = leg.journeyId!;
    journeyNumber = leg.journeyNumber;
    type = leg.type;
    evaId = leg.origin.id!;
    evaDateTime = leg.origin.dateTime;
  }
}

class JourneyPart {
  late int fromIdx;
  late int toIdx;

  JourneyPart(this.fromIdx, this.toIdx);

  JourneyPart.fromStopId(int stopId, JourneyDetail journeyDetail) {
    fromIdx = journeyDetail.stop.firstWhere((stop) => stop.id == stopId).routeIdx;
    toIdx = journeyDetail.stop.last.routeIdx;
  }
}

class MapFocusable<T> {
  final T item;
  final bool focus;

  MapFocusable(this.item, this.focus);
}

class Vehicle {
  String journeyId;

  VehiclePosition position;
  late LatLng interpolatedPosition;

  double ax = 0, bx = 0, cx = 0, dx = 0;
  double ay = 0, by = 0, cy = 0, dy = 0;

  double t = 0;

  late Map<String, dynamic> properties;

  String type;
  Color bgColor, fgColor;

  StreamController<VehiclePosition> streamController = StreamController.broadcast();

  String _getVehicleIconName(String type) {
    switch (type) {
      case 'VAS':
        return 'train';
      case 'LDT':
      case 'REG':
        return 'railway';
      case 'BOAT':
        return 'boat';
      case 'TRAM':
        return 'tram';
      default:
        return 'bus';
    }
  }

  void updatePosition(VehiclePosition newPosition, bool outdated, {bool teleport = false}) {
    var distance = Geolocator.distanceBetween(
        interpolatedPosition.latitude, interpolatedPosition.longitude, newPosition.lat, newPosition.long);

    if (newPosition.updatedAt.isBefore(position.updatedAt) ||
        position.updatedAt.isAtSameMomentAs(newPosition.updatedAt) &&
            (newPosition.speed > 10 || distance < 1) &&
            !teleport &&
            !outdated) {
      return;
    }

    if (teleport || distance > math.max(position.speed, 10)) {
      interpolatedPosition = LatLng(newPosition.lat, newPosition.long);

      ax = 0;
      bx = newPosition.lat - interpolatedPosition.latitude;
      cx = interpolatedPosition.latitude;

      ay = 0;
      by = newPosition.long - interpolatedPosition.longitude;
      cy = interpolatedPosition.longitude;
    } else {
      if (t > 2) t = 0;

      dx = 2 * ax * t + bx;
      ax = newPosition.lat - interpolatedPosition.latitude - dx;
      bx = dx;
      cx = interpolatedPosition.latitude;

      dy = 2 * ay * t + by;
      ay = newPosition.long - interpolatedPosition.longitude - dy;
      by = dy;
      cy = interpolatedPosition.longitude;
    }

    t = 0;

    position = newPosition;
    streamController.add(newPosition);
  }

  Vehicle(this.journeyId, bool outdated, this.position, this.type, this.bgColor, this.fgColor) {
    interpolatedPosition = LatLng(position.lat, position.long);
    cx = position.lat;
    cy = position.long;

    properties = {
      'icon': _getVehicleIconName(type),
      'bgColor': bgColor.toHexCode(),
      'fgColor': fgColor.toHexCode(),
      'outdated': outdated,
    };
  }
}

class Walk {
  final LatLng start;
  final LatLng end;

  Walk(this.start, this.end);
}
