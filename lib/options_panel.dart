import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import 'extensions.dart';
import 'location_searcher.dart';
import 'main.dart';
import 'network/planera_resa.dart';
import 'utils.dart';

abstract class BoxOption {
  late Box box;
}

abstract class TripOptions
    with ChangeMarginGetter, ServicesGetter, IncludeNearbyStopsGetter, ViaGetter, WalkDistanceGetter, OptionsSummary {}

abstract class DepartureBoardOptions with IncludeArrivalGetter, OptionsSummary {}

abstract mixin class ChangeMarginGetter {
  int? get changeMarginMinutes;
}

abstract mixin class ServicesGetter {
  List<bool> get services;
}

abstract mixin class IncludeNearbyStopsGetter {
  bool get includeNearbyStops;
}

abstract mixin class ViaGetter {
  StopLocation? get via;
}

abstract mixin class IncludeArrivalGetter {
  bool get includeArrivals;
}

abstract mixin class WalkDistanceGetter {
  int? get maxWalkDistance;
}

abstract mixin class OptionsSummary {
  String? get summary;
}

class BoxTripOptions extends BoxOption
    with ChangeMarginOption, ServicesOption, IncludeNearbyStopsOption, WalkDistanceOption, TripOptionsSummary
    implements TripOptions {
  BoxTripOptions() {
    box = tripBox;
  }

  LocationFieldController viaFieldController = LocationFieldController('via', tripBox);
  final TextEditingController viaInput = RichTextEditingController();

  @override
  StopLocation? get via => viaFieldController.location as StopLocation?;
}

class ParamTripOptions extends TripOptions with TripOptionsSummary {
  Map<String, String> params;

  ParamTripOptions(this.params);

  @override
  int? get changeMarginMinutes => parseInt(params['changeMargin']);

  @override
  List<bool> get services =>
      params['services']?.split('').map((s) => s == '1').toList(growable: false) ??
      List.filled(serviceButtons.length, true);

  @override
  StopLocation? get via => parseLocation(params, 'via') as StopLocation?;

  @override
  bool get includeNearbyStops => params['includeNearbyStops'] != 'false';

  @override
  int? get maxWalkDistance => parseInt(params['maxWalkDistance']);
}

mixin TripOptionsSummary implements TripOptions {
  @override
  String? get summary {
    List<String> changes = [];

    if (via != null) changes.add('Via ${via!.name.firstPart()}');

    if (changeMarginMinutes == 2) {
      changes.add('Kort bytesmarginal (2 min)');
    } else if (changeMarginMinutes != null) {
      var durationString = _TripOptionsPanelState.customChangeMarginDurationString(changeMarginMinutes!);
      changes.add('Bytesmarginal ($durationString)');
    }

    if (!services.all()) changes.add('Färdmedelsfilter');

    if (!includeNearbyStops) changes.add('Gå inte till närliggande hållplatser');

    if (maxWalkDistance != null && includeNearbyStops) changes.add('Gå max ${getDistanceString(maxWalkDistance!)}');

    return changes.isNotEmpty ? changes.join(', ') : null;
  }
}

class BoxDepartureBoardOptions extends BoxOption
    with IncludeArrivalOption, ServicesOption, DepartureBoardOptionsSummary
    implements DepartureBoardOptions {
  BoxDepartureBoardOptions() {
    box = departureBoardBox;
  }
}

class ParamDepartureBoardOptions extends DepartureBoardOptions with DepartureBoardOptionsSummary {
  Map<String, String> params;

  ParamDepartureBoardOptions(this.params);

  @override
  bool get includeArrivals => params['includeArrivals'] == 'true';
}

mixin DepartureBoardOptionsSummary implements DepartureBoardOptions {
  @override
  String? get summary {
    List<String> changes = [];
    if (includeArrivals) changes.add('Inkluderar ankomster');
    return changes.isNotEmpty ? changes.join(', ') : null;
  }
}

mixin IncludeArrivalOption on BoxOption implements IncludeArrivalGetter {
  @override
  bool get includeArrivals => box.get('includeArrivals', defaultValue: false);

  set includeArrivals(bool value) => box.put('includeArrivals', value);
}

