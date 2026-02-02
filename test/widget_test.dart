import "package:flutter_test/flutter_test.dart";

import "package:insta360link_android_test/main.dart";

void main() {
  testWidgets("tracker home renders", (WidgetTester tester) async {
    await tester.pumpWidget(const TrackerApp());
    expect(find.text("Insta360 Link Face Tracker"), findsOneWidget);
    expect(find.text("Initialize"), findsOneWidget);
    expect(find.text("Start Tracking"), findsOneWidget);
  });
}
