import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'favorites.dart';
import 'home_widget.dart';
import 'network/planera_resa.dart';
import 'utils.dart';

late Box mainBox;
late Box departureBoardBox;
late Box tripBox;
late Box<Location> favoriteLocationsBox;

bool supportShortcuts = false;
bool useEdgeToEdge = true;
bool supportVttogo = false;

int? androidSdkVersion;

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
  supportVttogo = await canLaunchUrlString('vttogo://s/');
  if (!kIsWeb && Platform.isAndroid) {
    androidSdkVersion = await androidSdk();
    if (androidSdkVersion != null) {
      supportShortcuts = androidSdkVersion! >= 26;
      useEdgeToEdge = androidSdkVersion! >= 29;
    }
  }
  Intl.defaultLocale = 'sv_SE';
  runApp(const MyApp());
}

const Color primaryColor = Color.fromRGBO(0, 121, 180, 1);
const Color primaryDarkColor = Color.fromRGBO(13, 71, 116, 1);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    if (useEdgeToEdge) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    return AnnotatedRegion(
      value: useEdgeToEdge
          ? const SystemUiOverlayStyle(systemNavigationBarColor: Colors.transparent)
          : SystemUiOverlayStyle(
              systemNavigationBarColor: Theme.of(context).canvasColor,
              systemNavigationBarIconBrightness: Brightness.dark),
      child: MaterialApp(
        title: 'Resecentrum',
        scrollBehavior: CustomScrollBehavior(androidSdkVersion),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('sv'),
        ],
        theme: lightTheme(),
        darkTheme: darkTheme(),
        home: const Home(),
      ),
    );
  }

  static ThemeData lightTheme() {
    var colorScheme = ColorScheme.fromSeed(seedColor: primaryColor);
    return ThemeData(
      primarySwatch: createMaterialColor(primaryColor),
      primaryColor: primaryColor,
      colorScheme: colorScheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      filledButtonTheme:
          FilledButtonThemeData(style: ButtonStyle(backgroundColor: WidgetStateProperty.all<Color>(primaryColor))),
      cardTheme: CardTheme(surfaceTintColor: Colors.transparent, color: colorScheme.surface),
      dividerTheme: const DividerThemeData(color: Colors.black12),
      textTheme: const TextTheme(bodyMedium: TextStyle(height: 1.25)),
    );
  }

  static ThemeData darkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: primaryColor,
      colorScheme: ColorScheme.fromSeed(
        brightness: Brightness.dark,
        seedColor: primaryColor,
      ),
      filledButtonTheme: FilledButtonThemeData(
          style: ButtonStyle(
              backgroundColor: WidgetStateProperty.all<Color>(primaryDarkColor),
              foregroundColor: WidgetStateProperty.all<Color>(Colors.white))),
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryDarkColor,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: const DividerThemeData(color: Colors.white10),
      textTheme: const TextTheme(bodyMedium: TextStyle(height: 1.25)),
    );
  }

  static MaterialColor createMaterialColor(Color color) {
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