mixin ServicesOption on BoxOption implements ServicesGetter {
  @override
  List<bool> get services => box.get('toggleVehicle', defaultValue: List.filled(serviceButtons.length, true));

  void update(List<bool> value) => box.put('toggleVehicle', value);
}

class ServiceButtons extends StatefulWidget {
  final ServicesOption servicesOption;

  const ServiceButtons(this.servicesOption, {super.key});

  @override
  State<ServiceButtons> createState() => _ServiceButtonsState();
}

class _ServiceButtonsState extends State<ServiceButtons> {
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          width: constraints.maxWidth,
          child: SegmentedButton(
            showSelectedIcon: false,
            multiSelectionEnabled: true,
            emptySelectionAllowed: true,
            style: ButtonStyle(
                padding: WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 12, horizontal: 4)),
                shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
            onSelectionChanged: (set) {
              setState(() {
                var list = List<bool>.generate(serviceButtons.length, (index) => set.contains(index));
                widget.servicesOption.update(list);
              });
            },
            segments: serviceButtons
                .mapIndexed((index, value) => ButtonSegment(
                    value: index,
                    label: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(value.icon, size: 24),
                        Text(value.name, textAlign: TextAlign.center, textScaler: const TextScaler.linear(1)),
                      ],
                    )))
                .toList(growable: false),
            selected:
                Set.from(Iterable.generate(serviceButtons.length).where((i) => widget.servicesOption.services[i])),
          ),
        ),
      );
}

mixin ChangeMarginOption on BoxOption implements ChangeMarginGetter {
  ChangeMargin get changeMarginDropdownValue =>
      ChangeMargin.values[box.get('changeMargin', defaultValue: ChangeMargin.normal.index)];

  set changeMarginDropdownValue(ChangeMargin value) => box.put('changeMargin', value.index);

  @override
  int? get changeMarginMinutes {
    if (changeMarginDropdownValue == ChangeMargin.custom) return box.get('changeMarginMinutes');
    return changeMarginDropdownValue == ChangeMargin.short ? 2 : null;
  }

  set changeMarginMinutes(int? value) => box.put('changeMarginMinutes', value);
}

mixin IncludeNearbyStopsOption on BoxOption implements IncludeNearbyStopsGetter {
  @override
  bool get includeNearbyStops => box.get('includeNearbyStops', defaultValue: true);

  set includeNearbyStops(bool value) => box.put('includeNearbyStops', value);
}

mixin WalkDistanceOption on BoxOption implements WalkDistanceGetter {
  WalkDistance get walkDistanceDropdownValue =>
      WalkDistance.values[box.get('maxWalkDistance', defaultValue: WalkDistance.max2km.index)];

  set walkDistanceDropdownValue(WalkDistance value) => box.put('maxWalkDistance', value.index);

  @override
  int? get maxWalkDistance {
    if (walkDistanceDropdownValue == WalkDistance.custom) return box.get('maxWalkDistanceMeters');
    return walkDistanceDropdownValue.meters;
  }

  set maxWalkDistance(int? value) => box.put('maxWalkDistanceMeters', value);
}

enum WalkDistance { max500m, max1km, max2km, max5km, custom }

extension WalkDistanceExt on WalkDistance {
  int? get meters => switch (this) {
        WalkDistance.max500m => 500,
        WalkDistance.max1km => 1000,
        WalkDistance.max2km => null,
        WalkDistance.max5km => 5000,
        WalkDistance.custom => null
      };
}

enum ChangeMargin { short, normal, custom }

class Service {
  final IconData icon;
  final String name;

  const Service(this.icon, this.name);
}

List<Service> serviceButtons = const [
  Service(Icons.tram, 'Spårvagn'),
  Service(Icons.directions_bus, 'Buss'),
  Service(Icons.train, 'Västtåg'),
  Service(Icons.directions_railway, 'Övriga tåg'),
  Service(Icons.directions_boat, 'Båt'),
];

class TripOptionsPanel extends StatefulWidget implements OptionsPanel {
  final BoxTripOptions tripOptions;

  const TripOptionsPanel(this.tripOptions, {super.key});

  @override
  State<TripOptionsPanel> createState() => _TripOptionsPanelState();

  @override
  String? get summary => tripOptions.summary;
}

