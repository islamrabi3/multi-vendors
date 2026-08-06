import 'package:flutter/foundation.dart';

/// Whether "Sign in with Apple" should be offered here.
///
/// Apple's own guideline is the reason it exists at all: an iOS app that
/// offers any third-party sign-in must offer Apple's too. Nothing asks for it
/// anywhere else, and on Android it is a button most users cannot complete —
/// there is no system account to fall back on, so it drops into a web flow for
/// an Apple ID they may not have.
bool get supportsAppleSignIn =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;
