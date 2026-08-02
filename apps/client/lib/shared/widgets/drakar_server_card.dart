import 'package:flutter/material.dart';

/// Static MVP server card (France / Paris #1). No chevron yet.
class DrakarServerCard extends StatelessWidget {
  const DrakarServerCard({
    super.key,
    required this.connected,
  });

  final bool connected;

  static const String flagAsset = 'assets/drakar/flag_france.png';
  static const Color _online = Color(0xFF1CCB58);
  static const Color _offline = Color(0xFF6A6A6A);
  // Darker well behind the flag (as on the Iceland ref).
  static const Color _flagWell = Color(0xFF050505);
  static const Color _cardFill = Color(0xFF0A0A0A);

  @override
  Widget build(BuildContext context) {
    final signalColor = connected ? _online : _offline;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _cardFill,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: _flagWell,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: ColoredBox(
                  color: _flagWell,
                  child: Image.asset(
                    flagAsset,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'France',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Paris #1',
                    style: TextStyle(
                      color: Color(0xFF8E8E8E),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
            _SignalBars(color: signalColor),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.color});

  final Color color;

  static const List<double> _heights = [8, 12, 16, 20];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 22,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final h in _heights)
            Container(
              width: 4,
              height: h,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
        ],
      ),
    );
  }
}
