import 'package:flutter/material.dart';

const _kInk = Color(0xFF0F2E26);
const _kMint = Color(0xFF7DD3B9);

/// A branded, shareable summary card rendered to an image for the share sheet.
class MatchShareCard extends StatelessWidget {
  const MatchShareCard({
    super.key,
    required this.title,
    required this.battingTeam,
    required this.score,
    required this.line,
    required this.status,
  });

  /// "Team A v Team B"
  final String title;
  final String battingTeam;
  final String score; // "45/2"
  final String line; // "Over 6.2  -  CRR 7.10"
  final String status; // "LIVE" / "Result: ..."

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: _kInk,
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              style: const TextStyle(
                  color: _kMint, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 18),
          Text(battingTeam,
              style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 2),
          Text(score,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 44,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(line, style: const TextStyle(color: _kMint, fontSize: 14)),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(status,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
              const Text('Pitch',
                  style: TextStyle(
                      color: _kMint,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5)),
            ],
          ),
        ],
      ),
    );
  }
}
