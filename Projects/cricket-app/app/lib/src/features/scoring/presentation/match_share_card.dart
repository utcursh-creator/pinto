import 'package:flutter/material.dart';

const _kInk = Color(0xFF0F2E26);
const _kMint = Color(0xFF7DD3B9);

/// MISS-9: one innings' full batting + bowling card for [FullScorecardCard].
class ScorecardInningsData {
  const ScorecardInningsData({
    required this.teamName,
    required this.total,
    required this.over,
    required this.batting,
    required this.bowling,
  });

  final String teamName;
  final String total; // "152/6"
  final String over; // "20.0"
  /// Rows: [name, R, B, 4s, 6s]
  final List<List<String>> batting;
  /// Rows: [name, O, M, R, W]
  final List<List<String>> bowling;
}

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

/// MISS-9: the FULL scorecard (every innings' batting + bowling card) as one
/// tall, branded, shareable image.
class FullScorecardCard extends StatelessWidget {
  const FullScorecardCard({
    super.key,
    required this.title,
    required this.resultLine,
    required this.innings,
  });

  final String title; // "Team A v Team B"
  final String resultLine; // "Kings won by 8 runs." (or status)
  final List<ScorecardInningsData> innings;

  static const _head = TextStyle(
      color: _kMint, fontSize: 11, fontWeight: FontWeight.w700);
  static const _cell = TextStyle(color: Colors.white, fontSize: 12);

  Widget _row(List<String> cells, {TextStyle style = _cell}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(flex: 5, child: Text(cells[0], style: style, maxLines: 1,
                overflow: TextOverflow.ellipsis)),
            for (var i = 1; i < cells.length; i++)
              Expanded(
                  flex: 2,
                  child:
                      Text(cells[i], style: style, textAlign: TextAlign.right)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      padding: const EdgeInsets.all(20),
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
          const SizedBox(height: 4),
          Text(resultLine,
              style: const TextStyle(
                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          for (final inn in innings) ...[
            const SizedBox(height: 14),
            Text('${inn.teamName}  ${inn.total} (${inn.over})',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            _row(const ['Batter', 'R', 'B', '4s', '6s'], style: _head),
            for (final b in inn.batting) _row(b),
            const SizedBox(height: 6),
            _row(const ['Bowler', 'O', 'M', 'R', 'W'], style: _head),
            for (final b in inn.bowling) _row(b),
          ],
          const SizedBox(height: 14),
          const Align(
            alignment: Alignment.centerRight,
            child: Text('Pitch',
                style: TextStyle(
                    color: _kMint,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5)),
          ),
        ],
      ),
    );
  }
}
