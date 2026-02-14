import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_custom_tabs/flutter_custom_tabs_lite.dart';
import 'package:html/parser.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_refresher/webview_refresher.dart';

import 'extensions.dart';
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
  Completer<void>? _completer;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(false)
      ..setNavigationDelegate(
        NavigationDelegate(onPageFinished: (s) {
          _finishRefresh();
          if (!mounted) return;
          setState(() => _isLoading = false);
        }, onWebResourceError: (e) {
          _finishRefresh();
          if (!mounted || (e.isForMainFrame == false)) return;
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
        SafeArea(child: WebviewRefresher(controller: _controller, onRefresh: _onRefresh)),
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

  Future<void> _load() async {
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

  Future<void> _onRefresh() async {
    _completer = Completer<void>();
    if (await _controller.currentUrl() == null) {
      await _load();
    } else {
      await _controller.reload();
    }
    await _completer!.future;
  }

  void _finishRefresh() {
    if (_completer == null) return;
    if (!_completer!.isCompleted) {
      _completer?.complete();
    }
  }

  void scrollToTop() => _controller.scrollTo(0, 0);
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
        --canvas-color: ${MyApp.darkTheme().canvasColor.toHexCode()};
    }

    body {
        color: white;
    }
    
    .page, body {
        background-color: var(--canvas-color);
    }
    
    .bg-white, .bg-sm-white, .accordion-button {
        background-color: var(--canvas-color) !important;
    }
     
    a, a:hover, .btn--as-text {
        color: #c2e4ef;
    }
    
    .traffic-situation-one-dot-one {
        background-color: var(--card-color) !important;
        border: solid #505050 !important;
    }
    
    .autocomplete {
        background-color: var(--card-color) !important;
        box-shadow: inset 0 1px 2px #505050;
    }
    
    .autocomplete .autocomplete-results {
        background-color: var(--card-color) !important;
    }
    
    .autocomplete .background-transparent, .accordion-item {
        color: white !important;
    }
    
    .accordion-button {
        color: #c2e4ef !important;
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
    
    .btn.btn-link, .selected-filter-value__close, .line-list-showcase__transport-mode, .municipality-list-showcase__icon, .traffic-situation-two-dot-zero__calendar-icon {
        filter: invert(1) grayscale(1);
    }
    
    .traffic-situation-tag {
        border-color: var(--canvas-color);
        outline-color: var(--canvas-color);
    }
}
''';
