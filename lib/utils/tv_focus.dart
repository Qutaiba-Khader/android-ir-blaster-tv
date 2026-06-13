import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A [FocusNode] for single-line search / text fields on Android TV.
///
/// A focused Material text field otherwise swallows the D-pad: arrow Down/Up
/// move the text cursor (or do nothing) and the user gets stuck inside the box.
/// This node hands focus to the next/previous control on Down/Up so the D-pad
/// can always escape the field, while Left/Right/typing still work normally.
FocusNode tvEscapeFocusNode({String? debugLabel}) {
  return FocusNode(
    debugLabel: debugLabel,
    onKeyEvent: (node, event) {
      if (event is KeyDownEvent) {
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          node.nextFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          node.previousFocus();
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    },
  );
}