class _TripOptionsPanelState extends _OptionsPanelState<TripOptionsPanel> {
  static String customChangeMarginDurationString(int minutes) =>
      '${getDurationString(Duration(minutes: minutes))}${minutes >= 5 ? ' extra marginal' : ''}';

  String get customChangeMarginText {
    var minutes = widget.tripOptions.changeMarginMinutes;
    return widget.tripOptions.changeMarginDropdownValue != ChangeMargin.custom || minutes == null
        ? 'Anpassad'
        : 'Anpassad (${customChangeMarginDurationString(minutes)})';
  }

  String get customWalkDistanceText {
    var meters = widget.tripOptions.maxWalkDistance;
    return widget.tripOptions.walkDistanceDropdownValue != WalkDistance.custom || meters == null
        ? 'Anpassad'
        : 'Anpassad (${getDistanceString(meters)})';
  }

  _TripOptionsPanelState();

  @override
  List<Widget> children() {
    var changeMargins = [
      const DropdownMenuItem(value: ChangeMargin.short, child: Text('Kort (2 min)')),
      const DropdownMenuItem(value: ChangeMargin.normal, child: Text('Normal (oftast 5 min)')),
      DropdownMenuItem(value: ChangeMargin.custom, child: Text(customChangeMarginText)),
    ];

    var walkDistances = [
      const DropdownMenuItem(value: WalkDistance.max500m, child: Text('Max 500 m')),
      const DropdownMenuItem(value: WalkDistance.max1km, child: Text('Max 1 km')),
      const DropdownMenuItem(value: WalkDistance.max2km, child: Text('Max 2 km')),
      const DropdownMenuItem(value: WalkDistance.max5km, child: Text('Max 5 km')),
      DropdownMenuItem(value: WalkDistance.custom, child: Text(customWalkDistanceText)),
    ];

    return [
      const Text('Res via hållplats'),
      LocationField(widget.tripOptions.viaFieldController, widget.tripOptions.viaInput, 'Via',
          onlyStops: true,
          suffixIcon: IconButton(
              onPressed: widget.tripOptions.viaFieldController.clearLocation, icon: const Icon(Icons.clear))),
      const SizedBox(height: 16),
      const Text('Bytesmarginal'),
      DropdownButton<ChangeMargin>(
          value: widget.tripOptions.changeMarginDropdownValue,
          onChanged: (ChangeMargin? newValue) {
            if (newValue == ChangeMargin.custom) {
              _customChangeMargin().then((minutes) {
                if (minutes == null) return;
                widget.tripOptions.changeMarginMinutes = minutes;
                setState(() => widget.tripOptions.changeMarginDropdownValue = ChangeMargin.custom);
              });
            } else {
              widget.tripOptions.changeMarginMinutes = newValue == ChangeMargin.short ? 2 : null;
              setState(() => widget.tripOptions.changeMarginDropdownValue = newValue!);
            }
          },
          items: changeMargins),
      if (widget.tripOptions.changeMarginDropdownValue == ChangeMargin.short ||
          (widget.tripOptions.changeMarginMinutes ?? 5) < 5)
        Text('Med kort bytesmarginal gäller inte längre rätten till förseningsersättning',
            style: TextStyle(color: Theme.of(context).hintColor)),
      const SizedBox(height: 16),
      const Text('Färdmedel'),
      const SizedBox(height: 5),
      ServiceButtons(widget.tripOptions),
      const SizedBox(height: 5),
      CheckboxListTile(
        value: widget.tripOptions.includeNearbyStops,
        onChanged: (newValue) => setState(() => widget.tripOptions.includeNearbyStops = newValue ?? true),
        title: const Text('Jag kan gå till närliggande hållplatser'),
      ),
      if (widget.tripOptions.includeNearbyStops) const SizedBox(height: 5),
      if (widget.tripOptions.includeNearbyStops) const Text('Maximal gångsträcka'),
      if (widget.tripOptions.includeNearbyStops) const SizedBox(height: 5),
      if (widget.tripOptions.includeNearbyStops)
        DropdownButton<WalkDistance>(
            value: widget.tripOptions.walkDistanceDropdownValue,
            onChanged: (WalkDistance? newValue) {
              if (newValue == WalkDistance.custom) {
                _customMaxWalkDistance().then((meters) {
                  if (meters == null) return;
                  widget.tripOptions.maxWalkDistance = meters;
                  setState(() => widget.tripOptions.walkDistanceDropdownValue = WalkDistance.custom);
                });
              } else {
                widget.tripOptions.maxWalkDistance = newValue?.meters;
                setState(() => widget.tripOptions.walkDistanceDropdownValue = newValue!);
              }
            },
            items: walkDistances),
    ];
  }

