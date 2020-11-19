// This widget allows .obj model files to be visualised in Flutter
// It is based on the flutter_3d_obj package (https://pub.dev/packages/flutter_3d_obj) with some significant modifications:
// 1. it can parse obj files with vertex colouring (Meshlab OBJ format)
// 2. adaptive brightness
// 3. flat colour mode
// 4. better rotation handling (axis enabling and acceleration/deceleration)
// 5. dynamic lighting
// 6. slightly faster rendering (though to be honest it is still quite slow due to limitations of the platform)

import 'dart:io';
import 'dart:math' as Math;
import 'dart:ui';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:vector_math/vector_math.dart' show Vector3;
import 'package:vector_math/vector_math.dart' as V;

// ModelViewer is the UI object. Instantiate this and change the values to create the 3D object widget.
class ModelViewer extends StatefulWidget {
  ModelViewer({
    @required this.size,
    @required this.path,
    @required this.asset,
    this.angleX,
    this.angleY,
    this.angleZ,
    this.zoom = 100.0,
    this.brightness = 1.0,
    this.adaptiveBrightness = -1,
    this.allowRotateX = true,
    this.allowRotateY = true,
    this.xDeceleration,
    this.yDeceleration,
    this.flatColor,
    this.useLight,
    this.lightColor,
    this.lightIntensity,
    this.postRenderCallback,
  });

  final Size size;
  final bool asset;
  final String path;
  final double zoom;

  // angleX, angleY and angleZ specify the initial rotation of the object (i.e. applied before the user rotates it)
  final double angleX;
  final double angleY;
  final double angleZ;

  // brightness is a fixed multiplier that is applied to the entire model
  final double brightness;
  // adaptiveBrightness allows the brightness of all models processed by the widget to come out
  // at approximately the same level of brightness; use values of 0-255, though the end result will not be exactly 0-255
  final int adaptiveBrightness;

  // allowRotateX and allowRotateY specify whether each of axes on the screen (i.e. left-right and up-down) can be used to rotate the object
  final bool allowRotateX;
  final bool allowRotateY;

  final double xDeceleration;
  final double yDeceleration;
  final Color flatColor;
  final bool useLight;
  final Color lightColor;
  final Vector3 lightIntensity;

  final Function(Map) postRenderCallback;

  @override
  _ModelViewerState createState() => new _ModelViewerState();
}

class _ModelViewerState extends State<ModelViewer> {
  _ModelViewerState();

  void initState() {
    if (widget.asset == true) {
      rootBundle.loadString(widget.path).then((String value) {
        setState(() {
          object = value;
        });
      });
    } else {
      File file = new File(widget.path);
      file.readAsString().then((String value) {
        setState(() {
          object = value;
        });
      });
    }

    angleX = widget.angleX ?? 0;
    angleY = widget.angleY ?? 0;
    angleZ = widget.angleZ ?? 0;

    useInternal = true;

    //useInternal = !(widget.angleX != null || widget.angleY != null || widget.angleZ != null);
    super.initState();
  }


  bool useInternal;

  double angleX = 0.0;
  double angleY = 135.0;
  double angleZ = 90.0;

  double _previousX = 0.0;
  double _previousY = 0.0;

  double zoom;
  String object = "V 1 1 1 1";

  File file;

  void _updateCube(DragUpdateDetails data) {
    if (angleY > 360.0) {
      angleY = angleY - 360.0;
    }
    if (_previousY > data.globalPosition.dx && widget.allowRotateX) {
      setState(() {
        angleY = angleY - 1;
      });
    }
    if (_previousY < data.globalPosition.dx && widget.allowRotateX) {
      setState(() {
        angleY = angleY + 1;
      });
    }
    _previousY = data.globalPosition.dx;

    if (angleX > 360.0) {
      angleX = angleX - 360.0;
    }
    if (_previousX > data.globalPosition.dy && widget.allowRotateY) {
      setState(() {
        angleX = angleX - 1;
      });
    }
    if (_previousX < data.globalPosition.dy && widget.allowRotateY) {
      setState(() {
        angleX = angleX + 1;
      });
    }
    _previousX = data.globalPosition.dy;
  }

