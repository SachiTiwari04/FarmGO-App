import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'dart:math';


class ModelService {
  // --------- SINGLETON ---------
  static final ModelService _instance = ModelService._internal();
  factory ModelService() => _instance;
  ModelService._internal();
  // -----------------------------

  late Interpreter generalModel;
  late Interpreter diseaseModel;
  late List<String> generalLabels;
  late List<String> diseaseLabels;

  bool isLoaded = false;

  // Load both models once
  Future<void> loadModels() async {
    if (isLoaded) return;

    generalModel =
    await Interpreter.fromAsset('assets/ml/best_image_model.tflite');
    diseaseModel =
    await Interpreter.fromAsset('assets/ml/animal_disease_classifier.tflite');

    generalLabels =
        (await rootBundle.loadString('assets/ml/labels.txt')).split("\n");

    diseaseLabels =
        (await rootBundle.loadString('assets/ml/disease_labels.txt')).split("\n");

    isLoaded = true;
  }

  Future<Map<String, dynamic>> predictBoth(img.Image image) async {
    final input = _preprocess(image);

    final generalOutput =
    List.generate(1, (_) => List.filled(generalLabels.length, 0.0));

    final diseaseOutput =
    List.generate(1, (_) => List.filled(diseaseLabels.length, 0.0));

    generalModel.run(input, generalOutput);
    diseaseModel.run(input, diseaseOutput);

    // Apply softmax to convert raw logits → probabilities
    List<double> generalProb = _softmax(generalOutput[0]);
    List<double> diseaseProb = _softmax(diseaseOutput[0]);

    int generalIndex = _argmax(generalProb);
    int diseaseIndex = _argmax(diseaseProb);

    double finalConfidence =
        ((generalProb[generalIndex] + diseaseProb[diseaseIndex]) / 2) * 100;

    return {
      'general': generalLabels[generalIndex],
      'disease': diseaseLabels[diseaseIndex],
      'confidence': finalConfidence,
    };
  }

  int _argmax(List<double> list) {
    double max = -999;
    int idx = 0;
    for (int i = 0; i < list.length; i++) {
      if (list[i] > max) {
        max = list[i];
        idx = i;
      }
    }
    return idx;
  }
  // Convert logits → probability distribution
  List<double> _softmax(List<double> logits) {
    double maxLogit = logits.reduce((a, b) => a > b ? a : b);

    // Shift logits for numerical stability
    List<double> expValues =
    logits.map((x) => (x - maxLogit)).map((x) => exp(x)).toList();

    double sumExp = expValues.reduce((a, b) => a + b);

    return expValues.map((x) => x / sumExp).toList();
  }

  // ---- FIXED PREPROCESSING ----
  // Your model requires **128x128 RGB normalized**
  List<List<List<List<double>>>> _preprocess(img.Image image) {
    const int size = 128;

    img.Image resized = img.copyResize(image, width: size, height: size);

    return [
      List.generate(size, (y) {
        return List.generate(size, (x) {
          final p = resized.getPixel(x, y);
          return [
            p.r / 255.0,
            p.g / 255.0,
            p.b / 255.0,
          ];
        });
      })
    ];
  }
}
