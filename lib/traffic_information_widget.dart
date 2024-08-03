import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_custom_tabs/flutter_custom_tabs_lite.dart';
import 'package:html/parser.dart';
import 'package:resecentrum/extensions.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'main.dart';
import 'utils.dart';

class TrafficInformationWidget extends StatefulWidget {
  const TrafficInformationWidget({super.key});

  @override
  TrafficInformationState createState() => TrafficInformationState();
}

const String url = 'https://www.vasttrafik.se/trafikinformation/';

class TrafficInformationState extends State<TrafficInformationWidget> {
  bool _isLoading = true;
  Object? _error;

  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(false)
      ..setNavigationDelegate(
        NavigationDelegate(onPageFinished: (s) {
          if (!mounted) return;
          setState(() => _isLoading = false);
        }, onWebResourceError: (e) {
          if (!mounted) return;
          if (kDebugMode) print(e);
          setState(() => _error = e);
        }, onNavigationRequest: (NavigationRequest request) {
          if (request.url.startsWith(url)) {
            return NavigationDecision.navigate;
          }
          _launchURL(context, request.url);
          return NavigationDecision.prevent;
        }),
      );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    _controller.setBackgroundColor(Theme.of(context).canvasColor);
    return Stack(
      children: [
        SafeArea(child: WebViewWidget(controller: _controller)),
        if (_isLoading) loadingPage(),
        if (_error != null)
          Container(
              color: Theme.of(context).canvasColor,
              child: ErrorPage(() async {
                setState(() {
                  _error = null;
                  _isLoading = true;
                });
                _load();
              }, error: NoInternetError(_error!))),
      ],
    );
  }

  void _load() async {
    try {
      var res = await Dio().get(url);

      try {
        var document = parse(res.data);

        var content = document.getElementsByClassName('page-content')[0];
        document.body!.insertBefore(content, document.body!.firstChild);

        var elements = document.querySelectorAll('body > :not(script)');
        for (var element in elements.skip(1)) {
          element.remove();
        }

        var style = document.createElement('style');
        style.innerHtml = customCss();
        document.head!.append(style);

        var csp = document.createElement('meta');
        csp.attributes = {
          'http-equiv': 'Content-Security-Policy',
          'content': "script-src 'unsafe-inline' 'unsafe-eval' 'self' *.vasttrafik.se"
        } as LinkedHashMap<Object, String>;
        document.head!.append(csp);

        _controller.loadHtmlString(document.outerHtml, baseUrl: url);
      } catch (_) {
        _controller.loadHtmlString(res.data, baseUrl: url);
      }
      setState(() => _isLoading = false);
    } on DioException catch (error) {
      setState(() => _error = error);
    }
  }
}

void _launchURL(BuildContext context, String url) async {
  try {
    await launchUrl(Uri.parse(url),
        options: LaunchOptions(
          barColor: Theme.of(context).primaryColor,
        ));
  } catch (e) {
    debugPrint(e.toString());
  }
}

String customCss() => '''
html {
    margin: 1rem;
    height: auto;
}



@media (prefers-color-scheme: dark) {
    :root {
        --card-color: ${MyApp.darkTheme().colorScheme.surfaceBright.toHexCode()};
    }

    body {
        color: white;
    }
    
    .page, body {
        background-color: ${MyApp.darkTheme().canvasColor.toHexCode()};
    }
     
    a, a:hover, .btn--as-text {
        color: #c2e4ef;
    }
    
    .traffic-situation-one-dot-one {
        background-color: var(--card-color) !important;
        border: solid #505050 !important;
    }
    
    .line-list-showcase__transport-mode {
        filter: invert(75%);
    }
    
    .autocomplete {
        background-color: var(--card-color) !important;
        box-shadow: inset 0 1px 2px #505050;
    }
    
    .autocomplete .autocomplete-results {
        background-color: var(--card-color) !important;
    }
    
    .autocomplete .background-transparent {
        color: white !important;
    }
    
    .autocomplete .background-transparent::placeholder {
        color: #BDBDBD;
    }

    .border, .border-x, .border-top {
        border-color: #505050 !important;
    }
    
    .selected-filter-value {
        color: white;
        background-color: var(--card-color);
        box-shadow: 0 1px 5px rgba(0,0,0,.22);
    }
    
    .form-control {
        color: white !important;
        background-color: var(--card-color) !important;
    }

    .form-control::placeholder {
        color: #ffffff99;
    }
    
    .custom-checkbox .custom-control-label:before, .custom-radio .custom-control-label:before {
        background-color: var(--card-color);
    }

    .bg-gray, .bg-gray-darker {
        background-color: var(--card-color) !important;
    }
}
''';
