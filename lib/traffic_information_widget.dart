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
        WebView(
          initialUrl: '$baseUrl/ts${Platform.isIOS ? 'iphone' : 'android'}',
          javascriptMode: JavascriptMode.unrestricted,
          zoomEnabled: false,
          onWebViewCreated: (controller) => _controller = controller,
          onPageFinished: (_) => setState(() {
            _isLoading = false;
          }),
          onWebResourceError: (_) => setState(() {
            _isError = true;
          }),
          navigationDelegate: (NavigationRequest request) {
            if (request.url.startsWith('$baseUrl/trafikinformation') || request.url.startsWith('$baseUrl/ts')) {
              return NavigationDecision.navigate;
            }
            _launchURL(context, request.url);
            return NavigationDecision.prevent;
          },
        ),
        if (_isLoading) Container(color: Theme.of(context).canvasColor),
        if (_isError)
          Container(
              child: ErrorPage(() async {
                _controller?.reload();
                setState(() {
                  _isError = false;
                  _isLoading = true;
                });
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
