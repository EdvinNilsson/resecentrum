import 'package:flutter/material.dart';

import 'extensions.dart';
import 'favorites.dart';
import 'location_searcher.dart';
import 'main.dart';
import 'options_panel.dart';
import 'reseplaneraren.dart';
import 'trip_result_widget.dart';
import 'utils.dart';

class TripWidget extends StatelessWidget {
  final TextEditingController _fromInput = RichTextEditingController();
  final TextEditingController _toInput = RichTextEditingController();
  final SegmentedControlController _segmentedControlController = SegmentedControlController(0);
  final LocationFieldController fromFieldController = LocationFieldController('from', tripBox);
  final LocationFieldController toFieldController = LocationFieldController('to', tripBox);
  final DateTimeSelectorController _dateTimeSelectorController = DateTimeSelectorController();

  final FocusNode _fromFocusNode = FocusNode();
  final FocusNode _toFocusNode = FocusNode();

  final TripOptions _tripOptions = TripOptions();

  final GlobalKey<_TripHistoryListState> _tripHistoryKey = GlobalKey();
  final GlobalKey<_FavoritePlacesListState> _favoritePlacesKey = GlobalKey();

  TripWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
                margin: const EdgeInsets.fromLTRB(10, 10, 10, 1),
                child: Column(children: [
                  LocationField(fromFieldController, _fromInput, 'Från',
                      focusNode: _fromFocusNode,
                      suffixIcon: IconButton(
                          onPressed: () async {
                            var currentLocation = CurrentLocation();

                            currentLocation.onNameChange = () {
                              fromFieldController.update();
                              toFieldController.update();
                            };

                            fromFieldController.setLocation(currentLocation);

                            await currentLocation.location(forceRefresh: true).catchError((e) {
                              if (e is DisplayableError) {
                                noLocationFound(context, description: e.description ?? e.message);
                              } else {
                                noLocationFound(context);
                              }
                              return null;
                            });
                            _fromInput.text = currentLocation.getName();
                          },
                          icon: const Icon(Icons.my_location))),
                  LocationField(toFieldController, _toInput, 'Till',
                      focusNode: _toFocusNode,
                      suffixIcon: IconButton(
                          onPressed: () {
                            var temp = fromFieldController.location;
                            fromFieldController.setLocation(toFieldController.location);
                            toFieldController.setLocation(temp);
                          },
                          icon: const Icon(Icons.swap_vert))),
                ])),
            Expanded(
              child: DefaultTabController(
                initialIndex: _index,
                length: 2,
                child: NestedScrollView(
                  headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
                    return <Widget>[
                      SliverToBoxAdapter(
                        child: Material(
                          child: Container(
                            margin: const EdgeInsets.fromLTRB(10, 5, 10, 0),
                            child: Column(
                              children: [
                                SegmentedControl(const ['Nu', 'Avgång', 'Ankomst'],
                                    controller: _segmentedControlController),
                                DateTimeSelector(_segmentedControlController, _dateTimeSelectorController),
                                TripOptionsPanel(_tripOptions),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SliverOverlapAbsorber(
                        handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
                        sliver: SliverAppBar(
                          backgroundColor: Theme.of(context).canvasColor,
                          pinned: true,
                          titleSpacing: 10,
                          forceElevated: true,
                          automaticallyImplyLeading: false,
                          title: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(onPressed: () => _onSearch(context), child: const Text('Sök')),
                          ),
                          bottom: TabBar(
                            indicatorColor: Theme.of(context).primaryColor,
                            labelColor: Theme.of(context).hintColor,
                            tabs: const [
                              Tab(icon: Text('Resvägar')),
                              Tab(icon: Text('Favoritplatser')),
                            ],
                          ),
                        ),
                      )
                    ];
                  },
                  body: TabBarView(
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      Builder(
                        builder: (BuildContext context) {
                          _index = 0;
                          return CustomScrollView(
                            key: const PageStorageKey(0),
                            slivers: [
                              SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
                              TripHistoryList((trip) {
                                fromFieldController.setLocation(trip.from);
                                toFieldController.setLocation(trip.to);
                                _tripOptions.viaFieldController.setLocation(trip.via);
                                _onSearch(context);
                              }, key: _tripHistoryKey)
                            ],
                          );
                        },
                      ),
                      Builder(builder: (BuildContext context) {
                        _index = 1;
                        return CustomScrollView(
                          key: const PageStorageKey(1),
                          slivers: [
                            SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
                            FavoritePlacesList(
                                onTap: (location) {
                                  if (!_toFocusNode.hasFocus) {
                                    fromFieldController.setLocation(location);
                                    FocusScope.of(context).requestFocus(_toFocusNode);
                                  } else {
                                    toFieldController.setLocation(location);
                                    FocusScope.of(context).requestFocus(_fromFocusNode);
                                  }
                                },
                                onLongPress: (location) {
                                  if (_toFocusNode.hasFocus) {
                                    fromFieldController.setLocation(location);
                                  } else {
                                    toFieldController.setLocation(location);
                                  }
                                },
                                key: _favoritePlacesKey),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onSearch(BuildContext context) async {
    if (fromFieldController.location == null || toFieldController.location == null) {
      if (fromFieldController.location == null) fromFieldController.setErrorText('Saknar startplats');
      if (toFieldController.location == null) toFieldController.setErrorText('Saknar destination');
      return;
    }
    addTripHistory(
        fromFieldController.location!, toFieldController.location!, _tripOptions.viaFieldController.location);
    await Navigator.push(context, MaterialPageRoute(builder: (context) {
      return TripResultWidget(
          fromFieldController.location!,
          toFieldController.location!,
          getDateTimeFromSelector(_dateTimeSelectorController, _segmentedControlController),
          _segmentedControlController.value == 2 ? true : null,
          _tripOptions);
    }));
    _tripHistoryKey.currentState?._update();
  }

  int get _index => tripBox.get('tab', defaultValue: 0);

  set _index(int value) => tripBox.put('tab', value);
}

class FavoritePlacesList extends StatefulWidget {
  final void Function(Location) onTap;
  final void Function(Location)? onLongPress;
  final bool onlyStops;

  const FavoritePlacesList({required this.onTap, this.onLongPress, this.onlyStops = false, Key? key}) : super(key: key);

  @override
  State<FavoritePlacesList> createState() => _FavoritePlacesListState();
}

class _FavoritePlacesListState extends State<FavoritePlacesList> {
  void _update() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    onFavoriteChange = _update;
    var favoriteLocations =
        (widget.onlyStops ? allFavoriteLocations.whereType<StopLocation>() : allFavoriteLocations).toList();
    if (favoriteLocations.isEmpty) {
      return noDataSliver('Här visas ${widget.onlyStops ? 'favorithållplatser' : 'favoritplatser'}');
    }
    return SeparatedSliverList(
      itemCount: favoriteLocations.length,
      itemBuilder: (context, i) {
        var location = favoriteLocations.elementAt(i);
        return SuggestionWidget(location, () => widget.onTap(location),
            onLongPress: widget.onLongPress != null ? () => widget.onLongPress!(location) : null,
            callOnFavoriteChange: false);
      },
      separatorBuilder: (context, index) {
        return const Divider(height: 1);
      },
    );
  }
}

class TripHistoryList extends StatefulWidget {
  final void Function(TripHistory) _onTap;

  const TripHistoryList(this._onTap, {Key? key}) : super(key: key);

  @override
  State<TripHistoryList> createState() => _TripHistoryListState();
}

class _TripHistoryListState extends State<TripHistoryList> {
  void _update() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return tripHistory.isEmpty
        ? noDataSliver('Här visas tidigare resvägar samt dina favoritresvägar')
        : SliverReorderableList(
            itemBuilder: (context, i) {
              var trip = tripHistory.elementAt(i);
              return Dismissible(
                key: ValueKey(trip.hashCode),
                background: Container(
                    alignment: Alignment.centerRight,
                    color: Colors.red,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 18),
                      child: Icon(Icons.delete, color: Colors.white),
                    )),
                direction: DismissDirection.endToStart,
                onDismissed: (direction) {
                  setState(() {
                    removeTripHistory(trip);
                  });
                  ScaffoldMessenger.of(context).clearSnackBars();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(_deleteTripMessage(trip)),
                      action: SnackBarAction(
                          label: 'ÅNGRA',
                          onPressed: () {
                            setState(() {
                              undoTripDeletion(i, trip);
                            });
                          })));
                },
                child: TripHistoryWidget(trip, i, () => widget._onTap(trip)),
              );
            },
            onReorder: reorderTripHistory,
            itemCount: tripHistory.length);
  }

  String _deleteTripMessage(TripHistory trip) {
    String via = trip.via != null ? ' via ${trip.via!.name.firstPart()}' : '';
    return 'Resväg mellan ${trip.from.name.firstPart()} och ${trip.to.name.firstPart()}$via togs bort';
  }
}

class TripHistoryWidget extends StatefulWidget {
  final TripHistory _trip;
  final GestureTapCallback? _onTap;
  final int _index;

  TripHistoryWidget(this._trip, this._index, this._onTap) : super(key: ValueKey(_trip.hashCode));

  @override
  State<TripHistoryWidget> createState() => _TripHistoryWidgetState();
}

class _TripHistoryWidgetState extends State<TripHistoryWidget> {
  @override
  Widget build(BuildContext context) {
    bool favorite = isTripFavorite(widget._trip);
    return Material(
      elevation: 1,
      child: InkWell(
        onTap: widget._onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.route, color: Theme.of(context).hintColor),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  highlightFirstPart(widget._trip.from.name),
                  highlightFirstPart(widget._trip.to.name),
                ].addIf(widget._trip.via != null,
                    Text('via ${widget._trip.via?.name}', style: TextStyle(color: Theme.of(context).hintColor))),
              )),
              IconButton(
                  icon: Icon(favorite ? Icons.star : Icons.star_border,
                      color: favorite ? Theme.of(context).primaryColor : Theme.of(context).hintColor),
                  onPressed: () {
                    setState(() {
                      setTripFavorite(widget._trip, !favorite);
                    });
                  }),
              ReorderableDragStartListener(
                  index: widget._index,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Icon(Icons.drag_handle, color: Theme.of(context).hintColor),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
