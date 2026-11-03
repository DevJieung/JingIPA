import 'startup_trace_stub.dart'
    if (dart.library.js_interop) 'startup_trace_web.dart'
    as platform;

/// Local timings only. Never include account IDs, names, choices or coordinates.
class StartupTrace {
  final Stopwatch _watch = Stopwatch()..start();
  final Set<String> _seen = {};
  void mark(String stage) {
    if (_seen.add(stage)) platform.mark(stage, _watch.elapsedMilliseconds);
  }
}
