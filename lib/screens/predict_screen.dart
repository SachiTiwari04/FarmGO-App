import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import '../ml/model_service.dart';

class PredictScreen extends StatefulWidget {
  @override
  _PredictScreenState createState() => _PredictScreenState();
}

class _PredictScreenState extends State<PredictScreen> {
  final picker = ImagePicker();
  final model = ModelService();
  String result = "No prediction yet";

  @override
  void initState() {
    super.initState();
    model.loadModels();
  }

  Future<void> pickImage() async {
    final picked = await picker.pickImage(source: ImageSource.gallery);

    if (picked != null) {
      Uint8List bytes = await picked.readAsBytes();
      img.Image decoded = img.decodeImage(bytes)!;

      final results = await model.predictBoth(decoded);
      String prediction = "General: ${results['general']} | Disease: ${results['disease']}";
      setState(() {
        result = prediction;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("FarmGo ML Predictor")),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(result, style: TextStyle(fontSize: 22)),
          SizedBox(height: 20),
          ElevatedButton(
            child: Text("Choose Image"),
            onPressed: pickImage,
          )
        ],
      ),
    );
  }
}