  void _updateY(DragUpdateDetails data) {
    _updateCube(data);
  }

  void _updateX(DragUpdateDetails data) {
    _updateCube(data);
  }

  @override
  Widget build(BuildContext context) {
    print(widget.adaptiveBrightness);
    return new GestureDetector(
      child: new CustomPaint(
        painter: new _ModelPainter(size: widget.size, object: object, angleX: useInternal ? angleX : widget.angleX,
            angleY: useInternal ? angleY : widget.angleY, angleZ: useInternal ? angleZ : widget.angleZ,
            zoomFactor: widget.zoom, brightness: widget.brightness, adaptiveBrightness: widget.adaptiveBrightness,
            flatColor: widget.flatColor, postRenderCallback: widget.postRenderCallback),
        size: widget.size,
      ),
      onHorizontalDragUpdate: _updateY,
      onVerticalDragUpdate: _updateX,
    );
  }
}

// _ModelPainter is the internal class that handles the actual rendering
class _ModelPainter extends CustomPainter {
  double zoomFactor = 100.0;

  final double zero = 0.0;

  final String object;

  double _viewPortX = 0.0, _viewPortY = 0.0;

  List<Vector3> vertices;
  List<dynamic> faces;
  List<Color> colors;
  V.Matrix4 T;
  Vector3 camera;
  Vector3 light;

  double angleX;
  double angleY;
  double angleZ;

  Color color;
  Color flatColor;

  Size size;

  double brightness;
  int adaptiveBrightness;
  double adaptiveBrightnessCoefficient;
  Function(Map) postRenderCallback;

  _ModelPainter({this.size, this.object, this.angleX, this.angleY, this.angleZ, this.zoomFactor, this.brightness, this.adaptiveBrightness, this.flatColor, this.postRenderCallback}) {
    //_translation *= zoomFactor;
    camera = new Vector3(0.0, 0.0, 0.0);
    light = new Vector3(100.0, 100.0, 300.0);
    color = new Color.fromARGB(255, 255, 255, 255);
    _viewPortX = (size.width / 2).toDouble();
    _viewPortY = (size.height / 2).toDouble();
    print("adaptivebrightness: $adaptiveBrightness");
  }

  Map _parseObjString(String objString) {
    List vertices = <Vector3>[];
    List faces = <List<int>>[];
    List<int> face = [];
    List<Color> colors = [];

    List lines = objString.split("\n");

    Vector3 vertex;

    int i = 0;
    int adaptiveBrightnessCount = 0;
    int adaptiveBrightnessTotal = 0;

    lines.forEach((dynamic line) {
      String lline = line;
      lline = lline.replaceAll(new RegExp(r"\s+$"), "");
      List<String> chars = lline.split(" ");

      // vertex
      if (chars[0] == "v") {
        vertex = new Vector3(double.parse(chars[1]), double.parse(chars[2]), double.parse(chars[3]));

        vertices.add(vertex);

        // this part handles the vertex colour encoding in meshlab obj files
        // the standard obj format encodes vertices as 'v x y z', where xyz constitute the position
        // the meshlab obj format encodes them as 'v x y z r g b', where rgb (0-1) give us the colour
        if(chars.length >= 7){
          int r = (double.parse(chars[4]) * 255).round();
          int g = (double.parse(chars[5]) * 255).round();
          int b = (double.parse(chars[6]) * 255).round();

          colors.add(Color.fromARGB(255, r, g, b));

          if(adaptiveBrightness >= 0 && i % 100 == 0){
            adaptiveBrightnessTotal += Math.max(Math.max(r, g), b);
            adaptiveBrightnessCount++;
          }
        }
        i++;

        // face
      } else if (chars[0] == "f") {
        for (var i = 1; i < chars.length; i++) {
          face.add(int.parse(chars[i].split("/")[0]));
        }

        faces.add(face);
        face = [];
      }
    });

    if(adaptiveBrightness >= 0){
      print("adaptiveBrightnessTotal: $adaptiveBrightnessTotal, adaptiveBrightnessCount: $adaptiveBrightnessCount");
      print("average brightness of model: ${(adaptiveBrightnessTotal / adaptiveBrightnessCount)}");
      adaptiveBrightnessCoefficient = adaptiveBrightness / (adaptiveBrightnessTotal / adaptiveBrightnessCount);
      print("adaptive brightness coefficient: $adaptiveBrightnessCoefficient");
    }

    return {'vertices': vertices, 'faces': faces, 'colors': colors};
  }

