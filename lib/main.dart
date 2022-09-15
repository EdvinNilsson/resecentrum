import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import 'favorites.dart';
import 'home_widget.dart';
import 'reseplaneraren.dart';

late Box mainBox;
late Box departureBoardBox;
late Box tripBox;
late Box<Location> favoriteLocationsBox;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(StopLocationAdapter());
  Hive.registerAdapter(CoordLocationAdapter());
  Hive.registerAdapter(TripHistoryAdapter());
  Hive.registerAdapter(CurrentLocationAdapter());
  mainBox = await Hive.openBox('main');
  tripBox = await Hive.openBox('trip');
  departureBoardBox = await Hive.openBox('departureBoard');
  favoriteLocationsBox = await Hive.openBox('favoriteLocations');
  Intl.defaultLocale = 'sv_SE';
  runApp(const MyApp());
}

const Color primaryColor = Color.fromRGBO(0, 121, 180, 1);

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    return AnnotatedRegion(
      value: const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
      ),
      child: MaterialApp(
        title: 'Resecentrum',
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('sv'),
        ],
        theme: ThemeData(primarySwatch: createMaterialColor(primaryColor)),
        darkTheme: ThemeData(
          brightness: Brightness.dark,
          primaryColor: primaryColor,
          toggleableActiveColor: primaryColor,
          elevatedButtonTheme: ElevatedButtonThemeData(
              style: ButtonStyle(foregroundColor: MaterialStateProperty.all<Color>(Colors.white))),
          appBarTheme: const AppBarTheme(
            backgroundColor: primaryColor,
          ),
          colorScheme: const ColorScheme.dark().copyWith(primary: primaryColor, secondary: primaryColor),
        ),
        home: const Home(),
      ),
    );
  }

  MaterialColor createMaterialColor(Color color) {
    List strengths = <double>[.05];
    final swatch = <int, Color>{};
    final int r = color.red, g = color.green, b = color.blue;

    for (int i = 1; i < 10; i++) {
      strengths.add(0.1 * i);
    }
    for (var strength in strengths) {
      final double ds = 0.5 - strength;
      swatch[(strength * 1000).round()] = Color.fromRGBO(
        r + ((ds < 0 ? r : (255 - r)) * ds).round(),
        g + ((ds < 0 ? g : (255 - g)) * ds).round(),
        b + ((ds < 0 ? b : (255 - b)) * ds).round(),
        1,
      );
    }
    return MaterialColor(color.value, swatch);
  }
}
