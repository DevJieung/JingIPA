import 'package:flutter/material.dart';
import 'brand_art.dart';
export 'brand_art.dart';
export 'card_grid.dart';

const ink = Color(0xFF203D35);
const muted = Color(0xFF5E7069);
const paper = Color(0xFFF2F5F3);
const lime = Color(0xFFDCECE2);
const forest = Color(0xFF244F43);
const line = Color(0xFFDDE5E0);
const orange = Color(0xFFAF4938);
const sageSurface = Color(0xFFEAF2ED);
const peachSurface = Color(0xFFFFF0EB);
const recruitingSurface = Color(0xFFFFE4C7);
const historySurface = Color(0xFFE0E5E2);
const historyCardSurface = Color(0xFFEBEEEC);
const historyInk = Color(0xFF4F6057);
const channelOpenSurface = Color(0xFFF1F4F2);
// Locked actions (e.g. new round while one is running) read as unavailable.
const lockedSurface = Color(0xFF5B635F);
// Pod outcome tags on the storefront cards.
const formedTagSurface = Color(0xFFD3EBDB);
const formedTagInk = Color(0xFF1D5B3C);
const pendingTagSurface = Color(0xFFFFE1C2);
const pendingTagInk = Color(0xFF8F4310);
// Destructive text actions such as blowing up the running round.
const dangerInk = Color(0xFFC62828);
const actionHeight = 54.0;

ThemeData appTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'NotoSansKR',
  fontFamilyFallback: const ['NotoEmoji'],
  scaffoldBackgroundColor: paper,
  colorScheme: ColorScheme.fromSeed(
    seedColor: forest,
    surface: Colors.white,
    onSurface: ink,
    onPrimary: Colors.white,
    primary: forest,
    secondary: lime,
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 32,
      height: 1.35,
      fontWeight: FontWeight.w800,
      letterSpacing: -1,
      color: ink,
    ),
    headlineMedium: TextStyle(
      fontSize: 27,
      height: 1.4,
      fontWeight: FontWeight.w800,
      letterSpacing: -.7,
      color: ink,
    ),
    titleLarge: TextStyle(
      fontSize: 21,
      height: 1.4,
      fontWeight: FontWeight.w700,
      letterSpacing: -.6,
      color: ink,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      letterSpacing: -.4,
      color: ink,
    ),
    bodyLarge: TextStyle(fontSize: 16, height: 1.55, color: ink),
    bodyMedium: TextStyle(fontSize: 14, height: 1.55, color: ink),
    bodySmall: TextStyle(fontSize: 12, height: 1.5, color: muted),
  ),
  materialTapTargetSize: MaterialTapTargetSize.padded,
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      minimumSize: const Size(48, 48),
      textStyle: const TextStyle(
        fontFamily: 'NotoSansKR',
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
  listTileTheme: const ListTileThemeData(
    iconColor: forest,
    textColor: ink,
    minVerticalPadding: 12,
    contentPadding: EdgeInsets.symmetric(horizontal: 16),
  ),
  expansionTileTheme: const ExpansionTileThemeData(
    shape: Border(),
    collapsedShape: Border(),
    iconColor: muted,
    collapsedIconColor: muted,
    tilePadding: EdgeInsets.symmetric(horizontal: 16),
    childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(double.infinity, actionHeight),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      elevation: 0,
      textStyle: const TextStyle(
        fontFamily: 'NotoSansKR',
        fontWeight: FontWeight.w700,
        fontSize: 15,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(double.infinity, actionHeight),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      side: const BorderSide(color: line),
      foregroundColor: forest,
      backgroundColor: Colors.transparent,
      textStyle: const TextStyle(
        fontWeight: FontWeight.w700,
        fontFamily: 'NotoSansKR',
        fontSize: 14,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.all(17),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: forest, width: 1.5),
    ),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: paper,
    foregroundColor: forest,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    titleTextStyle: TextStyle(
      fontFamily: 'NotoSansKR',
      fontSize: 19,
      fontWeight: FontWeight.w800,
      color: forest,
    ),
  ),
  bottomSheetTheme: const BottomSheetThemeData(
    constraints: BoxConstraints(maxWidth: 640),
    backgroundColor: paper,
    surfaceTintColor: Colors.transparent,
    dragHandleColor: line,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
  ),
  tabBarTheme: const TabBarThemeData(
    labelColor: forest,
    unselectedLabelColor: muted,
    indicatorColor: orange,
    dividerColor: line,
    indicatorSize: TabBarIndicatorSize.tab,
    labelStyle: TextStyle(
      fontFamily: 'NotoSansKR',
      fontWeight: FontWeight.w700,
      fontSize: 14,
    ),
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    indicatorColor: sageSurface,
    labelTextStyle: WidgetStateProperty.resolveWith(
      (states) => TextStyle(
        fontFamily: 'NotoSansKR',
        fontSize: 12,
        fontWeight: states.contains(WidgetState.selected)
            ? FontWeight.w800
            : FontWeight.w500,
        color: states.contains(WidgetState.selected) ? forest : muted,
      ),
    ),
    iconTheme: WidgetStateProperty.resolveWith(
      (states) => IconThemeData(
        color: states.contains(WidgetState.selected) ? forest : muted,
        size: 23,
      ),
    ),
  ),
  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: forest,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  ),
  dividerColor: line,
);