  bool _shouldDrawFace(List face) {
    var normalVector = _normalVector3(vertices[face[0] - 1], vertices[face[1] - 1], vertices[face[2] - 1]);

    var dotProduct = normalVector.dot(camera);
    double vectorLengths = normalVector.length * camera.length;

    double angleBetween = dotProduct / vectorLengths;

    return angleBetween < 0;
  }

  Vector3 _normalVector3(Vector3 first, Vector3 second, Vector3 third) {
    Vector3 secondFirst = new Vector3.copy(second);
    secondFirst.sub(first);
    Vector3 secondThird = new Vector3.copy(second);
    secondThird.sub(third);

    return new Vector3(
        (secondFirst.y * secondThird.z) - (secondFirst.z * secondThird.y),
        (secondFirst.z * secondThird.x) - (secondFirst.x * secondThird.z),
        (secondFirst.x * secondThird.y) - (secondFirst.y * secondThird.x));
  }

  double _scalarMultiplication(Vector3 first, Vector3 second) {
    return (first.x * second.x) + (first.y * second.y) + (first.z * second.z);
  }

  Vector3 _calcDefaultVertex(Vector3 vertex) {
    T = new V.Matrix4.translationValues(_viewPortX, _viewPortY, zero);
    T.scale(zoomFactor, -zoomFactor);

    T.rotateX(_degreeToRadian(angleX != null ? angleX : 0.0));
    T.rotateY(_degreeToRadian(angleY != null ? angleY : 0.0));
    T.rotateZ(_degreeToRadian(angleZ != null ? angleZ : 0.0));

    return T.transform3(vertex);
  }

  double _degreeToRadian(double degree) {
    return degree * (Math.pi / 180.0);
  }

  List<dynamic> _drawFace(List<Vector3> verticesToDraw, List face, {Color color, double brightness = 1.0, Canvas canvas, bool lighting = false}) {
    List<dynamic> list = <dynamic>[];
    Paint paint = new Paint();
    Vector3 normalizedLight = new Vector3.copy(light).normalized();

    var normalVector =
        _normalVector3(verticesToDraw[face[0] - 1], verticesToDraw[face[1] - 1], verticesToDraw[face[2] - 1]);

    Vector3 jnv = new Vector3.copy(normalVector).normalized();

    double koef = _scalarMultiplication(jnv, normalizedLight);

    if (koef < 0.0) {
      koef = 0.0;
    }

    Color newColor = color;// ?? Color.fromARGB(255, 0, 0, 0);

    Path path = new Path();
    koef += (brightness - 1.0);

    if(adaptiveBrightnessCoefficient != null) koef *= adaptiveBrightnessCoefficient;

    newColor = newColor.withRed(Math.min((color.red.toDouble() * koef).round(), 255));
    newColor = newColor.withGreen(Math.min((color.green.toDouble() * koef).round(), 255));
    newColor = newColor.withBlue(Math.min((color.blue.toDouble() * koef).round(), 255));

    bool lastPoint = false;
    double firstVertexX, firstVertexY, secondVertexX, secondVertexY;

    //print(verticesToDraw[face[0] - 1]);

    if(lighting) {
      double t = ((verticesToDraw[face[0] - 1].z) + 25) / 150;
      newColor = Color.lerp(newColor, Colors.white, t);
    }

    paint.color = newColor;
    paint.style = PaintingStyle.fill;

    Float32List positions2D = Float32List(face.length * 2);
    Int32List colors = Int32List.fromList(List.filled(face.length, newColor.value));

    for (int i = 0; i < face.length; i++) {
      if (i + 1 == face.length) {
        lastPoint = true;
      }

      if (lastPoint) {
        firstVertexX = verticesToDraw[face[i] - 1][0].toDouble();
        firstVertexY = verticesToDraw[face[i] - 1][1].toDouble();
        secondVertexX = verticesToDraw[face[0] - 1][0].toDouble();
        secondVertexY = verticesToDraw[face[0] - 1][1].toDouble();
      } else {
        firstVertexX = verticesToDraw[face[i] - 1][0].toDouble();
        firstVertexY = verticesToDraw[face[i] - 1][1].toDouble();
        secondVertexX = verticesToDraw[face[i + 1] - 1][0].toDouble();
        secondVertexY = verticesToDraw[face[i + 1] - 1][1].toDouble();
        positions2D[(i+1) * 2 + 0] = secondVertexX;
        positions2D[(i+1) * 2 + 1] = secondVertexY;
      }

      if (i == 0) {
        positions2D[0] = firstVertexX;
        positions2D[1] = firstVertexY;
        path.moveTo(firstVertexX, firstVertexY);
      }

      path.lineTo(secondVertexX, secondVertexY);
      // positions2D[(i+1) * 2 + 0] = secondVertexX;
      // positions2D[(i+1) * 2 + 1] = secondVertexY;
    }
    // unused
    // var z = 0.0;
    // face.forEach((dynamic x) {
    //   int xx = x;
    //   z += verticesToDraw[xx - 1].z;
    // });

    Vertices vv = Vertices.raw(VertexMode.triangles, positions2D, colors: colors);
    if(canvas != null) canvas.drawVertices(vv, BlendMode.multiply, paint);

    path.close();
    list.add(path);
    list.add(paint);
    return list;
  }

