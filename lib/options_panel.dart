import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import 'location_searcher.dart';
import 'main.dart';
import 'reseplaneraren.dart';
import 'utils.dart';

class TripOptions {
  ViaOptions viaOptions = ViaOptions();
  ChangeMarginOptions changeMarginOptions = ChangeMarginOptions();
  ToggleVehicleOptions toggleVehicleOptions = ToggleVehicleOptions(tripBox);
  WheelchairOptions wheelchairOptions = WheelchairOptions();
  LocationFieldController viaFieldController = LocationFieldController('via', tripBox);
  final TextEditingController viaInput = RichTextEditingController();
}

class DepartureBoardOptions {
  ToggleVehicleOptions toggleVehicleOptions = ToggleVehicleOptions(departureBoardBox);
  IncludeArrivalOptions includeArrivalOptions = IncludeArrivalOptions();
}

class IncludeArrivalOptions {
  bool get includeArrivals => departureBoardBox.get('includeArrivals', defaultValue: false);

  set includeArrivals(bool value) => departureBoardBox.put('includeArrivals', value);
}

class ViaOptions {
  Location? viaStop;
}

class ToggleVehicleOptions {
  final Box box;

  ToggleVehicleOptions(this.box);

  List<bool> get isSelected => box.get('toggleVehicle', defaultValue: List.filled(vehicleButtons.length, true));

  void toggle(int index) {
    var temp = isSelected;
    temp[index] = !temp[index];
    box.put('toggleVehicle', temp);
  }
}

class ToggleVehicleButtons extends StatefulWidget {
  final ToggleVehicleOptions toggleVehicleOptions;

  const ToggleVehicleButtons(this.toggleVehicleOptions, {Key? key}) : super(key: key);

  @override
  State<ToggleVehicleButtons> createState() => _ToggleVehicleButtonsState();
}

class _ToggleVehicleButtonsState extends State<ToggleVehicleButtons> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => ToggleButtons(
        color: Theme.of(context).hintColor,
        constraints: BoxConstraints.expand(
            width: (constraints.maxWidth - widget.toggleVehicleOptions.isSelected.length - 1) /
                widget.toggleVehicleOptions.isSelected.length),
        children: vehicleButtons
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
        onPressed: (int index) {
          setState(() {
            widget.toggleVehicleOptions.toggle(index);
          });
        },
        isSelected: widget.toggleVehicleOptions.isSelected,
      ),
    );
  }
}

class ChangeMarginOptions {
  ChangeMargin get dropdownValue =>
      ChangeMargin.values[tripBox.get('changeMargin', defaultValue: ChangeMargin.normal.index)];

  set dropdownValue(ChangeMargin value) => tripBox.put('changeMargin', value.index);

  int? get minutes {
    if (dropdownValue == ChangeMargin.custom) return tripBox.get('changeMarginMinutes');
    return dropdownValue == ChangeMargin.short ? 2 : null;
  }

  set minutes(int? value) => tripBox.put('changeMarginMinutes', value);
}

class WheelchairOptions {
  bool get wheelchair => tripBox.get('wheelchair', defaultValue: false);

  set wheelchair(bool value) => tripBox.put('wheelchair', value);
}

enum ChangeMargin { short, normal, custom }

class ToggleVehicle {
  final IconData icon;
  final String name;

  const ToggleVehicle(this.icon, this.name);
}

List<ToggleVehicle> vehicleButtons = const [
  ToggleVehicle(Icons.tram, 'Spårvagn'),
  ToggleVehicle(Icons.directions_bus, 'Buss'),
  ToggleVehicle(Icons.train, 'Västtåg'),
  ToggleVehicle(Icons.directions_railway, 'Övriga tåg'),
  ToggleVehicle(Icons.directions_boat, 'Båt'),
];

class TripOptionsPanel extends StatefulWidget {
  final TripOptions tripOptions;

  const TripOptionsPanel(this.tripOptions, {Key? key}) : super(key: key);

  @override
  State<TripOptionsPanel> createState() => _TripOptionsPanelState();
}

class _TripOptionsPanelState extends _OptionsPanelState<TripOptionsPanel> {
  String get customText {
    var minutes = widget.tripOptions.changeMarginOptions.minutes;
    return widget.tripOptions.changeMarginOptions.dropdownValue != ChangeMargin.custom || minutes == null
        ? 'Anpassad'
        : 'Anpassad (${getDurationString(Duration(minutes: minutes))}${minutes >= 5 ? ' extra marginal' : ''})';
  }

  _TripOptionsPanelState();

