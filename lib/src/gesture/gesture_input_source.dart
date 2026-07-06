// Keyed on dart.library.js_interop (not the legacy dart.library.html) so the
// web implementation is also selected under wasm compilation, where dart:html
// is unavailable but js_interop is.
export 'package:air_pointer/src/gesture/gesture_input_source_native.dart'
    if (dart.library.js_interop) 'package:air_pointer/src/gesture/gesture_input_source_web.dart';
