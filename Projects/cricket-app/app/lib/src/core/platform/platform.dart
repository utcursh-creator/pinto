import 'package:flutter/material.dart';

/// Whether to render the iOS (Cupertino) look. Uses Theme.of(context).platform
/// (NOT dart:io) so it is overridable in tests via
/// debugDefaultTargetPlatformOverride and stays correct on web.
bool isCupertino(BuildContext context) =>
    Theme.of(context).platform == TargetPlatform.iOS;
