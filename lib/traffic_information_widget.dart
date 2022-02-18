import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_custom_tabs/flutter_custom_tabs.dart';
import 'package:resecentrum/utils.dart';
import 'package:webview_flutter/webview_flutter.dart';

class TrafficInformationWidget extends StatefulWidget {
  const TrafficInformationWidget({Key? key}) : super(key: key);

  @override
  TrafficInformationState createState() => TrafficInformationState();
}

const String baseUrl = 'https://www.vasttrafik.se';

class TrafficInformationState extends State<TrafficInformationWidget> {
  bool _isLoading = true;
  bool _isError = false;

  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) WebView.platform = SurfaceAndroidWebView();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SafeArea(
          child: WebView(
              initialUrl: '$baseUrl/ts${Platform.isIOS ? 'iphone' : 'android'}',
              javascriptMode: JavascriptMode.unrestricted,
              zoomEnabled: false,
              backgroundColor: Theme.of(context).canvasColor,
              onWebViewCreated: (controller) => _controller = controller,
              onPageStarted: (_) {
                _controller?.runJavascript('''
                  const sheet = new CSSStyleSheet();
                  sheet.replaceSync("${darkModeCSS.replaceAll('\n', ' ')}");  
                  document.adoptedStyleSheets = [sheet];
                ''');
              },
              onPageFinished: (_) => setState(() => _isLoading = false),
              onWebResourceError: (_) => setState(() => _isError = true),
              navigationDelegate: (NavigationRequest request) {
                if (request.url.startsWith('$baseUrl/trafikinformation') || request.url.startsWith('$baseUrl/ts')) {
                  return NavigationDecision.navigate;
                }
                _launchURL(context, request.url);
                return NavigationDecision.prevent;
              }),
        ),
        if (_isLoading) loadingPage(),
        if (_isError)
          Container(
              child: ErrorPage(() async {
                setState(() {
                  _isError = false;
                  _isLoading = true;
                });
                _controller?.reload();
              }),
              color: Theme.of(context).canvasColor),
      ],
    );
  }
}

void _launchURL(BuildContext context, String url) async {
  try {
    await launch(
      url,
      customTabsOption: CustomTabsOption(
        toolbarColor: Theme.of(context).primaryColor,
        enableUrlBarHiding: true,
        showPageTitle: true,
        extraCustomTabs: const <String>[
          'org.mozilla.firefox',
          'com.microsoft.emmx',
        ],
      ),
    );
  } catch (e) {
    debugPrint(e.toString());
  }
}

const String darkModeCSS = '''
@media (prefers-color-scheme: dark) {
    body {
        color: white;
    }
    
    .page, body {
        background-color: #303030;
    }
    
    .bg-gray, .bg-gray-darker {
        background-color: #424242 !important;
    }
     
    a, a:hover, .btn--as-text {
        color: #c2e4ef;
    }
    
    .traffic-situation-one-dot-one[data-v-6e8db774] {
        background-color: #424242;
        border: solid #505050;
    }
    
    .line-list-showcase__transport-mode[data-v-267d2d50] {
        filter: invert(1);
    }
    
    .autocomplete[data-v-9fb93e08], .autocomplete[data-v-43ca31ec] {
        background-color: #424242;
        box-shadow: inset 0 1px 2px #505050;
    }
    
    .autocomplete .autocomplete-results[data-v-43ca31ec], .autocomplete .autocomplete-results[data-v-9fb93e08] {
        background-color: #424242;
    }
    
    .autocomplete .background-transparent[data-v-9fb93e08], .autocomplete .background-transparent[data-v-43ca31ec] {
        color: white;
    }
    
    .autocomplete .background-transparent[data-v-9fb93e08]::placeholder,
    .autocomplete .background-transparent[data-v-43ca31ec]::placeholder {
        color: #BDBDBD;
    }
    
    .selected-filter-value {
        color: white;
        background-color: #424242;
        box-shadow: 0 1px 5px rgba(0,0,0,.22);
    }
    
    .form-control {
        color: white;
    }
    
    .custom-checkbox .custom-control-label:before, .custom-radio .custom-control-label:before {
        background-color: #424242;
    }
}
''';
