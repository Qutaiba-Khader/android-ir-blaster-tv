import 'package:flutter/material.dart';

/// SpatialTraversalPolicy — D-pad movement tuned for the Control Surface shell.
///
/// We override [inDirection] (the method Flutter actually calls for ▲▼◀▶ movement —
/// overriding only [findFirstFocusInDirection] is inert for ongoing navigation) with a
/// geometry scorer that REQUIRES cross-axis overlap:
///   • ◀▶ consider only candidates whose vertical extent overlaps the current item —
///     so they stay in the same row and cross rail↔content only where items align.
///   • ▲▼ consider only candidates whose horizontal extent overlaps — so they stay in
///     the same column and a vertical press never jumps across to the rail.
/// Among valid candidates, the nearest by edge-gap (then cross-axis offset) wins.
/// If nothing qualifies, focus stays put (no diagonal teleports).
class SpatialTraversalPolicy extends FocusTraversalPolicy
    with DirectionalFocusTraversalPolicyMixin {
  @override
  Iterable<FocusNode> sortDescendants(Iterable<FocusNode> descendants, FocusNode currentNode) {
    // Reading order (top→bottom, then left→right) for Tab / initial focus.
    final list = descendants.toList();
    list.sort((a, b) {
      final ar = a.rect, br = b.rect;
      const rowTol = 24.0;
      if ((ar.top - br.top).abs() > rowTol) return ar.top.compareTo(br.top);
      return ar.left.compareTo(br.left);
    });
    return list;
  }

  FocusNode? _findTarget(FocusNode currentNode, TraversalDirection direction) {
    final current = currentNode.rect;
    final cx = current.center.dx, cy = current.center.dy;
    double overlap(double a0, double a1, double b0, double b1) =>
        (a1 < b1 ? a1 : b1) - (a0 > b0 ? a0 : b0);

    FocusNode? best;
    double bestScore = double.infinity;

    for (final node in currentNode.nearestScope?.traversalDescendants ?? const <FocusNode>[]) {
      if (node == currentNode || !node.canRequestFocus || node.skipTraversal) continue;
      final r = node.rect;
      final qx = r.center.dx, qy = r.center.dy;

      bool ahead;
      double gap, cross, ov;
      switch (direction) {
        case TraversalDirection.left:
          ahead = qx < cx - 2;
          gap = current.left - r.right;
          cross = (qy - cy).abs();
          ov = overlap(current.top, current.bottom, r.top, r.bottom);
          break;
        case TraversalDirection.right:
          ahead = qx > cx + 2;
          gap = r.left - current.right;
          cross = (qy - cy).abs();
          ov = overlap(current.top, current.bottom, r.top, r.bottom);
          break;
        case TraversalDirection.up:
          ahead = qy < cy - 2;
          gap = current.top - r.bottom;
          cross = (qx - cx).abs();
          ov = overlap(current.left, current.right, r.left, r.right);
          break;
        case TraversalDirection.down:
          ahead = qy > cy + 2;
          gap = r.top - current.bottom;
          cross = (qx - cx).abs();
          ov = overlap(current.left, current.right, r.left, r.right);
          break;
      }
      if (!ahead) continue;
      if (ov <= 0) continue; // require cross-axis overlap — no region-jumping diagonals
      if (gap < 0) gap = 0;
      final score = gap + cross * 0.25;
      if (score < bestScore) {
        bestScore = score;
        best = node;
      }
    }
    return best;
  }

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    // Fall back to the default behavior if focus sits on a scope (initial entry).
    if (currentNode is FocusScopeNode) {
      return super.inDirection(currentNode, direction);
    }
    final target = _findTarget(currentNode, direction);
    if (target == null) return false; // nothing aligned that way → stay put
    // Use requestFocusCallback (not bare requestFocus) so the target is SCROLLED
    // into view — this is what makes long grids/lists (e.g. a 109-key keypad)
    // scroll as the D-pad moves focus past the visible area.
    final ScrollPositionAlignmentPolicy align;
    switch (direction) {
      case TraversalDirection.up:
      case TraversalDirection.left:
        align = ScrollPositionAlignmentPolicy.keepVisibleAtStart;
        break;
      case TraversalDirection.down:
      case TraversalDirection.right:
        align = ScrollPositionAlignmentPolicy.keepVisibleAtEnd;
        break;
    }
    requestFocusCallback(target, alignmentPolicy: align);
    return true;
  }

  @override
  FocusNode? findFirstFocusInDirection(FocusNode currentNode, TraversalDirection direction) =>
      _findTarget(currentNode, direction);
}
