import 'package:ariami_mobile/widgets/common/adaptive_marquee_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildSubject({
    required String text,
    required double width,
    TextStyle? style,
    double height = 24,
    double velocity = 30.0,
    Duration startPause = const Duration(milliseconds: 1500),
    double gapWidth = 48.0,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: AdaptiveMarqueeText(
            text: text,
            style: style ?? const TextStyle(fontSize: 16),
            height: height,
            velocity: velocity,
            startPause: startPause,
            gapWidth: gapWidth,
          ),
        ),
      ),
    );
  }

  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
  }

  Finder findMarqueeTransform() {
    return find.descendant(
      of: find.byType(ClipRect),
      matching: find.byType(Transform),
    );
  }

  group('AdaptiveMarqueeText', () {
    test('textOverflows returns false when text fits', () {
      const style = TextStyle(fontSize: 16);
      const scaler = TextScaler.linear(1);

      expect(
        AdaptiveMarqueeText.textOverflows(
          text: 'Short title',
          style: style,
          textScaler: scaler,
          maxWidth: 300,
        ),
        isFalse,
      );
    });

    test('textOverflows returns true when text is wider than container', () {
      const style = TextStyle(fontSize: 16);
      const scaler = TextScaler.linear(1);
      const longText =
          '(There\'s No Place Like) Home for the Holidays - Extended Version';

      expect(
        AdaptiveMarqueeText.textOverflows(
          text: longText,
          style: style,
          textScaler: scaler,
          maxWidth: 120,
        ),
        isTrue,
      );
    });

    testWidgets('renders Text for short content that fits', (tester) async {
      await tester.pumpWidget(
        buildSubject(text: 'Short title', width: 300),
      );
      await tester.pump();

      expect(find.byType(Text), findsOneWidget);
      expect(find.byType(ClipRect), findsNothing);
      expect(find.text('Short title'), findsOneWidget);
    });

    testWidgets('renders two text copies for seamless loop with long content',
        (tester) async {
      const style = TextStyle(fontSize: 16);
      const longText =
          '(There\'s No Place Like) Home for the Holidays - Extended Version';
      const containerWidth = 120.0;
      final textWidth = AdaptiveMarqueeText.measureTextWidth(
        text: longText,
        style: style,
        textScaler: const TextScaler.linear(1),
      );

      await tester.pumpWidget(
        buildSubject(
          text: longText,
          width: containerWidth,
          style: style,
        ),
      );
      await tester.pump();

      expect(find.byType(ClipRect), findsOneWidget);
      // Spotify-style: two copies of the text for seamless looping
      expect(find.text(longText), findsNWidgets(2));

      // With OverflowBox, the Text widget lays out at its natural, unconstrained width,
      // which is greater than or equal to textWidth (preventing truncation).
      final textWidgets = tester.widgetList<Text>(find.text(longText));
      for (final textWidget in textWidgets) {
        final size = tester.getSize(find.byWidget(textWidget));
        expect(size.width, greaterThanOrEqualTo(textWidth));
      }

      // Initially no translation (before pause completes)
      final transform = tester.widget<Transform>(findMarqueeTransform());
      expect(transform.transform.getTranslation().x, 0);

      await disposeTree(tester);
    });

    testWidgets('scrolls with two text copies for continuous loop effect',
        (tester) async {
      const longText =
          'Jingle Jingle Jingle (From "Rudolph the Red-Nosed Reindeer")';

      await tester.pumpWidget(
        buildSubject(text: longText, width: 120),
      );
      await tester.pump();

      // Two copies for seamless loop
      expect(find.text(longText), findsNWidgets(2));
      expect(find.byType(Text), findsNWidgets(2));

      // After initial pause completes, scrolling should begin
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump(const Duration(milliseconds: 100));
      final transform = tester.widget<Transform>(findMarqueeTransform());
      expect(transform.transform.getTranslation().x, lessThan(0));

      await disposeTree(tester);
    });

    testWidgets('resets scroll position when text changes', (tester) async {
      const firstText =
          'First very long song title that should definitely overflow';
      const secondText =
          'Second very long song title that should definitely overflow';

      await tester.pumpWidget(
        buildSubject(text: firstText, width: 100),
      );
      await tester.pump();

      await tester.pump(const Duration(seconds: 5));
      await tester.pump();

      await tester.pumpWidget(
        buildSubject(text: secondText, width: 100),
      );
      await tester.pump();
      await tester.pump();

      final transform = tester.widget<Transform>(findMarqueeTransform());
      expect(transform.transform.getTranslation().x, 0);
      // Two copies for seamless loop
      expect(find.text(secondText), findsNWidgets(2));

      await disposeTree(tester);
    });

    testWidgets('scrolls full loop distance (textWidth + gapWidth)',
        (tester) async {
      const style = TextStyle(fontSize: 16);
      const scaler = TextScaler.linear(1);
      const longText = 'Let It Snow! Let It Snow! Let It Snow!';
      const containerWidth = 120.0;
      const gapWidth = 48.0;

      final textWidth = AdaptiveMarqueeText.measureTextWidth(
        text: longText,
        style: style,
        textScaler: scaler,
      );
      expect(textWidth, greaterThan(containerWidth));

      // Use moderate velocity so animation takes ~2s per cycle
      await tester.pumpWidget(
        buildSubject(
          text: longText,
          width: containerWidth,
          style: style,
          velocity: 100,
          gapWidth: gapWidth,
          startPause: const Duration(milliseconds: 100),
        ),
      );
      await tester.pump();

      // Wait for initial pause
      await tester.pump(const Duration(milliseconds: 150));

      // Animation should now be running. Sample at a point partway through.
      await tester.pump(const Duration(milliseconds: 500));

      final translationX = tester
          .widget<Transform>(findMarqueeTransform())
          .transform
          .getTranslation()
          .x;

      // With continuous loop, scroll distance is textWidth + gapWidth
      // Translation should be negative (scrolling left) and within range
      final expectedScrollDistance = textWidth + gapWidth;
      expect(translationX.abs(), lessThanOrEqualTo(expectedScrollDistance));
      expect(translationX, lessThanOrEqualTo(0));

      await disposeTree(tester);
    });

    testWidgets('scroll keeps progressing across many parent rebuilds',
        (tester) async {
      const longText =
          'Jingle Jingle Jingle (From "Rudolph the Red-Nosed Reindeer")';

      final hostKey = GlobalKey<_RebuildingHostState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 120,
              child: _RebuildingHost(
                key: hostKey,
                builder: (context) => AdaptiveMarqueeText(
                  text: longText,
                  style: const TextStyle(fontSize: 16),
                  height: 24,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Let the initial 1.5s pause complete and the scroll get going.
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump(const Duration(milliseconds: 400));

      final beforeRebuildsX = tester
          .widget<Transform>(findMarqueeTransform())
          .transform
          .getTranslation()
          .x;
      expect(beforeRebuildsX, lessThan(0));

      // Hammer the parent with rebuilds (mimics the playback position tick
      // that previously kept resetting the marquee animation).
      for (var i = 0; i < 20; i++) {
        hostKey.currentState!.rebuild();
        await tester.pump(const Duration(milliseconds: 50));
      }

      final afterRebuildsX = tester
          .widget<Transform>(findMarqueeTransform())
          .transform
          .getTranslation()
          .x;

      // Scroll must have continued past where it was before the rebuild
      // storm — i.e. the animation was NOT reset back to 0.
      expect(afterRebuildsX, lessThan(beforeRebuildsX));

      await disposeTree(tester);
    });

    testWidgets('continuous loop resets seamlessly', (tester) async {
      const style = TextStyle(fontSize: 16);
      const longText = 'Seamless Loop Test Title That Is Very Long';
      const containerWidth = 100.0;
      const gapWidth = 48.0;

      final textWidth = AdaptiveMarqueeText.measureTextWidth(
        text: longText,
        style: style,
        textScaler: const TextScaler.linear(1),
      );

      await tester.pumpWidget(
        buildSubject(
          text: longText,
          width: containerWidth,
          style: style,
          velocity: 5000,
          gapWidth: gapWidth,
          startPause: const Duration(milliseconds: 50),
        ),
      );
      await tester.pump();

      // Two copies should be rendered
      expect(find.text(longText), findsNWidgets(2));

      // Wait for pause and then let animation run through multiple cycles
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 5));

      // Animation should still be running (continuous repeat)
      final transform = tester.widget<Transform>(findMarqueeTransform());
      final translationX = transform.transform.getTranslation().x;

      // Translation should be within the valid range [-(textWidth + gapWidth), 0]
      final maxScroll = textWidth + gapWidth;
      expect(translationX, lessThanOrEqualTo(0));
      expect(translationX, greaterThanOrEqualTo(-maxScroll));

      await disposeTree(tester);
    });
  });
}

class _RebuildingHost extends StatefulWidget {
  final WidgetBuilder builder;

  const _RebuildingHost({super.key, required this.builder});

  @override
  State<_RebuildingHost> createState() => _RebuildingHostState();
}

class _RebuildingHostState extends State<_RebuildingHost> {
  int _tick = 0;

  void rebuild() {
    setState(() {
      _tick++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Touch _tick so the framework treats this as a meaningful rebuild.
    return KeyedSubtree(
      key: ValueKey('host-static'),
      child: Builder(builder: (context) {
        _tick.toString();
        return widget.builder(context);
      }),
    );
  }
}
