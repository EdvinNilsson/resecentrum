import 'package:flutter/material.dart';

import 'departure_board_result_widget.dart';
import 'location_searcher.dart';
import 'main.dart';
import 'options_panel.dart';
import 'reseplaneraren.dart';
import 'trip_widget.dart';
import 'utils.dart';

DepartureBoardOptions departureBoardOptions = DepartureBoardOptions();

class DepartureBoardWidget extends StatelessWidget {
  final TextEditingController _stopInput = RichTextEditingController();
  final TextEditingController _directionInput = RichTextEditingController();
  final SegmentedControlController _segmentedControlController = SegmentedControlController(0);
  final DateTimeSelectorController _dateTimeSelectorController = DateTimeSelectorController();

  final LocationFieldController _stopFieldController = LocationFieldController('stop', departureBoardBox);
  final LocationFieldController _directionFieldController = LocationFieldController('direction', departureBoardBox);

  final FocusNode _stopFocusNode = FocusNode();
  final FocusNode _directionFocusNode = FocusNode();

  DepartureBoardWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
                margin: const EdgeInsets.fromLTRB(10, 10, 10, 1),
                child: Column(children: [
                  LocationField(_stopFieldController, _stopInput, 'Ange hållplats',
                      focusNode: _stopFocusNode,
                      onlyStops: true,
                      suffixIcon: IconButton(
                          onPressed: () async {
                            var currentLocation = CurrentLocation(name: 'Närmaste hållplats');
                            currentLocation.onNameChange = () => _stopFieldController.update();
                            _stopFieldController.setLocation(currentLocation);
                            try {
                              await currentLocation.location(onlyStops: true, forceRefresh: true);
                            } on DisplayableError catch (e) {
                              noLocationFound(context, onlyStops: true, description: e.description ?? e.message);
                            }
                            _stopInput.text = currentLocation.getName();
                          },
                          icon: const Icon(Icons.my_location)))
                ])),
            Expanded(
                child: DefaultTabController(
              length: 1,
              child: NestedScrollView(
                headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
                  return <Widget>[
                    SliverToBoxAdapter(
                        child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 10),
                            child: Column(
                              children: [
                                const SizedBox(height: 4),
                                SegmentedControl(const ['Nu', 'Angiven tid'], controller: _segmentedControlController),
                                DateTimeSelector(_segmentedControlController, _dateTimeSelectorController),
                                LocationField(_directionFieldController, _directionInput, 'Ange riktning (valfri)',
                                    focusNode: _directionFocusNode,
                                    onlyStops: true,
                                    suffixIcon: IconButton(
                                        onPressed: _directionFieldController.clearLocation,
                                        icon: const Icon(Icons.clear))),
                                const SizedBox(height: 1),
                                DepartureBoardOptionsPanel(departureBoardOptions),
                              ],
                            ))),
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
                          child: ElevatedButton(
                              onPressed: () {
                                if (!(_stopFieldController.location is StopLocation ||
                                    _stopFieldController.location is CurrentLocation)) {
                                  _stopFieldController.setErrorText('Hållplats saknas');
                                  return;
                                }
                                _stopFieldController.clearError();

                                Navigator.push(context, MaterialPageRoute(builder: (context) {
                                  return DepartureBoardResultWidget(
                                      _stopFieldController.location!,
                                      getDateTimeFromSelector(_dateTimeSelectorController, _segmentedControlController),
                                      departureBoardOptions,
                                      direction: _directionFieldController.location as StopLocation?);
                                }));
                              },
                              child: const Text('Sök')),
                        ),
                        bottom: TabBar(
                          indicatorColor: Theme.of(context).primaryColor,
                          labelColor: Theme.of(context).hintColor,
                          tabs: const [
                            Tab(icon: Text('Favorithållplatser')),
                          ],
                        ),
                      ),
                    )
                  ];
                },
                body: TabBarView(
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    Builder(builder: (BuildContext context) {
                      return CustomScrollView(
                        key: const PageStorageKey(0),
                        slivers: [
                          SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
                          FavoritePlacesList(
                              onlyStops: true,
                              onTap: (location) async {
                                _stopFieldController.setLocation(location);
                                _directionFieldController.clearLocation();
                                await Navigator.push(context, MaterialPageRoute(builder: (context) {
                                  return DepartureBoardResultWidget(
                                      location as StopLocation,
                                      getDateTimeFromSelector(_dateTimeSelectorController, _segmentedControlController),
                                      departureBoardOptions,
                                      direction: null);
                                }));
                              },
                              onLongPress: (location) {
                                if (!_directionFocusNode.hasFocus) {
                                  _stopFieldController.setLocation(location);
                                  FocusScope.of(context).requestFocus(_directionFocusNode);
                                } else {
                                  _directionFieldController.setLocation(location);
                                  FocusScope.of(context).requestFocus(_stopFocusNode);
                                }
                              }),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }
}