class Tag extends StatelessWidget {
  const Tag(
    this.text, {
    this.color = lime,
    this.foreground = forest,
    super.key,
  });
  final String text;
  final Color color, foreground;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(50),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: foreground,
      ),
    ),
  );
}

class Surface extends StatelessWidget {
  const Surface({
    required this.child,
    this.color = Colors.white,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });
  final Widget child;
  final Color color;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Material(
    color: color,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: line),
    ),
    child: Padding(padding: padding, child: child),
  );
}

/// Shared title placement and help target across the four main destinations.
class PageHeading extends StatelessWidget {
  const PageHeading({required this.title, required this.onHelp, super.key});
  final String title;
  final VoidCallback onHelp;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(color: orange),
        ),
      ),
      TextButton.icon(
        key: const Key('open-tutorial'),
        onPressed: onHelp,
        icon: const Icon(Icons.help_outline_rounded, size: 18),
        label: const Text('도움말'),
      ),
    ],
  );
}

/// Secondary settings read as a list, with one full-width touch target per row.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    super.key,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, size: 22),
    title: Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    subtitle: subtitle == null
        ? null
        : Text(subtitle!, style: const TextStyle(fontSize: 12, color: muted)),
    trailing: const Icon(Icons.chevron_right_rounded, color: muted, size: 20),
    onTap: onTap,
  );
}

class LunchArt extends StatelessWidget {
  const LunchArt({this.size = 140, super.key});
  final double size;
  @override
  Widget build(BuildContext context) => ElephantArt(size: size);
}

class BrandMark extends StatelessWidget {
  const BrandMark({this.light = false, super.key});
  final bool light;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const ElephantArt(size: 34, headOnly: true),
      const SizedBox(width: 6),
      Text(
        '먹끼리',
        style: TextStyle(
          fontSize: 25,
          height: 1.2,
          letterSpacing: -1.2,
          fontWeight: FontWeight.w900,
          color: light ? Colors.white : forest,
        ),
      ),
    ],
  );
}

class BrandHeading extends StatelessWidget {
  const BrandHeading({
    required this.title,
    required this.subtitle,
    required this.eyebrow,
    this.scene = ElephantScene.greeting,
    super.key,
  });
  final String title, subtitle, eyebrow;
  final ElephantScene scene;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        eyebrow,
        style: const TextStyle(
          color: orange,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          const SizedBox(width: 8),
          ElephantArt(size: 70, scene: scene),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        subtitle,
        style: const TextStyle(color: muted, fontSize: 12, height: 1.8),
      ),
    ],
  );
}
