import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class SlideSosButton extends StatefulWidget {
  final VoidCallback onDispatch;

  const SlideSosButton({super.key, required this.onDispatch});

  @override
  State<SlideSosButton> createState() => _SlideSosButtonState();
}

class _SlideSosButtonState extends State<SlideSosButton> {
  static const double _height = 72;
  static const double _handleWidth = 124;

  double _progress = 0;
  double _maxDrag = 0;

  void _onDragUpdate(DragUpdateDetails details) {
    if (_maxDrag <= 0) return;
    setState(() {
      _progress = (_progress + details.delta.dx / _maxDrag).clamp(0.0, 1.0);
    });
  }

  Future<void> _onDragEnd() async {
    if (_progress >= 0.72) {
      setState(() => _progress = 1);
      widget.onDispatch();
      await Future.delayed(const Duration(milliseconds: 600));
    }
    if (mounted) setState(() => _progress = 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _maxDrag = constraints.maxWidth - _handleWidth - 8;
        final handleLeft = 4 + (_maxDrag * _progress);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: (_) => _onDragEnd(),
          child: Stack(
            children: [
              Container(
                height: _height,
                decoration: BoxDecoration(
                  color: AppColors.sosTrack,
                  borderRadius: BorderRadius.circular(_height / 2),
                  boxShadow: const [
                    BoxShadow(color: Color(0x11000000), blurRadius: 12, offset: Offset(0, 4)),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: _handleWidth + 8),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Slide for SOS',
                          style: TextStyle(
                            color: AppColors.sosRed,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.arrow_forward, size: 16, color: AppColors.sosRed),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: handleLeft,
                top: 4,
                bottom: 4,
                child: Container(
                  width: _handleWidth,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.sosRed,
                    borderRadius: BorderRadius.circular(40),
                    boxShadow: const [
                      BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3)),
                    ],
                  ),
                  child: const Text(
                    'SOS',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
