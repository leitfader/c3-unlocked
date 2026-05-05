import 'package:flutter/material.dart';

const Color c3Black = Color(0xFF030303);
const Color c3Panel = Color(0xFF0B0B0D);
const Color c3PanelHigh = Color(0xFF151518);
const Color c3Cyan = Color(0xFFF4F4F4);
const Color c3Magenta = Color(0xFFC9C9C9);
const Color c3Lime = Color(0xFFFFFFFF);
const Color c3Amber = Color(0xFFA7A7A7);
const Color c3Text = Color(0xFFF2F2F2);
const Color c3Muted = Color(0xFF8A8A8A);

ThemeData buildC3Theme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: c3Cyan,
        brightness: Brightness.dark,
        surface: c3Black,
        primary: c3Cyan,
        secondary: c3Magenta,
        tertiary: c3Lime,
        error: const Color(0xFFE6E6E6),
      ).copyWith(
        surfaceContainerLow: const Color(0xFF070707),
        surfaceContainer: c3Panel,
        surfaceContainerHigh: c3PanelHigh,
        onSurface: c3Text,
        onSurfaceVariant: c3Muted,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: c3Black,
    fontFamily: 'Roboto',
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      },
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: c3Text,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: c3Panel.withValues(alpha: 0.94),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: c3Cyan.withValues(alpha: 0.18)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c3Panel.withValues(alpha: 0.96),
      indicatorColor: c3Cyan.withValues(alpha: 0.14),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.selected) ? c3Cyan : c3Muted,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? c3Cyan : c3Muted,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c3PanelHigh.withValues(alpha: 0.72),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c3Cyan.withValues(alpha: 0.18)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c3Cyan.withValues(alpha: 0.18)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: c3Cyan, width: 1.2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c3Cyan,
        foregroundColor: c3Black,
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c3Cyan,
        minimumSize: const Size(44, 44),
        side: BorderSide(color: c3Cyan.withValues(alpha: 0.38)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: c3Cyan,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textTheme: const TextTheme(
      headlineSmall: TextStyle(
        color: c3Text,
        fontSize: 28,
        height: 1.05,
        fontWeight: FontWeight.w900,
      ),
      titleLarge: TextStyle(
        color: c3Text,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
      titleMedium: TextStyle(
        color: c3Text,
        fontSize: 16,
        fontWeight: FontWeight.w800,
      ),
      bodyLarge: TextStyle(color: c3Text, fontSize: 15, height: 1.35),
      bodyMedium: TextStyle(color: c3Text, fontSize: 14, height: 1.35),
      bodySmall: TextStyle(color: c3Muted, fontSize: 12, height: 1.3),
      labelLarge: TextStyle(color: c3Text, fontWeight: FontWeight.w800),
      labelMedium: TextStyle(color: c3Muted, fontWeight: FontWeight.w700),
    ),
  );
}

class C3Background extends StatelessWidget {
  const C3Background({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF030303),
            Color(0xFF09090B),
            Color(0xFF111113),
            Color(0xFF030303),
          ],
        ),
      ),
      child: Stack(
        children: <Widget>[
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

class C3ScrollBehavior extends MaterialScrollBehavior {
  const C3ScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = c3Cyan.withValues(alpha: 0.045)
      ..strokeWidth = 1;
    const gap = 32.0;
    for (var x = 0.0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
