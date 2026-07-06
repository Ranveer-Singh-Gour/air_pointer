import 'dart:async';

import 'package:air_pointer/src/boundary/canvas_input_source.dart';
import 'package:air_pointer/src/events/pointer_input_event.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// Minimal conforming implementation — verifies the contract shape stays
// implementable without platform dependencies.
final class _FakeSource implements CanvasInputSource {
  final StreamController<PointerInputEvent> _controller =
      StreamController<PointerInputEvent>.broadcast();

  @override
  Stream<PointerInputEvent> get events => _controller.stream;

  @override
  Widget buildSurface({required Widget child}) => child;

  @override
  void dispose() => unawaited(_controller.close());

  void emit(PointerInputEvent event) => _controller.add(event);
}

void main() {
  group('CanvasInputSource contract', () {
    test('events stream delivers emitted PointerInputEvents', () async {
      final source = _FakeSource();
      final received = <PointerInputEvent>[];
      source.events.listen(received.add);

      source.emit(const CanvasTapEvent(position: Offset(1, 2)));
      await Future<void>.delayed(Duration.zero);

      expect(received.single, isA<CanvasTapEvent>());
      expect((received.single as CanvasTapEvent).position, const Offset(1, 2));
      source.dispose();
    });

    test('dispose closes the events stream', () async {
      final source = _FakeSource();
      final done = source.events.drain<void>();
      source.dispose();
      await expectLater(done, completes);
    });

    test('a pass-through buildSurface returns the child unchanged', () {
      final source = _FakeSource();
      const child = SizedBox.shrink();
      expect(source.buildSurface(child: child), same(child));
      source.dispose();
    });
  });
}
