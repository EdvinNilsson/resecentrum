import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:maplibre_gl/mapbox_gl.dart';
import 'package:rxdart/subjects.dart';

import 'departure_board_result_widget.dart';
import 'departure_board_widget.dart';
import 'extensions.dart';
import 'home_widget.dart';
import 'journey_detail_widget.dart';
import 'network/mgate.dart';
import 'network/planera_resa.dart';
import 'network/trafikverket.dart';
import 'network/vehicle_positions.dart';
import 'trip_detail_widget.dart';
import 'utils.dart';

class MapWidget extends StatefulWidget {
  final List<MapJourney> _mapJourneys;
  final List<String> focusStopPoints;

  const MapWidget(this._mapJourneys, {this.focusStopPoints = const [], super.key});

  @override
  State createState() => MapWidgetState();
}

class MapWidgetState extends State<MapWidget> with WidgetsBindingObserver {
  late MaplibreMapController _mapController;

  final List<ServiceJourneyDetails> _journeyDetails = [];
  final Map<String, ServiceJourney> _journeyDetailById = {};
  final List<String> _journeyIds = [];
  final List<TrainPositionRef> _trains = [];
  final List<Vehicle> _vehicles = [];
  final List<MapFocusable<Call>> _stops = [];
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
  Future<TrainPositions?>? _initialTrainPosition;

  StreamSubscription<Iterable<TrainPosition>>? _trainPositionStream;

