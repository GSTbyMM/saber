import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/extensions/list_extensions.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/pen.dart';
import 'dart:ui' as ui;

class LaserPointer extends Tool {
  LaserPointer._();

  static final LaserPointer _currentLaserPointer = LaserPointer._();
  static LaserPointer get currentLaserPointer => _currentLaserPointer;

  @override
  ToolId get toolId => ToolId.laserPointer;

  static const outerColor = Color(0xFFB71C1C); // Darker red for the border
  static const innerColor = Colors.white; // Inner white line remains

  final pressureEnabled = false;
  final options = StrokeOptions(
    size: 2.0, // Base size for dynamic thickness
    smoothing: 0.85, // Increased smoothing for better flow
    streamline: 0.95, // Higher streamline for more alignment
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

    final velocity = Pen.currentStroke?.points.isNotEmpty == true
        ? (position - Pen.currentStroke!.points.last).distance
        : 0.0;
    final dynamicSize = (options.size * (1.0 + velocity / 10)).clamp(1.5, 4.0);

    Pen.currentStroke?.addPoint(position);
    Pen.currentStroke?.options = options.copyWith(size: dynamicSize); // Ensure immutability
    strokePointDelays.add(_stopwatch.elapsed);
    _stopwatch.reset();
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

  static const _fadeOutDelay = Duration(milliseconds: 1200);

  @visibleForTesting
  static void fadeOutStroke({
    required Stroke stroke,
    required List<Duration> strokePointDelays,
    required VoidCallback redrawPage,
    required void Function(Stroke) deleteStroke,
  }) async {
    await Future.delayed(_fadeOutDelay);

    for (int i = 0; i < strokePointDelays.length; i++) {
      final delay = strokePointDelays[i];
      await Future.delayed(delay * 0.7);

      stroke.color = stroke.color.withOpacity(
          ((strokePointDelays.length - i) / strokePointDelays.length)
              .clamp(0.0, 1.0));

      stroke.popFirstPoint();
      redrawPage();

      if (isDrawing) {
        const waitTime = Duration(milliseconds: 80);
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
  @visibleForTesting
  LaserStroke.convertStroke(Stroke stroke)
      : super(
          color: stroke.color,
          pressureEnabled: stroke.pressureEnabled,
          options: stroke.options
            ..streamline = 0.7
            ..smoothing = 0.7,
          pageIndex: stroke.pageIndex,
          page: stroke.page,
          penType: stroke.penType,
        ) {
    points.addAll(stroke.points);
  }

  @override
  void draw(Canvas canvas) {
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, options.size),
        [LaserPointer.innerColor, LaserPointer.outerColor],
      )
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, options.size * 0.5);

    final path = Stroke.smoothPathFromPolygon(highQualityPolygon);
    canvas.drawPath(path, paint);
  }

  List<Offset>? _innerPolygon;
  List<Offset> get innerPolygon => _innerPolygon ??= getStroke(
        points,
        options: options.copyWith(size: options.size * 0.25),
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
}