  int? _parseChangeMargin(String text) {
    int? minutes = int.tryParse(text);
    return minutes != null && minutes > 0 && minutes <= 600 ? minutes : null;
  }

  int? _parseWalkDistance(String text) {
    int? meters = int.tryParse(text);
    return meters != null && meters >= 0 && meters <= 10000 ? meters : null;
  }

  Future<int?> _customChangeMargin() async {
    return _customValueDialog('Ange bytesmarginal', 'Ange antal minuter', _parseChangeMargin);
  }

  Future<int?> _customMaxWalkDistance() async {
    return _customValueDialog('Ange maximala gångsträcka', 'Ange antal meter', _parseWalkDistance);
  }

  Future<int?> _customValueDialog(String title, String hintText, int? Function(String) parseValue) async {
    var textController = TextEditingController();
    var valid = ValueNotifier<bool>(false);
    return showDialog<int?>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(title),
            content: TextField(
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: false),
              onChanged: (value) => valid.value = parseValue(value) != null,
              onSubmitted: (value) {
                var parsed = parseValue(value);
                if (parsed == null) return;
                Navigator.pop(context, parsed);
              },
              controller: textController,
              decoration: InputDecoration(hintText: hintText),
            ),
            actions: [
              TextButton(
                child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
                onPressed: () => Navigator.pop(context),
              ),
              ValueListenableBuilder(
                valueListenable: valid,
                builder: (BuildContext context, bool value, Widget? child) => TextButton(
                  onPressed: value ? () => Navigator.pop(context, parseValue(textController.text)) : null,
                  child: Text(MaterialLocalizations.of(context).okButtonLabel),
                ),
              ),
            ],
          );
        });
  }
}

class DepartureBoardOptionsPanel extends StatefulWidget implements OptionsPanel {
  final BoxDepartureBoardOptions departureBoardOptions;

  const DepartureBoardOptionsPanel(this.departureBoardOptions, {super.key});

  @override
  State<DepartureBoardOptionsPanel> createState() => _DepartureBoardOptionsPanel();

  @override
  String? get summary => departureBoardOptions.summary;
}

class _DepartureBoardOptionsPanel extends _OptionsPanelState<DepartureBoardOptionsPanel> {
  _DepartureBoardOptionsPanel();

  @override
  List<Widget> children() {
    return [
      CheckboxListTile(
        value: widget.departureBoardOptions.includeArrivals,
        onChanged: (newValue) {
          setState(() {
            widget.departureBoardOptions.includeArrivals = newValue ?? false;
          });
        },
        title: const Text('Inkludera ankomster'),
      )
    ];
  }
}

abstract class OptionsPanel extends StatefulWidget implements OptionsSummary {
  const OptionsPanel({super.key});
}

abstract class _OptionsPanelState<T extends OptionsPanel> extends State<T> {
  bool expanded = false;

  List<Widget> children();

  @override
  Widget build(BuildContext context) {
    return ExpansionPanelList(
      elevation: 0,
      expandedHeaderPadding: EdgeInsets.zero,
      expansionCallback: (int index, bool isExpanded) {
        setState(() {
          expanded = isExpanded;
        });
      },
      children: [
        ExpansionPanel(
          canTapOnHeader: true,
          headerBuilder: (BuildContext context, bool isExpanded) {
            var summaryText = widget.summary;
            return AnimatedSize(
              duration: kThemeAnimationDuration,
              curve: Curves.easeInOut,
              child: ListTile(
                title: Text('Alternativ', style: TextStyle(color: Theme.of(context).hintColor)),
                subtitle: !expanded && summaryText != null ? Text(summaryText) : null,
              ),
            );
          },
          body: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children(),
              ),
            ),
          ),
          isExpanded: expanded,
        ),
      ],
    );
  }
}
