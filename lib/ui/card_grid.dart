import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Desktop cards share the tallest content height across the entire grid.
/// One-column layouts keep each card's natural height, including enlarged text.
class ResponsiveCards extends StatelessWidget {
  const ResponsiveCards({
    required this.children,
    this.minWidth = 300,
    this.spacing = 16,
    super.key,
  });
  final List<Widget> children;
  final double minWidth, spacing;

  static int columnsFor(
    BuildContext context,
    double width, {
    double minWidth = 300,
    double spacing = 16,
  }) => MediaQuery.textScalerOf(context).scale(14) / 14 > 1.3
      ? 1
      : ((width + spacing) / (minWidth + spacing)).floor().clamp(1, 3);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = columnsFor(
        context,
        constraints.maxWidth,
        minWidth: minWidth,
        spacing: spacing,
      );
      return _CardGrid(columns: columns, spacing: spacing, children: children);
    },
  );
}

class _CardGrid extends MultiChildRenderObjectWidget {
  const _CardGrid({
    required this.columns,
    required this.spacing,
    required super.children,
  });
  final int columns;
  final double spacing;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCardGrid(columns, spacing);

  @override
  void updateRenderObject(BuildContext context, _RenderCardGrid renderObject) =>
      renderObject.configure(columns, spacing);
}

class _CardParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderCardGrid extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _CardParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _CardParentData> {
  _RenderCardGrid(this._columns, this._spacing);
  int _columns;
  double _spacing;

  void configure(int columns, double spacing) {
    if (_columns == columns && _spacing == spacing) return;
    _columns = columns;
    _spacing = spacing;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _CardParentData) {
      child.parentData = _CardParentData();
    }
  }

  List<double> _heights(double width) {
    final heights = <double>[];
    final cardWidth = (width - (_columns - 1) * _spacing) / _columns;
    var child = firstChild;
    while (child != null) {
      heights.add(child.getMaxIntrinsicHeight(cardWidth));
      child = childAfter(child);
    }
    if (_columns > 1 && heights.isNotEmpty) {
      final tallest = heights.reduce(math.max);
      return List.filled(heights.length, tallest);
    }
    return heights;
  }

  double _height(List<double> heights) {
    var height = 0.0;
    for (var i = 0; i < heights.length; i += _columns) {
      if (i > 0) height += _spacing;
      height += heights[i];
    }
    return height;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(
    Size(constraints.maxWidth, _height(_heights(constraints.maxWidth))),
  );

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final cardWidth = (width - (_columns - 1) * _spacing) / _columns;
    final heights = _heights(width);
    var child = firstChild;
    var index = 0;
    var top = 0.0;
    while (child != null) {
      child.layout(
        BoxConstraints.tight(Size(cardWidth, heights[index])),
        parentUsesSize: true,
      );
      final data = child.parentData! as _CardParentData;
      final column = index % _columns;
      data.offset = Offset(column * (cardWidth + _spacing), top);
      if (column == _columns - 1) top += heights[index] + _spacing;
      index++;
      child = childAfter(child);
    }
    size = constraints.constrain(Size(width, _height(heights)));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
