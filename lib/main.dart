import 'package:flutter/material.dart';
import 'model_viewer.dart';

void main() {
  runApp(new MyApp());
}

class MyApp extends StatefulWidget{
  MyApp();

  double brightness = 3.0;

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      title: 'OBJ Model Viewer Demo',
      home: new Scaffold(
        appBar: new AppBar(
          title: const Text("OBJ Viewer"),
        ),
        body: new Center(
          child: new ModelViewer(
            size: const Size(400.0, 400.0),
            path: "assets/6k.obj",
            asset: true,
            zoom: 200.0,
            brightness: widget.brightness,
            allowRotateY: false,
            adaptiveBrightness: 40,
            angleY: 135,
            angleZ: 90,
            //flatColor: Colors.blueAccent,
            postRenderCallback: (data){
              print('Rendered OBJ model with ${data['numVertices']} verts and ${data['numFaces']} faces\n'
                  'Time taken ${data['renderTime']}ms (${data['fps']} FPS)');
            },
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            FloatingActionButton(
              child: Icon(Icons.brightness_low),
              onPressed: (){
                setState(() {
                  widget.brightness -= 0.5;
                });
              },
            ),
            FloatingActionButton(
              child: Icon(Icons.brightness_high),
              onPressed: (){
                setState(() {
                  widget.brightness += 0.5;
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}
