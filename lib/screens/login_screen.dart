import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'web_view_screen.dart';

// ── Country data ─────────────────────────────────────────────────────────────

class _Country {
  const _Country(this.name, this.flag, this.dialCode);
  final String name;
  final String flag;
  final String dialCode;
}

const _countries = [
  _Country('India', '🇮🇳', '+91'),
  _Country('United States', '🇺🇸', '+1'),
  _Country('United Kingdom', '🇬🇧', '+44'),
  _Country('United Arab Emirates', '🇦🇪', '+971'),
  _Country('Saudi Arabia', '🇸🇦', '+966'),
  _Country('Canada', '🇨🇦', '+1'),
  _Country('Australia', '🇦🇺', '+61'),
  _Country('Singapore', '🇸🇬', '+65'),
  _Country('Malaysia', '🇲🇾', '+60'),
  _Country('Germany', '🇩🇪', '+49'),
  _Country('France', '🇫🇷', '+33'),
  _Country('Nepal', '🇳🇵', '+977'),
  _Country('Bangladesh', '🇧🇩', '+880'),
  _Country('Sri Lanka', '🇱🇰', '+94'),
  _Country('Pakistan', '🇵🇰', '+92'),
];

// ── Main screen ───────────────────────────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  static const _primary = Color(0xFF2E6DD4);

  String _step = 'phone'; // 'phone' | 'otp' | 'email'

  _Country _selectedCountry = _countries.first;

  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  final _phoneFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  // OTP is managed inside _OtpStep; we only track the current code here
  String _otpCode = '';

  bool _loading = false;
  String? _error;
  bool _passwordVisible = false;

  String? _pendingVerificationId;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _setError(String? e) => setState(() => _error = e);
  void _setLoading(bool v) => setState(() => _loading = v);

  // ── Country picker ────────────────────────────────────────────────────────

  void _showCountryPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Select Country',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _countries.length,
              itemBuilder: (_, i) {
                final c = _countries[i];
                final selected =
                    c.dialCode == _selectedCountry.dialCode &&
                    c.name == _selectedCountry.name;
                return ListTile(
                  leading: Text(c.flag, style: const TextStyle(fontSize: 24)),
                  title: Text(
                    c.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: Text(
                    c.dialCode,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? const Color(0xFF2E6DD4)
                          : const Color(0xFF64748B),
                    ),
                  ),
                  selected: selected,
                  selectedTileColor: const Color(0xFFEDF4FF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onTap: () {
                    setState(() => _selectedCountry = c);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  // ── Phone OTP ─────────────────────────────────────────────────────────────

  Future<void> _sendOtp() async {
    final number = _phoneCtrl.text.trim();
    if (number.isEmpty) {
      _setError('Enter your phone number');
      return;
    }
    _setError(null);
    _setLoading(true);
    final fullPhone = '${_selectedCountry.dialCode}$number';
    try {
      // await FirebaseAuth.instance.setSettings(forceRecaptchaFlow: true);
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: fullPhone,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (cred) async {
          await FirebaseAuth.instance.signInWithCredential(cred);
          _goToApp();
        },
        verificationFailed: (e) {
          _setLoading(false);
          _setError(e.message ?? 'Verification failed');
        },
        codeSent: (verificationId, _) {
          _setLoading(false);
          setState(() {
            _step = 'otp';
            _pendingVerificationId = verificationId;
          });
        },
        codeAutoRetrievalTimeout: (_) {},
      );
    } catch (e) {
      _setLoading(false);
      _setError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _verifyOtp() async {
    if (_otpCode.length < 6) {
      _setError('Enter the 6-digit code');
      return;
    }
    _setError(null);
    _setLoading(true);
    try {
      final cred = PhoneAuthProvider.credential(
        verificationId: _pendingVerificationId!,
        smsCode: _otpCode,
      );
      await FirebaseAuth.instance.signInWithCredential(cred);
      _goToApp();
    } on FirebaseAuthException catch (e) {
      _setLoading(false);
      _setError(e.message ?? 'Invalid code');
    } catch (e) {
      _setLoading(false);
      _setError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  // ── Email / Password ──────────────────────────────────────────────────────

  Future<void> _signInWithEmail() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty) {
      _setError('Enter your email');
      return;
    }
    if (password.isEmpty) {
      _setError('Enter your password');
      return;
    }
    _setError(null);
    _setLoading(true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      _goToApp();
    } on FirebaseAuthException catch (e) {
      _setLoading(false);
      _setError(_friendlyError(e));
    } catch (e) {
      _setLoading(false);
      _setError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  String _friendlyError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      default:
        return e.message ?? 'Authentication failed.';
    }
  }

  void _goToApp() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const WebViewScreen(),
        transitionDuration: const Duration(milliseconds: 400),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  String get _titleText {
    if (_step == 'otp') return 'Verify your\nnumber';
    if (_step == 'email') return 'Sign in with\nemail';
    return 'Welcome back,\nDoctor';
  }

  String get _subtitleText {
    if (_step == 'otp') {
      return 'Enter the 6-digit code sent to\n${_selectedCountry.dialCode} ${_phoneCtrl.text.trim()}';
    }
    if (_step == 'email') return 'Use your email and password to sign in';
    return 'Sign in to manage your practice';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: FadeTransition(
        opacity: _fade,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Brand
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _primary,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: _primary.withValues(alpha: 0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.medical_services_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Soocher',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          'FOR DOCTORS',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: _primary,
                            letterSpacing: 3,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 48),

                // Title
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Column(
                    key: ValueKey(_step),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _titleText,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.5,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _subtitleText,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey.shade600,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // Form
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  child: _step == 'phone'
                      ? _PhoneStep(
                          key: const ValueKey('phone'),
                          controller: _phoneCtrl,
                          focusNode: _phoneFocus,
                          loading: _loading,
                          error: _error,
                          country: _selectedCountry,
                          onCountryTap: _showCountryPicker,
                          onSend: _sendOtp,
                          onEmailTap: () => setState(() {
                            _step = 'email';
                            _error = null;
                            Future.delayed(
                              const Duration(milliseconds: 150),
                              () => _emailFocus.requestFocus(),
                            );
                          }),
                        )
                      : _step == 'otp'
                      ? _OtpStep(
                          key: const ValueKey('otp'),
                          loading: _loading,
                          error: _error,
                          onCodeChanged: (code) =>
                              setState(() => _otpCode = code),
                          onVerify: _verifyOtp,
                          onBack: () => setState(() {
                            _step = 'phone';
                            _error = null;
                            _otpCode = '';
                          }),
                          onResend: () {
                            setState(() {
                              _otpCode = '';
                              _error = null;
                              _step = 'phone';
                            });
                            _sendOtp();
                          },
                        )
                      : _EmailStep(
                          key: const ValueKey('email'),
                          emailCtrl: _emailCtrl,
                          passwordCtrl: _passwordCtrl,
                          emailFocus: _emailFocus,
                          passwordFocus: _passwordFocus,
                          loading: _loading,
                          error: _error,
                          passwordVisible: _passwordVisible,
                          onTogglePassword: () => setState(
                            () => _passwordVisible = !_passwordVisible,
                          ),
                          onSubmit: _signInWithEmail,
                          onBack: () => setState(() {
                            _step = 'phone';
                            _error = null;
                            _emailCtrl.clear();
                            _passwordCtrl.clear();
                          }),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Phone step ────────────────────────────────────────────────────────────────

class _PhoneStep extends StatelessWidget {
  const _PhoneStep({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.loading,
    required this.error,
    required this.country,
    required this.onCountryTap,
    required this.onSend,
    required this.onEmailTap,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool loading;
  final String? error;
  final _Country country;
  final VoidCallback onCountryTap;
  final VoidCallback onSend;
  final VoidCallback onEmailTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: error != null
                  ? const Color(0xFFE11D48)
                  : const Color(0xFFE2E8F0),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: onCountryTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 16,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(
                      right: BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(country.flag, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 6),
                      Text(
                        country.dialCode,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: Color(0xFF94A3B8),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                  decoration: InputDecoration(
                    hintText: '99999 99999',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade400,
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 16,
                    ),
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ),
            ],
          ),
        ),
        if (error != null) _ErrorText(error!),
        const SizedBox(height: 16),
        _PrimaryButton(label: 'Send OTP', loading: loading, onTap: onSend),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: Divider(color: Colors.grey.shade300)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'or',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              ),
            ),
            Expanded(child: Divider(color: Colors.grey.shade300)),
          ],
        ),
        const SizedBox(height: 20),
        _SecondaryButton(
          icon: Icons.email_rounded,
          label: 'Continue with Email',
          onTap: onEmailTap,
        ),
        const SizedBox(height: 32),
        Center(
          child: Text(
            'By signing in you agree to our Terms & Privacy Policy',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade400,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

// ── OTP step — individual digit boxes ────────────────────────────────────────

class _OtpStep extends StatefulWidget {
  const _OtpStep({
    super.key,
    required this.loading,
    required this.error,
    required this.onCodeChanged,
    required this.onVerify,
    required this.onBack,
    required this.onResend,
  });

  final bool loading;
  final String? error;
  final ValueChanged<String> onCodeChanged;
  final VoidCallback onVerify;
  final VoidCallback onBack;
  final VoidCallback onResend;

  @override
  State<_OtpStep> createState() => _OtpStepState();
}

class _OtpStepState extends State<_OtpStep> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _cursorTimer;
  bool _cursorVisible = true;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onTextChange);
    _focus.addListener(_onFocusChange);
    _cursorTimer = Timer.periodic(const Duration(milliseconds: 530), (_) {
      if (mounted) setState(() => _cursorVisible = !_cursorVisible);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _onTextChange() {
    setState(() {});
    widget.onCodeChanged(_ctrl.text);
    if (_ctrl.text.length == 6 && !widget.loading) widget.onVerify();
  }

  void _onFocusChange() => setState(() {});

  @override
  void dispose() {
    _cursorTimer?.cancel();
    _ctrl.removeListener(_onTextChange);
    _focus.removeListener(_onFocusChange);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final code = _ctrl.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tap anywhere on the digit row to focus
        GestureDetector(
          onTap: () => _focus.requestFocus(),
          behavior: HitTestBehavior.opaque,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Hidden text field — receives actual keyboard input
              SizedBox(
                height: 1,
                child: Opacity(
                  opacity: 0,
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    enabled: !widget.loading,
                    decoration: const InputDecoration(counterText: ''),
                  ),
                ),
              ),
              // Visible 6-box row
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(6, (i) {
                    final digit = i < code.length ? code[i] : '';
                    final isActive = i == code.length && _focus.hasFocus;
                    return _DigitBox(
                      digit: digit,
                      isActive: isActive,
                      cursorVisible: _cursorVisible,
                      hasError: widget.error != null,
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
        if (widget.error != null) _ErrorText(widget.error!),
        const SizedBox(height: 20),
        _PrimaryButton(
          label: 'Verify & Sign In',
          loading: widget.loading,
          onTap: widget.onVerify,
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              onPressed: widget.loading ? null : widget.onBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Change number'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF64748B),
              ),
            ),
            TextButton(
              onPressed: widget.loading ? null : widget.onResend,
              child: const Text(
                'Resend OTP',
                style: TextStyle(
                  color: Color(0xFF2E6DD4),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Digit box ─────────────────────────────────────────────────────────────────

class _DigitBox extends StatelessWidget {
  const _DigitBox({
    required this.digit,
    required this.isActive,
    required this.cursorVisible,
    required this.hasError,
  });

  final String digit;
  final bool isActive;
  final bool cursorVisible;
  final bool hasError;

  static const _primary = Color(0xFF2E6DD4);

  @override
  Widget build(BuildContext context) {
    final filled = digit.isNotEmpty;
    final Color borderColor = hasError
        ? const Color(0xFFE11D48)
        : isActive
        ? _primary
        : filled
        ? const Color(0xFFBCD4FF)
        : const Color(0xFFE2E8F0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 46,
      height: 58,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFEDF4FF) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: isActive ? 2 : 1.5),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: _primary.withValues(alpha: 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: Center(
        child: filled
            ? Text(
                digit,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: hasError
                      ? const Color(0xFFE11D48)
                      : const Color(0xFF0F172A),
                ),
              )
            : isActive && cursorVisible
            ? Container(
                width: 2,
                height: 24,
                decoration: BoxDecoration(
                  color: _primary,
                  borderRadius: BorderRadius.circular(1),
                ),
              )
            : null,
      ),
    );
  }
}

// ── Email step ────────────────────────────────────────────────────────────────

class _EmailStep extends StatelessWidget {
  const _EmailStep({
    super.key,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.emailFocus,
    required this.passwordFocus,
    required this.loading,
    required this.error,
    required this.passwordVisible,
    required this.onTogglePassword,
    required this.onSubmit,
    required this.onBack,
  });

  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final FocusNode emailFocus;
  final FocusNode passwordFocus;
  final bool loading;
  final String? error;
  final bool passwordVisible;
  final VoidCallback onTogglePassword;
  final VoidCallback onSubmit;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InputField(
          controller: emailCtrl,
          focusNode: emailFocus,
          hint: 'doctor@example.com',
          icon: Icons.email_rounded,
          keyboardType: TextInputType.emailAddress,
          onSubmitted: (_) => passwordFocus.requestFocus(),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: error != null
                  ? const Color(0xFFE11D48)
                  : const Color(0xFFE2E8F0),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: passwordCtrl,
            focusNode: passwordFocus,
            obscureText: !passwordVisible,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
            ),
            decoration: InputDecoration(
              hintText: 'Password',
              hintStyle: TextStyle(
                color: Colors.grey.shade400,
                fontWeight: FontWeight.w400,
              ),
              prefixIcon: const Icon(
                Icons.lock_rounded,
                color: Color(0xFF2E6DD4),
                size: 20,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  passwordVisible
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: Colors.grey.shade400,
                  size: 20,
                ),
                onPressed: onTogglePassword,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
            onSubmitted: (_) => onSubmit(),
          ),
        ),
        if (error != null) _ErrorText(error!),
        const SizedBox(height: 16),
        _PrimaryButton(label: 'Sign In', loading: loading, onTap: onSubmit),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: loading ? null : onBack,
          icon: const Icon(Icons.arrow_back_rounded, size: 16),
          label: const Text('Use phone instead'),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF64748B)),
        ),
      ],
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _InputField extends StatelessWidget {
  const _InputField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Color(0xFF0F172A),
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: Colors.grey.shade400,
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: Icon(icon, color: const Color(0xFF2E6DD4), size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
        onSubmitted: onSubmitted,
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        style: const TextStyle(color: Color(0xFFE11D48), fontSize: 13),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.loading,
    required this.onTap,
  });

  final String label;
  final bool loading;
  final VoidCallback onTap;

  static const _primary = Color(0xFF2E6DD4);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 56,
        decoration: BoxDecoration(
          color: loading ? _primary.withValues(alpha: 0.7) : _primary,
          borderRadius: BorderRadius.circular(100),
          boxShadow: loading
              ? []
              : [
                  BoxShadow(
                    color: _primary.withValues(alpha: 0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFF2E6DD4), size: 20),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
