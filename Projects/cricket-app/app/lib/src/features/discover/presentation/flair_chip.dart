import 'package:flutter/material.dart';

import '../data/discover_models.dart';

/// The colored flair pill (loser pays = amber, practice = grey, corporate =
/// blue). Shared across the feed, post detail, composer, and my-posts.
class FlairChip extends StatelessWidget {
  const FlairChip(this.flair, {super.key});

  final String? flair;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (flair) {
      'loser_pays' => (const Color(0xFFFAEEDA), const Color(0xFF854F0B)),
      'corporate_match' => (const Color(0xFFE6F1FB), const Color(0xFF0C447C)),
      'practice_match' => (const Color(0xFFD3D1C7), const Color(0xFF444441)),
      _ => (const Color(0xFFEDEDED), const Color(0xFF555555)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        LfLabels.flair(flair),
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