  final LatLngBounds _mapBounds =
      LatLngBounds(southwest: const LatLng(55.02652, 10.54138), northeast: const LatLng(69.06643, 24.22472));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    var focusJourneyIds =
        widget._mapJourneys.where((j) => j.focusJid != null && j.focusTrainNumber == null).map((j) => j.focusJid!);
    if (focusJourneyIds.isNotEmpty) {
      _initialVehiclePosition = VehiclePositions.getPositions(focusJourneyIds.toList(growable: false));
    }
    var focusTrainRefs = widget._mapJourneys
        .where((j) => j.focusJid != null && j.focusTrainNumber != null)
        .map((j) => TrainPositionRef(j.focusJid!, j.focusTrainNumber!));
    if (focusTrainRefs.isNotEmpty) {
      _initialTrainPosition = Trafikverket.getTrainPositions(focusTrainRefs);
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
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _trainPositionStream?.cancel();
    _ticker?.stop();
    _ticker?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _timer?.isActive == true) {
      _timer?.cancel();
      _trainPositionStream?.cancel();
    } else if (state == AppLifecycleState.resumed && _timer?.isActive == false) {
      _initTimer();
    }
  }

  bool _mapCreated = false;

  void _onMapCreated(MaplibreMapController controller) {
    _mapController = controller;
    _mapController.onFeatureTapped.add(_onFeatureTap);
    _mapCreated = true;
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
        LineLayerProperties(
          lineColor: '#000000',
          lineOpacity: 0.5,
          lineWidth: 4,
          lineDasharray: [
            Expressions.literal,
            !kIsWeb && Platform.isIOS ? [1, 1, 1 / 2] : [1, 1 / 2]
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
          circleStrokeWidth: 1,
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

    await addMapJourneys(widget._mapJourneys);

    var initialPosition = await _initialVehiclePosition;
    var initialTrainPosition = await _initialTrainPosition;
    _initTimer(initialPosition, initialTrainPosition);

    var refStops = widget._mapJourneys
        .map((j) => j.refStopPointGid)
        .whereNotNull()
        .map((stopAreaGid) => _journeyDetails
            .expand((journeyDetails) => journeyDetails.serviceJourneys)
            .expand((serviceJourney) => serviceJourney.callsOnServiceJourney!)
            .firstWhere((stop) => stop.stopPoint.gid == stopAreaGid))
        .map((s) => s.position);

    var vehiclePos = _vehicles.map((v) => v.vehiclePosition.position);

    LatLngBounds? bounds;

    if (refStops.isNotEmpty && vehiclePos.isNotEmpty) {
      bounds = minBounds(
              fromPoints(vehiclePos.followedBy(refStops))?.pad(0.2), _getBounds(extraPoints: vehiclePos)?.pad(0.06))
          ?.minSize(0.005);
    } else {
      bounds = _getBounds()?.pad(0.06).minSize(0.003);
    }

    if (bounds != null && mounted) {
      var padding = MediaQuery.of(context).padding;
      _mapController.animateCamera(CameraUpdate.newLatLngBounds(bounds,
          top: padding.top, right: padding.right, bottom: padding.bottom, left: padding.left));
    }

    _ticker = Ticker(_updateInterpolation);
    _ticker?.start();
  }

  Future<void> addMapJourneys(Iterable<MapJourney> mapJourneys) async {
    var futures = <Future>[];
    for (var mapJourney in mapJourneys) {
      if (mapJourney.serviceJourneyDetails != null) {
        _addJourneyDetail(mapJourney.serviceJourneyDetails!, mapJourney.journeyPart, mapJourney.focus);
      } else if (mapJourney.futureServiceJourneyDetails != null) {
        futures.add(mapJourney.futureServiceJourneyDetails!.then((jd) {
          if (jd != null) _addJourneyDetail(jd, mapJourney.journeyPart, mapJourney.focus);
        }));
      } else if (mapJourney.link != null) {
        _addLink(mapJourney);
      } else if (mapJourney.futureMapJourneys != null) {
        futures.add(mapJourney.futureMapJourneys!.then((mapJourneys) async => await addMapJourneys(mapJourneys)));
      }
    }

    await Future.wait(futures);
  }

  void _initTimer([Iterable<VehiclePosition>? initialPosition, TrainPositions? initialTrainPosition]) {
    _timer = Timer.periodic(const Duration(seconds: 1), _updatePosition);
    _updatePosition(_timer!, initialPosition);
    _updateTrainPosition(initialTrainPosition);
  }

  Future<void> _updateJourneyDetails(
      StreamController streamController, Departure departure, Wrapper<ServiceJourneyDetails> journeyDetails) async {
    try {
      var response = await getJourneyDetails(DepartureDetailsRef.fromDeparture(departure));
      journeyDetails.element = response.serviceJourneyDetails;
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
    if (_updatingNearbyStops || !_mapCreated) return;
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
    var serviceJourney = _journeyDetailById[vehicle.journeyId]!;

    await showModalBottomSheet(
        context: context,
        builder: (context) {
          var bgColor = Theme.of(context).cardColor;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                  title: Row(
                    children: [
                      lineIconFromLine(serviceJourney.line, bgColor, context),
                      const SizedBox(width: 12),
                      Expanded(child: highlightFirstPart(serviceJourney.direction, overflow: TextOverflow.fade))
                    ],
                  ),
                  automaticallyImplyLeading: false),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: StreamBuilder<VehiclePosition>(
                      stream: vehicle.streamController.stream,
                      builder: (context, snapshot) {
                        var vehiclePosition = snapshot.data ?? vehicle.vehiclePosition;
                        var dateFormat =
                            vehiclePosition.updatedAt.difference(DateTime.now()).abs() > const Duration(hours: 12)
                                ? DateFormat.MMMMEEEEd().add_Hms()
                                : DateFormat.Hms();
                        return Column(children: [
                          Text('Senast uppdaterad: ${dateFormat.format(vehiclePosition.updatedAt)}'),
                          if (vehiclePosition.speed != null) Text('Hastighet: ${vehiclePosition.speed!.round()} km/h'),
                        ]);
                      }),
                ),
              ),
            ],
          );
        });
  }

  void _onMapTap(math.Point<double> point, LatLng position, {bool longClick = false}) async {
    if (!longClick) {
      List<math.Point<num>> points =
          await _mapController.toScreenLocationBatch(_stops.map((stop) => stop.item.position));

      var touchRadius = math.pow(48 * devicePixelRatio, 2);

      for (int i = 0; i < _stops.length; i++) {
        if (points[i].squaredDistanceTo(point) < touchRadius) {
          var stop = _stops[i].item;
          DateTime? dateTime = stop.improvedArrivalTimeEstimation;
          _showDepartureSheet(stopRowFromStop(stop), stopAreaFromStopPoint(stop.stopPoint.gid), stop.stopPoint.position,
              dateTime: dateTime);
          return;
        }
      }

      points = await _mapController.toScreenLocationBatch(_stopLocations.map((stop) => stop.position));

      for (int i = 0; i < points.length; i++) {
        if (points[i].squaredDistanceTo(point) < touchRadius) {
          var stopLocation = _stopLocations.elementAt(i);
          _showDepartureSheet(highlightFirstPart(stopLocation.name), stopLocation.gid, stopLocation.position,
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
      var address = await MGate.getLocationNearbyAddress(position);
      if (address == null) return;
      if (_marker != null) _mapController.removeCircle(_marker!);
      _marker = await _mapController.addCircle(CircleOptions(
          geometry: address.position,
          circleColor: Colors.red.toHexCode(),
          circleRadius: 5,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 3));
      await _showAddressSheet(address);
      if (_marker != null) _mapController.removeCircle(_marker!);
    }
  }

  void _addJourneyDetail(ServiceJourneyDetails journeyDetails, JourneyPart? journeyPart, bool focus) {
    _addStops(journeyDetails, journeyPart, focus);
    _addPolylines(journeyDetails, journeyPart);
    _journeyDetails.add(journeyDetails);
    for (var serviceJourney in journeyDetails.serviceJourneys) {
      _journeyDetailById[serviceJourney.gid] = serviceJourney;
      if (serviceJourney.isTrain) {
        _trains.add(TrainPositionRef(serviceJourney.gid, serviceJourney.line.trainNumber!));
      } else {
        _journeyIds.add(serviceJourney.gid);
      }
    }
  }

  LatLngBounds? _getBounds({Iterable<LatLng>? extraPoints}) {
    Iterable<LatLng> points;
    if (widget._mapJourneys.any((mapJourney) => mapJourney.focus) || widget.focusStopPoints.isNotEmpty) {
      var focusStops = widget.focusStopPoints.map((stopPointGid) =>
          _journeyDetails.expand((jd) => jd.allCalls).firstWhere((stop) => stop.stopPoint.gid == stopPointGid));

      var allFocusedStops = _stops.where((stop) => stop.focus).map((stop) => stop.item).followedBy(focusStops);

      points = allFocusedStops
          .map((stop) => stop.position)
          .followedBy(_walks.where((walk) => walk.focus).map((walk) => [walk.item.start, walk.item.end]).flattened);
    } else {
      points = _stops
          .map((stop) => stop.item.position)
          .followedBy(_walks.map((walk) => [walk.item.start, walk.item.end]).flattened);
    }
    return fromPoints(points.followedBy(extraPoints ?? []));
  }

  Future<void> _getJourneyDetailAndAdd(DepartureDetailsRef ref,
      {JourneyPart? journeyPart, bool focus = false, String? fromStopPointGid}) async {
    var journeyDetails = await getJourneyDetailExtra(ref);
    if (journeyDetails == null) return;
    if (fromStopPointGid != null) journeyPart = JourneyPart.fromStopPointGid(fromStopPointGid, journeyDetails);
    _addJourneyDetail(journeyDetails, journeyPart, focus);
  }

  void _addLink(MapJourney mapJourney) async {
    var linkCoordinates = mapJourney.link!.linkCoordinates;

    _walksGeoJson['features'].add({
      'type': 'Feature',
      'geometry': {
        'type': 'LineString',
        'coordinates': linkCoordinates.map((point) => point.toGeoJsonCoordinates()).toList(growable: false),
      }
    });

    _mapController.setGeoJsonSource('walks', _walksGeoJson);
    var start = linkCoordinates.first, end = linkCoordinates.last;
    _walks.add(MapFocusable(Walk(start, end), mapJourney.focus));
  }

  void _addPolylines(ServiceJourneyDetails journeyDetails, JourneyPart? journeyPart) async {
    for (var serviceJourney in journeyDetails.serviceJourneys) {
      var points =
          journeyPart != null ? getJourneyPart(serviceJourney, journeyPart) : serviceJourney.serviceJourneyCoordinates!;

      _addLine(points, serviceJourney.line.foregroundColor, serviceJourney.line.backgroundColor);
    }
  }

  List<LatLng> getJourneyPart(ServiceJourney serviceJourney, JourneyPart journeyPart) {
    if (journeyPart.toIdx <= journeyPart.fromIdx) return [];

    var firstStop = serviceJourney.callsOnServiceJourney!.firstWhereOrNull((stop) => stop.index == journeyPart.fromIdx);
    var lastStop = serviceJourney.callsOnServiceJourney!.lastWhereOrNull((stop) => stop.index == journeyPart.toIdx);

    bool draw = firstStop == null && journeyPart.fromIdx <= serviceJourney.callsOnServiceJourney!.first.index;
    List<LatLng> line = [];
    for (var point in serviceJourney.serviceJourneyCoordinates!) {
      if (point == firstStop?.position) {
        if (draw) line.clear();
        draw = true;
      }

      if (draw) line.add(point);

      if (draw && point == lastStop?.position) break;
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

  void _addStops(ServiceJourneyDetails journeyDetails, JourneyPart? journeyPart, bool focus) {
    for (var serviceJourney in journeyDetails.serviceJourneys) {
      var calls = journeyPart == null
          ? serviceJourney.callsOnServiceJourney!
          : serviceJourney.callsOnServiceJourney!
              .where((stop) => stop.index >= journeyPart.fromIdx && stop.index <= journeyPart.toIdx);

      for (var call in calls) {
        _lineStopsGeoJson['features'].add({
          'type': 'Feature',
          'id': call.stopPoint.gid,
          'properties': {
            'fgColor': serviceJourney.line.foregroundColor.toHexCode(),
            'bgColor': serviceJourney.line.backgroundColor.toHexCode(),
          },
          'geometry': {
            'type': 'Point',
            'coordinates': call.position.toGeoJsonCoordinates(),
          }
        });
        _stops.add(MapFocusable(call, focus));
      }
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

  Json _getVehicleGeoJson(Duration deltaTime) {
    return {
      'type': 'FeatureCollection',
      'features': _getVehicleGeoJsonFeatures(deltaTime).toList(growable: false),
    };
  }

  Iterable<Map<String, dynamic>> _getVehicleGeoJsonFeatures(Duration deltaTime) {
    double dt = deltaTime.inMicroseconds / (Duration.microsecondsPerSecond * 2);
    return _vehicles.map((vehicle) {
      if (vehicle.useInterpolation) {
        vehicle.t += dt;

        double x = vehicle.t;

        if (vehicle.t > 1) {
          if (vehicle.vehiclePosition.speedOrZero < 10 || vehicle.t > 2) {
            x = 1;
          } else {
            x = (vehicle.t - 1) / 2 + 1;
          }
        }

        vehicle.interpolatedPosition = LatLng(
            _quadratic(vehicle.ax, vehicle.bx, vehicle.cx, x), _quadratic(vehicle.ay, vehicle.by, vehicle.cy, x));
      }

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
    if (vehiclePosition is TrainPosition) return !vehiclePosition.active;
    if (vehiclePosition is! LiveVehiclePosition) return false;

    if (!vehiclePosition.dataStillRelevant) return true;
    Duration diff = DateTime.now().difference(vehiclePosition.updatedAt);
    bool still = vehiclePosition.atStop || vehiclePosition.speedOrZero < 10;
    return diff > Duration(minutes: still ? 5 : 1);
  }

  Future<void> _updatePosition(Timer _, [Iterable<VehiclePosition>? initialPosition]) async {
    if (_journeyDetails.isEmpty || (_journeyIds.isEmpty && initialPosition == null)) return;

    var response = initialPosition ?? await VehiclePositions.getPositions(_journeyIds);

    if (!mounted) return;

    if (response == null) {
      for (var vehicle in _vehicles) {
        if (vehicle.transportMode == TransportMode.train) continue;
        vehicle.properties['outdated'] = true;
        vehicle.updatePosition(vehicle.vehiclePosition, true, teleport: true);
      }
    } else {
      for (var vehiclePosition in response) {
        var vehicle = _getVehicle(vehiclePosition);
        bool outdated = _isOutdated(vehiclePosition);

        if (vehicle != null) {
          vehicle.properties['outdated'] = outdated;
          vehicle.updatePosition(vehiclePosition, outdated, teleport: vehicle.transportMode == TransportMode.train);
        } else {
          var journeyDetails = _journeyDetailById[vehiclePosition.journeyId]!;

          _vehicles.add(Vehicle(vehiclePosition.journeyId, outdated, vehiclePosition, journeyDetails.line.transportMode,
              journeyDetails.line.backgroundColor, journeyDetails.line.foregroundColor,
              useInterpolation: !journeyDetails.isTrain));
        }
      }
      await _mapController.setGeoJsonSource('vehicles', _getVehicleGeoJson(Duration.zero));
    }
  }

  Future<void> _updateTrainPosition([TrainPositions? initialPosition]) async {
    if (_trains.isEmpty) return;

    var response = initialPosition ?? await Trafikverket.getTrainPositions(_trains);

    if (_timer == null || response == null || !mounted) return;

    _updatePosition(_timer!, response.initial);

    _trainPositionStream = (await response.getStream())?.listen((event) {
      if (_timer == null || !mounted) return;
      _updatePosition(_timer!, event);
    });
  }

  void _refreshTrainPositionStream() {
    _trainPositionStream?.cancel();
    _updateTrainPosition();
  }

  Circle? _marker;

  final Set<StopLocation> _stopLocations = {};

  Future<void> _updateNearbyStops() async {
    var coord = _mapController.cameraPosition?.target;
    if (coord == null) return;

    Set<StopLocation>? nearbyStops =
        (await PlaneraResa.nearbyStops(coord, limit: 1000, radiusInMeters: 3000).suppress())
            ?.where((stop) => stop.isStopArea)
            .toSet();
    if (nearbyStops == null || !mounted) return;

    Set<StopLocation> add = nearbyStops.difference(_stopLocations);
    _stopLocations.addAll(add);

    for (var stop in add) {
      _stopsGeoJson['features'].add({
        'type': 'Feature',
        'id': stop.gid,
        'geometry': {
          'type': 'Point',
          'coordinates': stop.position.toGeoJsonCoordinates(),
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

  void _showDepartureSheet(Widget header, String stopAreaGid, LatLng position,
      {DateTime? dateTime, Widget? extraSliver}) {
    final StreamController<Iterable<Departure>> streamController = StreamController();
    final BehaviorSubject<Iterable<TS>> trafficSituationSubject = BehaviorSubject();
    final DepartureBoardState state = DepartureBoardState();
    _updateDepartureBoard(streamController, stopAreaGid, dateTime, position, state, trafficSituationSubject);

    if (!mounted) return;
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
                return StreamBuilder<Iterable<Departure>>(
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
                                        () => _updateDepartureBoard(streamController, stopAreaGid, dateTime, position,
                                            state, trafficSituationSubject),
                                        error: departureBoardWithTs.error))
                          ].insertIf(extraSliver != null, 1, extraSliver));
                    }
                    var bgColor = Theme.of(context).cardColor;
                    return CustomScrollView(
                        controller: scrollController,
                        slivers: [
                          appBar,
                          SliverSafeArea(
                            sliver:
                                departureBoardList(departureBoardWithTs.data!, bgColor, onTap: (context, departure) {
                              Navigator.pop(context);
                              _showJourneyDetailSheet(departure);
                            }, onLongPress: (context, departure) {
                              Navigator.pop(context);
                              _showDepartureOnMap(departure, null);
                            }),
                            bottom: false,
                          ),
                          trafficSituationWidget(trafficSituationSubject.stream)
                        ].insertIf(extraSliver != null, 1, extraSliver));
                  },
                );
              });
        });
  }

  Future<void> _updateDepartureBoard(StreamController streamController, String stopAreaGid, DateTime? dateTime,
      LatLng position, DepartureBoardState state, BehaviorSubject tsSubject) async {
    await getDepartureBoard(streamController, stopAreaGid, dateTime, departureBoardOptions, null, position, state,
        tsSubject: tsSubject);
  }

  void _showJourneyDetailSheet(Departure departure) {
    final StreamController<ServiceJourneyDetailsWithTrafficSituations> streamController = StreamController();
    Wrapper<ServiceJourneyDetails> journeyDetails = Wrapper(null);
    _updateJourneyDetails(streamController, departure, journeyDetails);

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
              return StreamBuilder<ServiceJourneyDetailsWithTrafficSituations>(
                  stream: streamController.stream,
                  builder: (context, journeyDetailsWithTs) {
                    var bgColor = Theme.of(context).cardColor;
                    var appBar = SliverAppBar(
                        title: Row(
                          children: [
                            lineIconFromLine(departure.serviceJourney.line, bgColor, context, shortTrainName: false),
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
                                _showDepartureOnMap(departure, journeyDetails.element, showAllStops: true);
                              },
                              icon: const Icon(Icons.map))
                        ]);
                    if (!journeyDetailsWithTs.hasData) {
                      return CustomScrollView(controller: scrollController, slivers: [
                        appBar,
                        SliverFillRemaining(
                            child: journeyDetailsWithTs.connectionState == ConnectionState.waiting
                                ? loadingPage()
                                : ErrorPage(() => _updateJourneyDetails(streamController, departure, journeyDetails),
                                    error: journeyDetailsWithTs.error))
                      ]);
                    }
                    return CustomScrollView(controller: scrollController, slivers: [
                      appBar,
                      SliverSafeArea(
                          sliver: trafficSituationList(journeyDetailsWithTs.data!.importantTs,
                              boldTitle: true, padding: const EdgeInsets.fromLTRB(10, 10, 10, 0)),
                          bottom: false),
                      SliverSafeArea(
                          sliver: journeyDetailList(journeyDetailsWithTs.data!.serviceJourneyDetails,
                              journeyDetailsWithTs.data!.stopNoteIcons, onTap: (context, stop) {
                            Navigator.pop(context);
                            _showDepartureSheet(stopRowFromStop(stop), stopAreaFromStopPoint(stop.stopPoint.gid),
                                stop.stopPoint.position,
                                dateTime: stop.improvedArrivalTimeEstimation);
                          }, onLongPress: (context, stop) {
                            _showDepartureOnMap(departure, journeyDetailsWithTs.data!.serviceJourneyDetails,
                                showAllStops: true);
                            _mapController.animateCamera(
                                CameraUpdate.newCameraPosition(CameraPosition(target: stop.position, zoom: 16)));
                            Navigator.pop(context);
                          }),
                          bottom: false),
                      SliverSafeArea(
                        sliver: trafficSituationList(journeyDetailsWithTs.data!.normalTs,
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10)),
                      ),
                    ]);
                  });
            });
      },
    );
  }

  Future<void> _showDepartureOnMap(Departure departure, ServiceJourneyDetails? serviceJourneyDetails,
      {bool showAllStops = false}) async {
    if (_journeyDetailById.containsKey(departure.serviceJourney.gid)) return;
    if (serviceJourneyDetails != null) {
      _addJourneyDetail(serviceJourneyDetails,
          showAllStops ? null : JourneyPart.fromStopPointGid(departure.stopPoint.gid, serviceJourneyDetails), false);
    } else {
      await _getJourneyDetailAndAdd(DepartureDetailsRef.fromDeparture(departure),
          fromStopPointGid: showAllStops ? null : departure.stopPoint.gid);
    }
    _refreshTrainPositionStream();
  }
}

