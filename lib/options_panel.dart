import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import 'extensions.dart';
import 'location_searcher.dart';
import 'main.dart';
import 'reseplaneraren.dart';
import 'utils.dart';

abstract class BoxOption {
  late Box box;
}

abstract class TripOptions with ChangeMarginGetter, ServicesGetter, WheelchairGetter, ViaGetter, OptionsSummary {}

abstract class DepartureBoardOptions with IncludeArrivalGetter, ServicesGetter, OptionsSummary {}

abstract class ChangeMarginGetter {
  int? get changeMarginMinutes;
}

abstract class ServicesGetter {
  List<bool> get services;
}

abstract class WheelchairGetter {
  bool get wheelchair;
}

abstract class ViaGetter {
  StopLocation? get via;
}

abstract class IncludeArrivalGetter {
  bool get includeArrivals;
}

abstract class OptionsSummary {
  String? get summary;
}

class BoxTripOptions extends BoxOption
    with ChangeMarginOption, ServicesOption, WheelchairOption, TripOptionsSummary
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
  bool get wheelchair => params['wheelchair'] == 'true';
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

    if (!services.every((s) => s)) changes.add('Färdmedelsfilter');

    if (wheelchair) changes.add('Rullstolsplats');

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

  @override
  List<bool> get services =>
      params['service']?.split('').map((s) => s == '1').toList(growable: false) ??
      List.filled(serviceButtons.length, true);
}

mixin DepartureBoardOptionsSummary implements DepartureBoardOptions {
  @override
  String? get summary {
    List<String> changes = [];
    if (!services.every((s) => s)) changes.add('Färdmedelsfilter');
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

  void toggle(int index) {
    var temp = services;
    temp[index] = !temp[index];
    box.put('toggleVehicle', temp);
  }
}

class ServiceButtons extends StatefulWidget {
  final ServicesOption servicesOption;

  const ServiceButtons(this.servicesOption, {Key? key}) : super(key: key);

  @override
  State<ServiceButtons> createState() => _ServiceButtonsState();
}

class _ServiceButtonsState extends State<ServiceButtons> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => ToggleButtons(
        color: Theme.of(context).hintColor,
        constraints: BoxConstraints.expand(
            width: (constraints.maxWidth - widget.servicesOption.services.length - 1) /
                widget.servicesOption.services.length),
        onPressed: (int index) {
          setState(() {
            widget.servicesOption.toggle(index);
          });
        },
        isSelected: widget.servicesOption.services,
        children: serviceButtons
            .map((v) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(v.icon),
                      Text(v.name, textAlign: TextAlign.center),
                    ],
                  ),
                ))
            .toList(growable: false),
      ),
    );
  }
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

mixin WheelchairOption on BoxOption implements WheelchairGetter {
  @override
  bool get wheelchair => box.get('wheelchair', defaultValue: false);

  set wheelchair(bool value) => box.put('wheelchair', value);
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

  const TripOptionsPanel(this.tripOptions, {Key? key}) : super(key: key);

  @override
  State<TripOptionsPanel> createState() => _TripOptionsPanelState();

  @override
  String? get summary => tripOptions.summary;
}

class _TripOptionsPanelState extends _OptionsPanelState<TripOptionsPanel> {
  static String customChangeMarginDurationString(int minutes) =>
      '${getDurationString(Duration(minutes: minutes))}${minutes >= 5 ? ' extra marginal' : ''}';

  String get customText {
    var minutes = widget.tripOptions.changeMarginMinutes;
    return widget.tripOptions.changeMarginDropdownValue != ChangeMargin.custom || minutes == null
        ? 'Anpassad'
        : 'Anpassad (${customChangeMarginDurationString(minutes)})';
  }

  _TripOptionsPanelState();

  @override
  List<Widget> children() {
    var items = [
      const DropdownMenuItem(value: ChangeMargin.short, child: Text('Kort (2 min)')),
      const DropdownMenuItem(value: ChangeMargin.normal, child: Text('Normal (oftast 5 min)')),
      DropdownMenuItem(value: ChangeMargin.custom, child: Text(customText)),
    ];

    return [
      const Text('Via hållplats'),
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
                setState(() {
                  widget.tripOptions.changeMarginDropdownValue = ChangeMargin.custom;
                });
              });
            } else {
              widget.tripOptions.changeMarginMinutes = newValue == ChangeMargin.short ? 2 : null;
              setState(() {
                widget.tripOptions.changeMarginDropdownValue = newValue!;
              });
            }
          },
          items: items),
      if (widget.tripOptions.changeMarginDropdownValue == ChangeMargin.short ||
          (widget.tripOptions.changeMarginMinutes ?? 5) < 5)
        Text('Med kort bytesmarginal gäller inte längre rätten till förseningsersättning',
            style: TextStyle(color: Theme.of(context).hintColor)),
      const SizedBox(height: 16),
      const Text('Färdmedel'),
      const SizedBox(height: 5),
      ServiceButtons(widget.tripOptions),
      CheckboxListTile(
          value: widget.tripOptions.wheelchair,
          onChanged: (newValue) {
            setState(() {
              widget.tripOptions.wheelchair = newValue ?? false;
            });
          },
          title: const Text('Rullstolsplats'))
    ];
  }

  int? _parseChangeMargin(String text) {
    int? minutes = int.tryParse(text);
    return minutes != null && minutes > 0 && minutes <= 600 ? minutes : null;
  }

  Future<int?> _customChangeMargin() async {
    var textController = TextEditingController();
    var valid = ValueNotifier<bool>(false);
    return showDialog<int?>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Ange bytesmarginal'),
            content: TextField(
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: false),
              onChanged: (value) => valid.value = _parseChangeMargin(value) != null,
              onSubmitted: (value) {
                var minutes = _parseChangeMargin(value);
                if (minutes == null) return;
                Navigator.pop(context, minutes);
              },
              controller: textController,
              decoration: const InputDecoration(hintText: 'Ange antal minuter'),
            ),
            actions: [
              TextButton(
                child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
                onPressed: () => Navigator.pop(context),
              ),
              ValueListenableBuilder(
                valueListenable: valid,
                builder: (BuildContext context, bool value, Widget? child) => TextButton(
                  onPressed: value ? () => Navigator.pop(context, _parseChangeMargin(textController.text)) : null,
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

  const DepartureBoardOptionsPanel(this.departureBoardOptions, {Key? key}) : super(key: key);

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
      const Text('Färdmedel'),
      const SizedBox(height: 5),
      ServiceButtons(widget.departureBoardOptions),
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
  const OptionsPanel({Key? key}) : super(key: key);
}

abstract class _OptionsPanelState<T extends OptionsPanel> extends State<T> {
  bool expanded = false;

  List<Widget> children();

  @override
  Widget build(BuildContext context) {
    return ExpansionPanelList(
      elevation: expanded ? 2 : 0,
      expandedHeaderPadding: EdgeInsets.zero,
      expansionCallback: (int index, bool isExpanded) {
        setState(() {
          expanded = !isExpanded;
        });
      },
      children: [
        ExpansionPanel(
          backgroundColor: expanded ? null : Theme.of(context).canvasColor,
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
          body: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children(),
            ),
          ),
          isExpanded: expanded,
        ),
      ],
    );
  }
}
