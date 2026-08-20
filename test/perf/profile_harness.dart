// M6 PERFORMANCE MEASUREMENT — non-production instrumentation.
//
// PROFILE-MODE harness. Unlike the widget tests (Dart VM, JIT, asserts on,
// software raster, fake clock), this runs the REAL app shell AOT-compiled with
// a real GPU raster pass and a real vsync clock, and reads frame timings from
// Flutter's own `SchedulerBinding.addTimingsCallback` — i.e. the same numbers
// DevTools' performance overlay shows: build time and RASTER time separately.
//
// Run:
//   flutter run --profile -t test/perf/profile_harness.dart -d windows
//
// It drives the scenarios automatically and prints a summary, so no manual
// interaction is needed. Results are printed to stdout as PROFILE| lines.
//
// WHY WINDOWS DESKTOP: no Android device or emulator is available on this
// machine (`flutter devices` shows only Windows/Chrome/Edge; `flutter emulators`
// reports none, and adb is not installed). Windows profile mode still gives
// genuine AOT + real raster numbers, which is far better evidence than JIT
// widget-test timings. Absolute numbers on a mid-range Android phone will be
// slower (roughly 3-6x on raster-bound work); the RELATIVE comparisons and the
// scaling behaviour carry over.
//
// DELETE THIS DIRECTORY once the measurement milestone is signed off.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/screens/match_details/match_details_screen.dart';

import 'stub_api.dart';

/// Collects frame timings for a labelled window of time.
class FrameProbe {
  final List<FrameTiming> _timings = [];
  bool _recording = false;

  void start() {
    _timings.clear();
    _recording = true;
  }

  void onTimings(List<FrameTiming> timings) {
    if (_recording) _timings.addAll(timings);
  }

  /// Stops recording and reports build/raster stats in microseconds.
  void report(String label) {
    _recording = false;
    if (_timings.isEmpty) {
      // ignore: avoid_print
      print('PROFILE| $label | NO FRAMES CAPTURED');
      return;
    }
    final build = _timings
        .map((t) => t.buildDuration.inMicroseconds)
        .toList()
      ..sort();
    final raster = _timings
        .map((t) => t.rasterDuration.inMicroseconds)
        .toList()
      ..sort();
    final total = _timings
        .map((t) => t.totalSpan.inMicroseconds)
        .toList()
      ..sort();
    int pct(List<int> xs, double p) => xs[(xs.length * p).clamp(0, xs.length - 1).floor()];
    // 60fps budget = 16667us for build+raster combined.
    final janky = _timings
        .where((t) =>
            t.buildDuration.inMicroseconds + t.rasterDuration.inMicroseconds >
            16667)
        .length;
    // ignore: avoid_print
    print('PROFILE| $label | frames=${_timings.length} '
        'build_med=${pct(build, .5)} build_p90=${pct(build, .9)} build_max=${build.last} '
        'raster_med=${pct(raster, .5)} raster_p90=${pct(raster, .9)} raster_max=${raster.last} '
        'total_p90=${pct(total, .9)} '
        'janky_frames=$janky (${(janky * 100 / _timings.length).toStringAsFixed(1)}%)');
  }
}

final FrameProbe probe = FrameProbe();

/// Feed size for this run, so one AOT binary can measure several sizes:
///   flutter run --profile -t ... --dart-define=MD_FEED=8
const int kFeed = int.fromEnvironment('MD_FEED', defaultValue: 80);
final StubApi stub = StubApi(commentaryCount: kFeed);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});
  stub.install();
  SchedulerBinding.instance.addTimingsCallback(probe.onTimings);
  runApp(const _ProfileApp());
  unawaited(_drive());
}

/// Drives the scenarios with real wall-clock waits.
Future<void> _drive() async {
  Future<void> settle([int ms = 2500]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  await settle(4000); // let the first load + AOT warmup finish

  // --- Scenario B: live polling on the default (Live) tab ------------------
  probe.start();
  await settle(20000); // 4 poll cycles
  probe.report('B live-tab 20s polling (feed=$kFeed)');

  // --- Scenario C/B2: 80-row commentary tab -------------------------------
  _tapTab('Comm');
  await settle(1500);
  probe.start();
  await settle(20000);
  probe.report('B2 comm-tab $kFeed rows, 20s polling');

  // --- Scenario E: continuous scrolling over the 80-row list --------------
  probe.start();
  await _scroll(cycles: 6);
  probe.report('E scroll $kFeed-row commentary list');

  // --- Scenario D: rapid tab switching ------------------------------------
  probe.start();
  for (var i = 0; i < 2; i++) {
    for (final t in const ['Info', 'Live', 'Score', 'Squad', 'Comm', 'Overs']) {
      _tapTab(t);
      await settle(700);
    }
  }
  probe.report('D rapid tab switching (12 switches)');

  // ignore: avoid_print
  print('PROFILE| DONE | requests=${stub.totalRequests} hits=${stub.hits}');
}

final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

/// Finds a tab by its label text and taps it via the gesture binding.
void _tapTab(String label) {
  final target = _findTextCenter(label);
  if (target == null) {
    // ignore: avoid_print
    print('PROFILE| WARN | tab "$label" not found');
    return;
  }
  _tapAt(target);
}

Offset? _findTextCenter(String label) {
  Offset? found;
  void visit(Element el) {
    if (found != null) return;
    final w = el.widget;
    if (w is Text && w.data == label) {
      final ro = el.renderObject;
      if (ro is RenderBox && ro.hasSize && ro.attached) {
        found = ro.localToGlobal(ro.size.center(Offset.zero));
        return;
      }
    }
    el.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}

void _tapAt(Offset p) {
  final binding = GestureBinding.instance;
  const id = 42;
  binding.handlePointerEvent(PointerDownEvent(pointer: id, position: p));
  binding.handlePointerEvent(PointerUpEvent(pointer: id, position: p));
}

/// Fling-scrolls the page up and down to exercise the scroll path.
Future<void> _scroll({int cycles = 4}) async {
  final size =
      WidgetsBinding.instance.rootElement!.renderObject!.paintBounds.size;
  final start = Offset(size.width / 2, size.height * 0.75);
  const id = 77;
  for (var c = 0; c < cycles; c++) {
    final dir = c.isEven ? -1 : 1;
    final binding = GestureBinding.instance;
    binding.handlePointerEvent(PointerDownEvent(pointer: id, position: start));
    var pos = start;
    for (var i = 0; i < 20; i++) {
      pos = pos.translate(0, dir * 22);
      binding.handlePointerEvent(
          PointerMoveEvent(pointer: id, position: pos, delta: Offset(0, dir * 22)));
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    binding.handlePointerEvent(PointerUpEvent(pointer: id, position: pos));
    await Future<void>.delayed(const Duration(milliseconds: 900));
  }
}

class _ProfileApp extends StatelessWidget {
  const _ProfileApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: navKey,
        theme: cricTheme(true),
        debugShowCheckedModeBanner: false,
        // Force a phone-sized viewport so row counts match the Android case.
        home: const Center(
          child: SizedBox(
            width: 360,
            height: 804,
            child: MatchDetailsScreen(matchId: 'perf-1'),
          ),
        ),
      );
}