  @override
  void paint(Canvas canvas, Size size) {
    DateTime startTime = DateTime.now();
    Map parsedFile = _parseObjString(object);
    vertices = parsedFile["vertices"];
    faces = parsedFile["faces"];
    colors = parsedFile["colors"];

    List<Vector3> verticesToDraw = [];
    vertices.forEach((vertex) {
      verticesToDraw.add(new Vector3.copy(vertex));
    });

    for (int i = 0; i < verticesToDraw.length; i++) {
      verticesToDraw[i] = _calcDefaultVertex(verticesToDraw[i]);
    }

    final List<Map> avgOfZ = List();
    for (int i = 0; i < faces.length; i++) {
      List face = faces[i];
      double z = 0.0;
      face.forEach((dynamic x) {
        int xx = x;
        z += verticesToDraw[xx - 1].z;
      });
      Map data = <String, dynamic>{
        "index": i,
        "z": z,
      };
      avgOfZ.add(data);
    }
    avgOfZ.sort((Map a, Map b) => a['z'].compareTo(b['z']));

    //print("Rendering OBJ Model..\nVertices: ${vertices.length}, Faces: ${faces.length}, Colors: ${colors.length}");

    for (int i = 0; i < faces.length; i++) {
      List face = faces[avgOfZ[i]["index"]];
      if (_shouldDrawFace(face) || true) {
        Color c = (flatColor != null) ? flatColor : colors[face[0] - 1];
        final List<dynamic> faceProp = _drawFace(verticesToDraw, face, color: c, brightness: brightness);
        canvas.drawPath(faceProp[0], faceProp[1]);
        //canvas.drawVertices(vertices, blendMode, paint);
      }
    }

    Duration renderTime = DateTime.now().difference(startTime);
    String fps = (1000/renderTime.inMilliseconds).toStringAsFixed(2);
    //print("Render Time: ${renderTime.inMilliseconds}ms (${(1000/renderTime.inMilliseconds).toStringAsFixed(2)} FPS)");
    if(postRenderCallback != null) postRenderCallback({'renderTime': renderTime.inMilliseconds, 'fps': fps, 'numVertices': vertices.length, 'numFaces': faces.length});
  }

  @override
  bool shouldRepaint(_ModelPainter old) =>
      old.object != object ||
      old.angleX != angleX ||
      old.angleY != angleY ||
      old.angleZ != angleZ ||
      old.zoomFactor != zoomFactor;
}
