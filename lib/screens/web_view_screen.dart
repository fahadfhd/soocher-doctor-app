import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';

import 'login_screen.dart';
import 'video_call_screen.dart';

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  static const _baseUrl   = 'https://soocher-doctor.vercel.app';
  static const _tokenApi  = '$_baseUrl/api/native-auth-token';
  static const _nativeAuth = '$_baseUrl/native-auth';
  static const _dashboard  = '$_baseUrl/dashboard';

  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 16; Mobile) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';

  late final WebViewController _wvc;
  int  _progress      = 0;
  bool _loading     = true;
  bool _hasError    = false;
  bool _joiningCall = false;
  bool _signingIn   = false;

  @override
  void initState() {
    super.initState();
    _wvc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF8FAFC))
      ..setUserAgent(_userAgent)
      ..addJavaScriptChannel('SoocherBridge', onMessageReceived: _onBridgeMessage)
      ..setOnConsoleMessage((msg) => debugPrint('[WebConsole] ${msg.level.name}: ${msg.message}'))
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (req) {
          final url = req.url;
          debugPrint('[NavRequest] url=$url isMain=${req.isMainFrame}');

          // Video call room
          final roomMatch = RegExp(r'/consultations/([^/?#]+)/room').firstMatch(url);
          if (roomMatch != null) {
            _requestVideoCallData(roomMatch.group(1)!);
            return NavigationDecision.prevent;
          }

          // Web redirected to /login — re-auth or real logout
          if (_isLoginUrl(url)) {
            debugPrint('[NavRequest] → login detected, handling');
            _handleLoginDetected();
            return NavigationDecision.prevent;
          }

          if (url.startsWith('https://') ||
              url.startsWith('http://') ||
              url.startsWith('about:')) {
            return NavigationDecision.navigate;
          }
          return NavigationDecision.prevent;
        },
        onProgress: (p) => setState(() {
          _progress = p;
          _loading  = p < 100;
        }),
        onPageStarted: (_) => setState(() {
          _loading  = true;
          _hasError = false;
        }),
        onPageFinished: (url) {
          debugPrint('[PageFinished] url=$url');
          setState(() => _loading = false);
          if (_isLoginUrl(url)) {
            debugPrint('[PageFinished] → login detected, handling');
            _handleLoginDetected();
            return;
          }
          _injectRouteHook();
          _injectOverscrollFix();
          _injectDatePickerHook();
          _injectHeaderPaddingFix();
        },
        onUrlChange: (UrlChange change) {
          final url = change.url ?? '';
          debugPrint('[UrlChange] url=$url');
          if (_isLoginUrl(url)) {
            debugPrint('[UrlChange] → login detected, handling');
            _handleLoginDetected();
          }
          final path = Uri.tryParse(url)?.path ?? '';
          if (path.startsWith('/onboarding')) {
            Future.delayed(const Duration(milliseconds: 600), _injectHeaderPaddingFix);
          }
        },
        onWebResourceError: (error) {
          debugPrint('[SoocherWebView] resource error: isForMainFrame=${error.isForMainFrame} code=${error.errorCode} desc=${error.description} url=${error.url}');
          // isForMainFrame is null on some Android API levels — treat null as main frame
          if (error.isForMainFrame != false) {
            debugPrint('[SoocherWebView] → triggering error screen');
            setState(() { _hasError = true; _loading = false; });
          }
        },
      ));

    // Kick off the first auth load and FCM registration
    _loadWithCustomToken();
    _registerFcmToken();
  }

  // ── Custom-token auth flow ────────────────────────────────────────────────

  bool _isLoginUrl(String url) {
    final p = Uri.tryParse(url)?.path ?? '';
    return p == '/login';
  }

  /// Get a Firebase custom token from the web app's API route, then load
  /// /native-auth?ct=<token> so the web Firebase SDK signs in natively.
  Future<void> _loadWithCustomToken() async {
    if (_signingIn) return;
    setState(() => _signingIn = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _doSignOut();
      return;
    }

    try {
      final idToken = await user.getIdToken();
      debugPrint('[SoocherAuth] got idToken, posting to $_tokenApi');
      final res = await http.post(
        Uri.parse(_tokenApi),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 8));

      debugPrint('[SoocherAuth] API status=${res.statusCode} body=${res.body}');

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final customToken = body['customToken'] as String?;
        if (customToken != null && customToken.isNotEmpty) {
          final uri = Uri.parse(_nativeAuth).replace(
            queryParameters: {'ct': customToken},
          );
          debugPrint('[SoocherAuth] loading ${uri.toString().substring(0, 60)}…');
          _wvc.loadRequest(uri);
          setState(() => _signingIn = false);
          return;
        }
      }
    } catch (e) {
      debugPrint('[SoocherAuth] exception: $e');
    }

    // API failed — show native error so user can retry; don't load /dashboard
    // because the web app would just redirect to its own /login screen.
    debugPrint('[SoocherAuth] falling through to error screen');
    setState(() { _signingIn = false; _hasError = true; _loading = false; });
  }

  // ── FCM token registration ────────────────────────────────────────────────

  Future<void> _registerFcmToken() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      await FirebaseFirestore.instance
          .collection('Users')
          .doc(uid)
          .update({'fcmToken': token});
      debugPrint('[FCM] token registered');

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        if (currentUid == null) return;
        await FirebaseFirestore.instance
            .collection('Users')
            .doc(currentUid)
            .update({'fcmToken': newToken});
        debugPrint('[FCM] token refreshed');
      });
    } catch (e) {
      debugPrint('[FCM] error: $e');
    }
  }

  /// Called when the web app navigates (or tries to navigate) to /login.
  /// If native user still exists → re-auth via custom token.
  /// If native user is gone → real logout → native LoginScreen.
  void _handleLoginDetected() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _loadWithCustomToken();
    } else {
      _doSignOut();
    }
  }

  Future<void> _doSignOut() async {
    if (!mounted) return;
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const LoginScreen(),
        transitionDuration: const Duration(milliseconds: 350),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
      (_) => false,
    );
  }

  // ── Overscroll fix ───────────────────────────────────────────────────────

  void _injectOverscrollFix() {
    _wvc.runJavaScript(r'''
(function() {
  if (window.__soocherScrollFixed) return;
  window.__soocherScrollFixed = true;

  document.documentElement.style.overscrollBehavior = 'none';
  document.documentElement.style.overscrollBehaviorY = 'none';
  document.body.style.overscrollBehavior = 'none';

  var startY = 0;
  document.addEventListener('touchstart', function(e) {
    startY = e.touches[0].clientY;
  }, { passive: true });

  document.addEventListener('touchmove', function(e) {
    if (!e.cancelable) return;
    var el = e.target;
    while (el && el !== document.body) {
      var ov = window.getComputedStyle(el).overflowY;
      if (ov === 'auto' || ov === 'scroll') {
        var atTop    = el.scrollTop <= 0;
        var atBottom = el.scrollTop + el.clientHeight >= el.scrollHeight - 1;
        var goingUp  = e.touches[0].clientY > startY;
        if ((atTop && goingUp) || (atBottom && !goingUp)) e.preventDefault();
        return;
      }
      el = el.parentElement;
    }
    var scrollTop = document.documentElement.scrollTop || document.body.scrollTop;
    var scrollMax = document.documentElement.scrollHeight - window.innerHeight;
    var goingUp = e.touches[0].clientY > startY;
    if ((scrollTop <= 0 && goingUp) || (scrollTop >= scrollMax - 1 && !goingUp)) {
      e.preventDefault();
    }
  }, { passive: false });
})();
''');
  }

  // ── Date picker interception ─────────────────────────────────────────────

  void _injectDatePickerHook() {
    _wvc.runJavaScript(r'''
(function() {
  if (window.__soocherDateHooked) return;
  window.__soocherDateHooked = true;

  function interceptDateInput(input) {
    if (input.__soocherDate) return;
    input.__soocherDate = true;

    // Store real value on a data attribute, convert to readonly text
    // so the native Android date picker never opens.
    var realValue = input.value || '';
    input.setAttribute('data-sd-value', realValue);
    input.setAttribute('type', 'text');
    input.setAttribute('readonly', 'readonly');
    input.style.caretColor = 'transparent';
    if (realValue) input.value = realValue;

    input.addEventListener('click', function(e) {
      e.preventDefault();
      e.stopPropagation();
      if (!input.id) input.id = '__sd_' + Math.random().toString(36).substr(2, 8);
      SoocherBridge.postMessage(JSON.stringify({
        type: 'date_picker',
        fieldId: input.id,
        currentValue: input.getAttribute('data-sd-value') || ''
      }));
    }, true);
  }

  document.querySelectorAll('input[type="date"]').forEach(interceptDateInput);

  new MutationObserver(function(mutations) {
    mutations.forEach(function(m) {
      m.addedNodes.forEach(function(node) {
        if (node.nodeType !== 1) return;
        if (node.matches('input[type="date"]')) interceptDateInput(node);
        node.querySelectorAll('input[type="date"]').forEach(interceptDateInput);
      });
    });
  }).observe(document.body, { childList: true, subtree: true });
})();
''');
  }

  void _setDateInputValue(String fieldId, String value) {
    final safeId = fieldId.replaceAll("'", r"\'");
    final safeVal = value.replaceAll("'", r"\'");
    _wvc.runJavaScript('''
(function() {
  var input = document.getElementById('$safeId');
  if (!input) return;
  input.setAttribute('data-sd-value', '$safeVal');
  var setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
  setter.call(input, '$safeVal');
  input.dispatchEvent(new Event('input', { bubbles: true }));
  input.dispatchEvent(new Event('change', { bubbles: true }));
})();
''');
  }

  // ── Onboarding header-gap fix ────────────────────────────────────────────

  void _injectHeaderPaddingFix() {
    _wvc.runJavaScript(r'''
(function() {
  console.log('[HeaderFix] path=' + window.location.pathname);
  if (!window.location.pathname.startsWith('/onboarding')) return;
  function applyFix() {
    var header = document.querySelector('header');
    if (!header) { console.log('[HeaderFix] no header yet'); return false; }
    var h = header.getBoundingClientRect().height;
    console.log('[HeaderFix] header h=' + h);
    if (h < 10) return false;
    // Inject a persistent <style> block so React re-renders can't clobber it
    var styleId = '__sd_hfix';
    var existing = document.getElementById(styleId);
    if (existing) existing.remove();
    var s = document.createElement('style');
    s.id = styleId;
    // target any direct scroll-container child that is not fixed/sticky
    s.textContent =
      '[data-sd-content] { padding-top: ' + h + 'px !important; }';
    document.head.appendChild(s);
    // Mark the content element with our data attribute
    var parent = header.parentNode;
    if (!parent) return false;
    for (var i = 0; i < parent.children.length; i++) {
      var el = parent.children[i];
      if (el === header) continue;
      var pos = window.getComputedStyle(el).position;
      if (pos === 'fixed' || pos === 'sticky') continue;
      el.setAttribute('data-sd-content', '1');
      console.log('[HeaderFix] applied ' + h + 'px to', el.tagName, el.className.slice(0,40));
      return true;
    }
    return false;
  }
  if (!applyFix()) {
    var tries = 0;
    var t = setInterval(function() {
      if (applyFix() || ++tries > 30) clearInterval(t);
    }, 100);
  }
})();
''');
  }

  // ── Route hook (client-side navigation detection) ───────────────────────

  void _injectRouteHook() {
    _wvc.runJavaScript(r'''
(function() {
  if (window.__soocherHooked) return;
  window.__soocherHooked = true;

  function checkPath(path) {
    var p = path || window.location.pathname;

    if (p === '/login') {
      SoocherBridge.postMessage(JSON.stringify({ type: 'login_detected' }));
      return;
    }

    var match = p.match(/\/consultations\/([^/?#]+)\/room/);
    if (!match) return;
    var cid = match[1];

    setTimeout(function() { history.back(); }, 30);

    try {
      var req = indexedDB.open('firebaseLocalStorageDb', 1);
      req.onsuccess = function(e) {
        var db = e.target.result;
        var all = db.transaction(['firebaseLocalStorage'], 'readonly')
                    .objectStore('firebaseLocalStorage').getAll();
        all.onsuccess = function() {
          var uid = null, token = null;
          for (var i = 0; i < all.result.length; i++) {
            var item = all.result[i];
            if (item.fbase_key && item.fbase_key.indexOf('authUser') !== -1) {
              uid   = item.value && item.value.uid;
              token = item.value && item.value.stsTokenManager &&
                      item.value.stsTokenManager.accessToken;
              break;
            }
          }
          SoocherBridge.postMessage(JSON.stringify({
            type: 'join_call', uid: uid, idToken: token, consultationId: cid
          }));
        };
        all.onerror = function() {
          SoocherBridge.postMessage(JSON.stringify({ type: 'error', message: 'IndexedDB read failed' }));
        };
      };
    } catch(e) {
      SoocherBridge.postMessage(JSON.stringify({ type: 'error', message: String(e) }));
    }
  }

  var origPush = history.pushState.bind(history);
  history.pushState = function(s, t, url) {
    origPush(s, t, url);
    if (url) checkPath(typeof url === 'string' ? url : (url.pathname || ''));
  };

  var origReplace = history.replaceState.bind(history);
  history.replaceState = function(s, t, url) {
    origReplace(s, t, url);
    if (url) checkPath(typeof url === 'string' ? url : (url.pathname || ''));
  };

  window.addEventListener('popstate', function() { checkPath(window.location.pathname); });
})();
''');
  }

  // ── Video call ───────────────────────────────────────────────────────────

  void _requestVideoCallData(String consultationId) {
    if (_joiningCall) return;
    final eid = consultationId.replaceAll("'", r"\'");
    _wvc.runJavaScript('''
(function() {
  var cid = '$eid';
  try {
    var req = indexedDB.open('firebaseLocalStorageDb', 1);
    req.onsuccess = function(e) {
      var all = e.target.result
                  .transaction(['firebaseLocalStorage'], 'readonly')
                  .objectStore('firebaseLocalStorage').getAll();
      all.onsuccess = function() {
        var uid = null, token = null;
        for (var i = 0; i < all.result.length; i++) {
          var item = all.result[i];
          if (item.fbase_key && item.fbase_key.indexOf('authUser') !== -1) {
            uid   = item.value && item.value.uid;
            token = item.value && item.value.stsTokenManager &&
                    item.value.stsTokenManager.accessToken;
            break;
          }
        }
        SoocherBridge.postMessage(JSON.stringify({
          type: 'join_call', uid: uid, idToken: token, consultationId: cid
        }));
      };
    };
  } catch(e) {
    SoocherBridge.postMessage(JSON.stringify({ type: 'error', message: String(e) }));
  }
})();
''');
  }

  // ── Bridge message handler ───────────────────────────────────────────────

  Future<void> _onBridgeMessage(JavaScriptMessage msg) async {
    try {
      final data = jsonDecode(msg.message) as Map<String, dynamic>;
      switch (data['type'] as String?) {
        case 'logout':
          _doSignOut();

        case 'login_detected':
          _handleLoginDetected();

        case 'join_call':
          if (_joiningCall) return;
          final cid = data['consultationId'] as String?;
          if (cid == null || cid.isEmpty) { _showSnack('Missing consultation ID.'); return; }
          final user = FirebaseAuth.instance.currentUser;
          if (user == null) { _showSnack('Not signed in.'); return; }
          setState(() => _joiningCall = true);
          user.getIdToken(true).then((tok) {
            if (tok == null) { setState(() => _joiningCall = false); _showSnack('Could not refresh token.'); return; }
            _openNativeVideoCall(user.uid, tok, cid);
          }).catchError((e) {
            setState(() => _joiningCall = false);
            _showSnack('Auth error: $e');
          });

        case 'date_picker':
          final fieldId = data['fieldId'] as String? ?? '';
          final current = data['currentValue'] as String? ?? '';
          DateTime initial = DateTime.now();
          if (current.isNotEmpty) {
            initial = DateTime.tryParse(current) ?? initial;
          }
          if (!mounted) return;
          final picked = await showDatePicker(
            context: context,
            initialDate: initial,
            firstDate: DateTime(1900),
            lastDate: DateTime(2100),
            builder: (ctx, child) => Theme(
              data: Theme.of(ctx).copyWith(
                colorScheme: const ColorScheme.light(
                  primary: Color(0xFF2E6DD4),
                  onPrimary: Colors.white,
                  surface: Colors.white,
                ),
              ),
              child: child!,
            ),
          );
          if (picked != null && fieldId.isNotEmpty) {
            final formatted =
                '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
            _setDateInputValue(fieldId, formatted);
          }

        case 'error':
          _showSnack('Error: ${data['message']}');
      }
    } catch (_) {}
  }

  Future<void> _openNativeVideoCall(String uid, String idToken, String cid) async {
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => VideoCallScreen(uid: uid, idToken: idToken, consultationId: cid),
    ));
    if (mounted) setState(() => _joiningCall = false);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFF2E6DD4),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _reload() {
    setState(() { _hasError = false; _loading = true; _signingIn = false; });
    _loadWithCustomToken();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _wvc.canGoBack()) _wvc.goBack();
        else SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _hasError ? _errorView() : WebViewWidget(controller: _wvc),
              if (_joiningCall)
                const ColoredBox(
                  color: Color(0x88000000),
                  child: Center(child: CircularProgressIndicator(
                      color: Color(0xFF2E6DD4))),
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
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.wifi_off_rounded, size: 64, color: Color(0xFF2E6DD4)),
            const SizedBox(height: 16),
            const Text('No connection',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A), letterSpacing: -0.3)),
            const SizedBox(height: 8),
            const Text('Check your internet connection\nand try again.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Color(0xFF64748B), height: 1.5)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _reload,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E6DD4),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                elevation: 0,
              ),
              child: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }
}
