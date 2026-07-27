import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

/// One way to raise the share sheet.
///
/// iPad presents it as a POPOVER, which needs an anchor rectangle, and
/// `share_plus` asserts when it is not given one. Every call site in the app
/// omitted `sharePositionOrigin` (penetration review 2026-07-07), so sharing an
/// invite, a scorecard or a tournament link was broken on every iPad - and
/// sharing is how a team gets its players in the first place.
///
/// The anchor is the render box of the widget whose [context] is passed, so
/// pass the closest one you have to the button that was tapped.
Rect shareAnchor(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box != null && box.hasSize) {
    return box.localToGlobal(Offset.zero) & box.size;
  }
  // No box (a dialog's context, a detached callback): anchor at the centre so
  // the sheet still has somewhere legal to come from.
  final size = MediaQuery.sizeOf(context);
  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height / 2),
    width: 1,
    height: 1,
  );
}

Future<void> shareFrom(
  BuildContext context, {
  String? text,
  String? subject,
  List<XFile>? files,
}) =>
    SharePlus.instance.share(ShareParams(
      text: text,
      subject: subject,
      files: files,
      sharePositionOrigin: shareAnchor(context),
    ));
