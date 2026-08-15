import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// `setState(() => _field = someFuture)` throws at runtime.
///
/// An arrow closure returns the value of its expression, and an assignment
/// evaluates to the value assigned — so `() => _future = f` is a closure
/// returning a `Future`, which Flutter rejects with "setState() callback
/// argument returned a Future". It compiles cleanly and the analyzer says
/// nothing, so it only ever shows up in front of a user.
///
/// This is a documented trap in this codebase (see the comment in
/// `admin_ads_screen.dart`) and it was still reintroduced in four screens
/// while making pull-to-refresh await its fetch. The rule is a block body
/// whenever the assigned value is a Future or a Stream.
void main() {
  testWidgets('an arrow-body setState assigning a Future throws', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _Subject(useArrow: true)));

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(
      tester.takeException(),
      isA<FlutterError>().having(
        (e) => e.message,
        'message',
        contains('returned a Future'),
      ),
    );
  });

  testWidgets('a block-body setState assigning a Future is fine', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _Subject(useArrow: false)));

    await tester.tap(find.byType(ElevatedButton));
    // Twice: the first frame is the FutureBuilder in its waiting state, the
    // second is after the future completes.
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('assigned'), findsOneWidget);
  });
}

/// Reproduces the shape the refresh handlers use: swap in a new future and
/// rebuild a `FutureBuilder` around it.
class _Subject extends StatefulWidget {
  const _Subject({required this.useArrow});

  final bool useArrow;

  @override
  State<_Subject> createState() => _SubjectState();
}

class _SubjectState extends State<_Subject> {
  Future<String>? _future;

  void _reload() {
    final future = Future.value('assigned');
    if (widget.useArrow) {
      // ignore: unnecessary_lambdas
      setState(() => _future = future);
    } else {
      setState(() {
        _future = future;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        ElevatedButton(onPressed: _reload, child: const Text('reload')),
        if (_future != null)
          FutureBuilder<String>(
            future: _future,
            builder: (context, snapshot) => Text(snapshot.data ?? ''),
          ),
      ],
    ),
  );
}
