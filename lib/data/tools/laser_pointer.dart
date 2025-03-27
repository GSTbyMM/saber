import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/extensions/list_extensions.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/pen.dart';

class LaserPointer extends Tool {
  LaserPointer._();

  static final LaserPointer _currentLaserPointer = LaserPointer._();
  static LaserPointer get currentLaserPointer => _currentLaserPointer;

  @override
  ToolId get toolId => ToolId.laserPointer;

  static const outerColor = Color(0xFFB71C1C); // Dark red for the outer stroke
  static const innerColor = Colors.white; // Inner white stroke

  final pressureEnabled = false;
  final options = StrokeOptions(
    size: 5.0, // Initial stroke size
    smoothing: 0.8,
    streamline: 0.9,
  );

  List<Duration> strokePointDelays = [];
  final Stopwatch _stopwatch = Stopwatch();
  static bool isDrawing = false;

  void onDragStart(Offset position, EditorPage page, int pageIndex) {
    isDrawing = true;
    Pen.currentStroke = LaserStroke(
      color: outerColor,
      pressureEnabled: pressureEnabled,
      options: options.copyWith(),
      pageIndex: pageIndex,
      page: page,
      penType: runtimeType.toString(),
    );

    strokePointDelays = [];
    _stopwatch.reset();
    onDragUpdate(position);
    _stopwatch.start();
  }

  void onDragUpdate(Offset position) {
    isDrawing = true;
    Pen.currentStroke?.addPoint(position);
    strokePointDelays.add(_stopwatch.elapsed);
    _stopwatch.reset();

    // Dynamically adjust stroke size based on velocity
    final velocity = Pen.currentStroke!.points.length > 1
        ? (Pen.currentStroke!.points.last - Pen.currentStroke!.points[Pen.currentStroke!.points.length - 2]).distance
        : 0.0;

    Pen.currentStroke!.options = options.copyWith(
      size: (5.0 + velocity * 0.2).clamp(3.0, 10.0), // Dynamic thickness
    );
  }

  LaserStroke onDragEnd(
      VoidCallback redrawPage, void Function(Stroke) deleteStroke) {
    isDrawing = false;

    fadeOutStroke(
      stroke: Pen.currentStroke!,
      strokePointDelays: strokePointDelays,
      redrawPage: redrawPage,
      deleteStroke: deleteStroke,
    );

    final stroke = (Pen.currentStroke! as LaserStroke)
      ..options.isComplete = true
      ..markPolygonNeedsUpdating();
    Pen.currentStroke = null;
    return stroke;
  }

  static const _fadeOutDelay = Duration(milliseconds: 1500); // Faster fade-out

  @visibleForTesting
  static void fadeOutStroke({
    required Stroke stroke,
    required List<Duration> strokePointDelays,
    required VoidCallback redrawPage,
    required void Function(Stroke) deleteStroke,
  }) async {
    await Future.delayed(_fadeOutDelay);

    for (final delay in strokePointDelays) {
      await Future.delayed(delay * 0.5); // Smoother delay

      stroke.popFirstPoint();
      stroke.color = stroke.color.withOpacity(
        (stroke.points.length / strokePointDelays.length).clamp(0.0, 1.0),
      ); // Adjust opacity
      redrawPage();

      if (isDrawing) {
        const waitTime = Duration(milliseconds: 100);
        while (isDrawing) await Future.delayed(waitTime);
        await Future.delayed(_fadeOutDelay - waitTime);
      }
    }

    deleteStroke(stroke);
    redrawPage();
  }
}

class LaserStroke extends Stroke {
  LaserStroke({
    required super.color,
    required super.pressureEnabled,
    required super.options,
    required super.pageIndex,
    required EditorPage super.page,
    required super.penType,
  });

  List<Offset>? _innerPolygon;
  List<Offset> get innerPolygon => _innerPolygon ??= getStroke(
        points,
        options: options.copyWith(size: options.size * 0.3),
      );

  Path? _innerPath;
  Path get innerPath =>
      _innerPath ??= Stroke.smoothPathFromPolygon(innerPolygon);

  @override
  List<Offset> get lowQualityPolygon => highQualityPolygon;

  @override
  void shift(Offset offset) {
    _innerPolygon?.shift(offset);
    _innerPath?.shift(offset);
    super.shift(offset);
  }

  @override
  void markPolygonNeedsUpdating() {
    _innerPolygon = null;
    _innerPath = null;
    super.markPolygonNeedsUpdating();
  }

  /// Override to apply a glow effect and gradient color
  @override
  Path get outerPath {
    final glowPath = Path();
    final glowWidth = options.size * 2.0; // Glow width
    for (final point in highQualityPolygon) {
      glowPath.addOval(Rect.fromCircle(center: point, radius: glowWidth));
    }
    return glowPath;
  }

  @override
  Paint get paint {
    final gradientPaint = Paint()
      ..shader = _createGradientShader()
      ..style = PaintingStyle.fill;

    return gradientPaint;
  }

  Shader _createGradientShader() {
    return LinearGradient(
      colors: [innerColor, outerColor],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    ).createShader(
      Rect.fromLTWH(0, 0, options.size, options.size),
    );
  }
}
