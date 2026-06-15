import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  static const _url = 'https://soocher-doctor.vercel.app/login';

  late final WebViewController _wvc;
  int _progress = 0;
  bool _loading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _wvc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF8FAFC))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) => setState(() {
            _progress = p;
            _loading = p < 100;
          }),
          onPageStarted: (_) => setState(() {
            _loading = true;
            _hasError = false;
          }),
          onPageFinished: (_) => setState(() => _loading = false),
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? true) {
              setState(() {
                _hasError = true;
                _loading = false;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_url));
  }

  void _reload() {
    setState(() {
      _hasError = false;
      _loading = true;
    });
    _wvc.loadRequest(Uri.parse(_url));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _wvc.canGoBack()) {
          _wvc.goBack();
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF2E6DD4),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              AnimatedOpacity(
                opacity: _loading ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: LinearProgressIndicator(
                  value: _progress / 100.0,
                  minHeight: 3,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              Expanded(
                child: _hasError
                    ? _errorView()
                    : WebViewWidget(controller: _wvc),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorView() {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                size: 64,
                color: Color(0xFF2E6DD4),
              ),
              const SizedBox(height: 16),
              const Text(
                'No connection',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Check your internet connection\nand try again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF64748B),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _reload,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E6DD4),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Try Again',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
