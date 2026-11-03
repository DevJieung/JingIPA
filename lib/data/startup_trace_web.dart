import 'dart:js_interop';

@JS('performance.mark')
external void _mark(JSString name);

void mark(String stage, int elapsedMilliseconds) {
  _mark('meokkiri:$stage'.toJS);
}