  @override
  List<Widget> children() {
    var items = [
      const DropdownMenuItem(
        child: Text('Kort (2 min)'),
        value: ChangeMargin.short,
      ),
      const DropdownMenuItem(
        child: Text('Normal (oftast 5 min)'),
        value: ChangeMargin.normal,
      ),
      DropdownMenuItem(child: Text(customText), value: ChangeMargin.custom),
    ];

    return [
      const Text('Via hållplats:'),
      LocationField(widget.tripOptions.viaFieldController, widget.tripOptions.viaInput, 'Via',
          onlyStops: true,
          suffixIcon: IconButton(
              onPressed: widget.tripOptions.viaFieldController.clearLocation, icon: const Icon(Icons.clear))),
      const SizedBox(height: 16),
      const Text('Minsta bytestid:'),
      DropdownButton<ChangeMargin>(
          value: widget.tripOptions.changeMarginOptions.dropdownValue,
          onChanged: (ChangeMargin? newValue) {
            if (newValue == ChangeMargin.custom) {
              _customChangeMargin().then((minutes) {
                if (minutes == null) return;
                widget.tripOptions.changeMarginOptions.minutes = minutes;
                setState(() {
                  widget.tripOptions.changeMarginOptions.dropdownValue = ChangeMargin.custom;
                });
              });
            } else {
              widget.tripOptions.changeMarginOptions.minutes = newValue == ChangeMargin.short ? 2 : null;
              setState(() {
                widget.tripOptions.changeMarginOptions.dropdownValue = newValue!;
              });
            }
          },
          items: items),
      if (widget.tripOptions.changeMarginOptions.dropdownValue == ChangeMargin.short ||
          (widget.tripOptions.changeMarginOptions.minutes ?? 5) < 5)
        Text('Med kort bytesmarginal gäller inte längre rätten till förseningsersättning.',
            style: TextStyle(color: Theme.of(context).hintColor)),
      const SizedBox(height: 8),
      const Text('Färdmedel:'),
      const SizedBox(height: 5),
      ToggleVehicleButtons(widget.tripOptions.toggleVehicleOptions),
      CheckboxListTile(
          value: widget.tripOptions.wheelchairOptions.wheelchair,
          onChanged: (newValue) {
            setState(() {
              widget.tripOptions.wheelchairOptions.wheelchair = newValue ?? false;
            });
          },
          title: const Text('Rullstolsplats'))
    ];
  }
}

class DepartureBoardOptionsPanel extends StatefulWidget {
  final DepartureBoardOptions departureBoardOptions;

  const DepartureBoardOptionsPanel(this.departureBoardOptions, {Key? key}) : super(key: key);

  @override
  State<DepartureBoardOptionsPanel> createState() => _DepartureBoardOptionsPanel();
}

class _DepartureBoardOptionsPanel extends _OptionsPanelState<DepartureBoardOptionsPanel> {
  _DepartureBoardOptionsPanel();

  @override
  List<Widget> children() {
    return [
      const Text('Färdmedel:'),
      const SizedBox(height: 5),
      ToggleVehicleButtons(widget.departureBoardOptions.toggleVehicleOptions),
      CheckboxListTile(
        value: widget.departureBoardOptions.includeArrivalOptions.includeArrivals,
        onChanged: (newValue) {
          setState(() {
            widget.departureBoardOptions.includeArrivalOptions.includeArrivals = newValue ?? false;
          });
        },
        title: const Text('Inkludera ankomster'),
      )
    ];
  }
}

abstract class _OptionsPanelState<T extends StatefulWidget> extends State<T> {
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
            return ListTile(
              title: Text('Fler alternativ', style: TextStyle(color: Theme.of(context).hintColor)),
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

  int? _parseChangeMargin(String text) {
    int? minutes = int.tryParse(text);
    return minutes != null && minutes > 0 ? minutes : null;
  }

  Future<int?> _customChangeMargin() async {
    TextEditingController textController = TextEditingController();
    return showDialog<int?>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Ange minsta bytesmarginal'),
            content: TextField(
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: false),
              onSubmitted: (value) {
                Navigator.pop(context, _parseChangeMargin(value));
              },
              controller: textController,
              decoration: const InputDecoration(hintText: 'Ange antal minuter'),
            ),
            actions: [
              TextButton(
                child: const Text('AVBRYT'),
                onPressed: () {
                  setState(() {
                    Navigator.pop(context);
                  });
                },
              ),
              TextButton(
                child: const Text('OK'),
                onPressed: () {
                  setState(() {
                    Navigator.pop(context, _parseChangeMargin(textController.text));
                  });
                },
              ),
            ],
          );
        });
  }
}
