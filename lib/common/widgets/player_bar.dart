/*
 * This file is part of PiliPlus
 *
 * PiliPlus is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * PiliPlus is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with PiliPlus.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:math' as math;

import 'package:PiliPlus/common/widgets/slotted_layout_helper.dart';
import 'package:flutter/rendering.dart'
    show BoxHitTestResult, TransformLayer, RenderObjectVisitor;
import 'package:flutter/widgets.dart';

enum PlayerBarType {
  left,
  rightLeading,
  optionalRight,
  compactRight,
  right,
  title,
}

class PlayerBar
    extends SlottedMultiChildRenderObjectWidget<PlayerBarType, RenderBox> {
  const PlayerBar({
    super.key,
    required this.left,
    required this.right,
    this.title,
    this.rightLeading,
    this.optionalRight,
    this.compactRight,
  }) : assert(
         title == null ||
             (rightLeading == null &&
                 optionalRight == null &&
                 compactRight == null),
       );

  final Widget left;
  final Widget right;
  final Widget? title;
  final Widget? rightLeading;

  /// 在右侧两组之间优先显示，空间不足时显示紧凑入口。
  final Widget? optionalRight;
  final Widget? compactRight;

  @override
  RenderPlayerBar createRenderObject(BuildContext context) {
    return RenderPlayerBar();
  }

  @override
  Widget? childForSlot(slot) => switch (slot) {
    .left => left,
    .right => right,
    .title => title,
    .rightLeading => rightLeading,
    .optionalRight => optionalRight,
    .compactRight => compactRight,
  };

  @override
  Iterable<PlayerBarType> get slots => PlayerBarType.values;
}

class RenderPlayerBar extends RenderBox
    with
        SlottedContainerRenderObjectMixin<PlayerBarType, RenderBox>,
        SlottedLayoutMixin<PlayerBarType> {
  RenderBox get left => childForSlot(.left)!;
  RenderBox get right => childForSlot(.right)!;
  RenderBox? get title => childForSlot(.title);

  @override
  Iterable<PlayerBarType> get slots => _showOptionalRight
      ? const [.left, .rightLeading, .optionalRight, .right, .title]
      : const [.left, .rightLeading, .compactRight, .right, .title];

  Matrix4? _transform;
  bool _showOptionalRight = false;

  @override
  void performLayout() {
    _transform = null;
    final maxWidth = constraints.maxWidth;

    final title = this.title;
    if (title != null) {
      final c = constraints.loosen();
      final left = this.left..layout(c, parentUsesSize: true);
      final right = this.right..layout(c, parentUsesSize: true);
      final leftSize = left.size;
      final rightSize = right.size;

      title.layout(
        BoxConstraints(
          maxWidth: math.max(0, maxWidth - leftSize.width - rightSize.width),
        ),
        parentUsesSize: true,
      );

      final titleSize = title.size;
      final height = math.max(
        math.max(leftSize.height, rightSize.height),
        titleSize.height,
      );

      setOffset(left, Offset(0, (height - leftSize.height) / 2));
      setOffset(
        right,
        Offset(maxWidth - rightSize.width, (height - rightSize.height) / 2),
      );
      setOffset(title, Offset(leftSize.width, (height - titleSize.height) / 2));

      size = constraints.constrainDimensions(maxWidth, height);
      return;
    }

    final c = constraints.loosen().copyWith(maxWidth: .infinity);
    final left = this.left..layout(c, parentUsesSize: true);
    final right = this.right..layout(c, parentUsesSize: true);
    final leading = childForSlot(.rightLeading)
      ?..layout(c, parentUsesSize: true);
    final optional = childForSlot(.optionalRight)
      ?..layout(c, parentUsesSize: true);
    final compact = childForSlot(.compactRight)
      ?..layout(c, parentUsesSize: true);
    final leadingWidth = leading?.size.width ?? 0;
    final available =
        maxWidth - left.size.width - leadingWidth - right.size.width;
    final show =
        optional != null &&
        optional.size.width > 0 &&
        optional.size.width <= available;
    if (show != _showOptionalRight) {
      _showOptionalRight = show;
      markNeedsSemanticsUpdate();
    }
    final picker = show ? optional : compact;
    final rightGroup = [?leading, ?picker, right];
    final rightWidth =
        leadingWidth + (picker?.size.width ?? 0) + right.size.width;
    final totalWidth = left.size.width + rightWidth;
    final height = rightGroup.fold(
      left.size.height,
      (height, child) => math.max(height, child.size.height),
    );
    size = constraints.constrainDimensions(maxWidth, height);

    setOffset(left, Offset(0, (height - left.size.height) / 2));
    var rightOffset = maxWidth - rightWidth;
    if (totalWidth > maxWidth) {
      final scale = maxWidth / totalWidth;
      _transform = Matrix4.identity()
        ..translateByDouble(0.0, height * (1 - scale) / 2, 0.0, 1.0)
        ..scaleByDouble(scale, scale, scale, 1.0);
      rightOffset = left.size.width;
    }
    for (final child in rightGroup) {
      setOffset(child, Offset(rightOffset, (height - child.size.height) / 2));
      rightOffset += child.size.width;
    }
  }

  void defaultPaint(PaintingContext context, Offset offset) {
    for (final slot in slots) {
      if (childForSlot(slot) case final child?) {
        context.paintChild(child, getOffset(child) + offset);
      }
    }
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    for (final slot in slots) {
      if (childForSlot(slot) case final child?) visitor(child);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_transform != null) {
      layer = context.pushTransform(
        needsCompositing,
        offset,
        _transform!,
        defaultPaint,
        oldLayer: layer as TransformLayer?,
      );
    } else {
      defaultPaint(context, offset);
      layer = null;
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return result.addWithPaintTransform(
      transform: _transform,
      position: position,
      hitTest: (result, position) {
        return super.hitTestChildren(result, position: position);
      },
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final Offset offset = getOffset(child);
    if (_transform != null) {
      transform
        ..translateByDouble(offset.dx * _transform!.storage[0], offset.dy, 0, 1)
        ..multiply(_transform!);
    } else {
      transform.translateByDouble(offset.dx, offset.dy, 0, 1);
    }
  }
}
