import 'package:flutter/material.dart';

import '../../../core/ui/storage_image_url.dart';

import '../../../core/theme/brand_tokens.dart';
import '../data/identity_labels.dart';

/// A circular avatar. Shows the person's/team's photo when [photoUrl] is set,
/// falling back to their initials over the brand-teal tint.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({
    required this.name,
    this.photoUrl,
    this.radius = 28,
    super.key,
  });

  final String? name;
  final String? photoUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    return CircleAvatar(
      radius: radius,
      backgroundColor: BrandTokens.tealLight,
      foregroundImage: hasPhoto
          ? NetworkImage(resolveStorageUrl(photoUrl)!)
          : null,
      // Initials remain as the fallback if the image fails to load.
      child: hasPhoto
          ? null
          : Text(
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