class MapJourney {
  ServiceJourneyDetails? serviceJourneyDetails;
  JourneyPart? journeyPart;

  Link? link;

  bool focus;

  String? refStopPointGid;
  String? focusJid;
  int? focusTrainNumber;

  Future<ServiceJourneyDetails?>? futureServiceJourneyDetails;
  Future<Iterable<MapJourney>>? futureMapJourneys;

  MapJourney(
      {DetailsRef? journeyDetailsRef,
      String? journeyDetailsReference,
      this.serviceJourneyDetails,
      this.journeyPart,
      this.link,
      this.refStopPointGid,
      this.focusJid,
      this.focusTrainNumber,
      this.focus = false}) {
    if (journeyDetailsRef != null) {
      futureServiceJourneyDetails = getJourneyDetailExtra(journeyDetailsRef);
    }
    if (journeyDetailsReference != null) {
      futureMapJourneys = PlaneraResa.journeyDetails(journeyDetailsReference, {
        JourneyDetailsIncludeType.serviceJourneyCalls,
        JourneyDetailsIncludeType.serviceJourneyCoordinates,
        JourneyDetailsIncludeType.links,
      }).then((journeyDetails) => TripDetailsWidget.mapJourneys(journeyDetails));
    }
  }
}

class JourneyPart {
  late int fromIdx;
  late int toIdx;

