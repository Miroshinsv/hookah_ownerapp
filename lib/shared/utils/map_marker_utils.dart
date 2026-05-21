import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

Future<BitmapDescriptor> buildHookahMarkerBitmap() async {
  const double canvasSize = 300;
  const double circleR = 95.0;
  const double circleCX = canvasSize / 2;
  const double circleCY = circleR + 15;
  const double tipY = canvasSize - 10;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);

  // Gold pin
  final pinPaint = ui.Paint()
    ..color = const ui.Color(0xFFC9A96E)
    ..isAntiAlias = true;

  canvas.drawCircle(const ui.Offset(circleCX, circleCY), circleR, pinPaint);

  final triangle = ui.Path();
  triangle.moveTo(circleCX - circleR * 0.65, circleCY + circleR * 0.6);
  triangle.lineTo(circleCX, tipY);
  triangle.lineTo(circleCX + circleR * 0.65, circleCY + circleR * 0.6);
  triangle.close();
  canvas.drawPath(triangle, pinPaint);

  // Dark inner circle
  const double innerR = circleR - 20;
  canvas.drawCircle(
    const ui.Offset(circleCX, circleCY),
    innerR,
    ui.Paint()
      ..color = const ui.Color(0xFF0A0A0A)
      ..isAntiAlias = true,
  );

  // Hookah icon in gold (srcIn = use image alpha, fill with gold)
  final ByteData assetData = await rootBundle.load('assets/icon/hookah_fg.png');
  final int iconPx = ((innerR - 18) * 2).toInt();
  final ui.Codec codec = await ui.instantiateImageCodec(
    assetData.buffer.asUint8List(),
    targetWidth: iconPx,
    targetHeight: iconPx,
  );
  final ui.FrameInfo frame = await codec.getNextFrame();
  canvas.drawImage(
    frame.image,
    ui.Offset(circleCX - iconPx / 2, circleCY - iconPx / 2),
    ui.Paint()
      ..colorFilter = const ui.ColorFilter.mode(
        ui.Color(0xFFC9A96E),
        ui.BlendMode.srcIn,
      ),
  );

  final picture = recorder.endRecording();
  final img = await picture.toImage(canvasSize.toInt(), canvasSize.toInt());
  final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
}
