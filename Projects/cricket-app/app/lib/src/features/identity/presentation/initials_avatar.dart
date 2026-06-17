import 'package:flutter/material.dart';

import '../../../core/theme/brand_tokens.dart';
import '../data/identity_labels.dart';

/// A circular avatar showing a person's initials over the brand-teal tint.
/// (Photo upload is a later slice; this stands in for photo_url.)
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({required this.name, this.radius = 28, super.key});

  final String? name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: BrandTokens.tealLight,
      child: Text(
        IdentityLabels.initials(name),
        style: TextStyle(
          color: BrandTokens.teal,
          fontWeight: FontWeight.w600,
          fontSize: radius * 0.7,
        ),
      ),
    );
  }
}