  JourneyPart(this.fromIdx, this.toIdx);

  JourneyPart.fromStopPointGid(String stopPointGid, ServiceJourneyDetails journeyDetails) {
    fromIdx = journeyDetails.allCalls.firstWhere((stop) => stop.stopPoint.gid == stopPointGid).index;
    toIdx = journeyDetails.lastCall!.index;
  }
}

class MapFocusable<T> {
  final T item;
  final bool focus;

  MapFocusable(this.item, this.focus);
}

class Vehicle {
  String journeyId;

  VehiclePosition vehiclePosition;
  late LatLng interpolatedPosition;

  double ax = 0, bx = 0, cx = 0, dx = 0;
  double ay = 0, by = 0, cy = 0, dy = 0;

  double t = 0;

  late Json properties;

  TransportMode transportMode;
  Color bgColor, fgColor;

  bool useInterpolation;

  StreamController<VehiclePosition> streamController = StreamController.broadcast();

  String _getVehicleIconName(TransportMode transportMode) {
    return switch (transportMode) {
      TransportMode.tram => 'tram',
      TransportMode.ferry => 'boat',
      TransportMode.train => 'railway',
      _ => 'bus',
    };
  }

  void updatePosition(VehiclePosition newPosition, bool outdated, {bool teleport = false}) {
    var distance = distanceBetween(interpolatedPosition, newPosition.position);

    if (newPosition.updatedAt.isBefore(vehiclePosition.updatedAt) ||
        vehiclePosition.updatedAt.isAtSameMomentAs(newPosition.updatedAt) &&
            (newPosition.speedOrZero > 10 || distance < 1) &&
            !teleport &&
            !outdated) {
      return;
    }

    if (teleport || distance > math.max(vehiclePosition.speedOrZero, 10)) {
      interpolatedPosition = newPosition.position;

      ax = 0;
      bx = newPosition.position.latitude - interpolatedPosition.latitude;
      cx = interpolatedPosition.latitude;

      ay = 0;
      by = newPosition.position.longitude - interpolatedPosition.longitude;
      cy = interpolatedPosition.longitude;
    } else {
      if (t > 2) t = 0;

      dx = 2 * ax * t + bx;
      ax = newPosition.position.latitude - interpolatedPosition.latitude - dx;
      bx = dx;
      cx = interpolatedPosition.latitude;

      dy = 2 * ay * t + by;
      ay = newPosition.position.longitude - interpolatedPosition.longitude - dy;
      by = dy;
      cy = interpolatedPosition.longitude;
    }

    t = 0;

    vehiclePosition = newPosition;
    streamController.add(newPosition);
  }

  Vehicle(this.journeyId, bool outdated, this.vehiclePosition, this.transportMode, this.bgColor, this.fgColor,
      {this.useInterpolation = true}) {
    interpolatedPosition = vehiclePosition.position;
    cx = vehiclePosition.position.latitude;
    cy = vehiclePosition.position.longitude;

    properties = {
      'icon': _getVehicleIconName(transportMode),
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
