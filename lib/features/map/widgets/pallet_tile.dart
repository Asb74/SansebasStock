import 'package:flutter/material.dart';

class PalletTile extends StatelessWidget {
  const PalletTile({
    super.key,
    required this.ocupado,
    this.p,
  });

  final bool ocupado;
  final String? p;

  @override
  Widget build(BuildContext context) {
    final background = ocupado ? const Color(0xFF8BC34A) : const Color(0xFFF2F3F5);
    final border = ocupado ? const Color(0xFF5E8E2E) : const Color(0xFFB9C1CC);

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: border, width: 2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: p == null
            ? const SizedBox.expand()
            : Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    p!,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
