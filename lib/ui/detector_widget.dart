import 'dart:async';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:live_object_detection_ssd_mobilenet/models/recognition.dart';
import 'package:live_object_detection_ssd_mobilenet/models/screen_params.dart';
import 'package:live_object_detection_ssd_mobilenet/service/detector_service.dart';
import 'package:live_object_detection_ssd_mobilenet/ui/box_widget.dart';
import 'package:live_object_detection_ssd_mobilenet/ui/sos.dart';
import 'package:live_object_detection_ssd_mobilenet/ui/stats_widget.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

/// [DetectorWidget] sends each frame for inference
class DetectorWidget extends StatefulWidget {
  /// Constructor
  const DetectorWidget({super.key});

  @override
  State<DetectorWidget> createState() => _DetectorWidgetState();
}

enum TtsState { playing, stopped, paused, continued }

class _DetectorWidgetState extends State<DetectorWidget>
    with WidgetsBindingObserver {
  late FlutterTts flutterTts;
  late Timer periodicTimer;

  bool isCurrentLanguageInstalled = false;

  String _newVoiceText = "";

  bool isSpoken = false;

  /// List of available cameras
  late List<CameraDescription> cameras;

  /// Controller
  CameraController? _cameraController;

  // use only when initialized, so - not null
  get _controller => _cameraController;

  /// Object Detector is running on a background [Isolate]. This is nullable
  /// because acquiring a [Detector] is an asynchronous operation. This
  /// value is `null` until the detector is initialized.
  Detector? _detector;
  StreamSubscription? _subscription;

  /// Results to draw bounding boxes
  List<Recognition>? results;

  /// Realtime stats
  Map<String, String>? stats;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initStateAsync();

    initTts();
  }

  void _initStateAsync() async {
    // initialize preview and CameraImage stream
    _initializeCamera();
    // Spawn a new isolate
    Detector.start().then((instance) {
      setState(() {
        _detector = instance;
        _subscription = instance.resultsStream.stream.listen((values) {
          setState(() {
            results = values['recognitions'];
            stats = values['stats'];
          });
        });
      });
    });
  }

  initTts() {
    flutterTts = FlutterTts();
    flutterTts.setLanguage("en-US");
    flutterTts.setSpeechRate(0.4); //speed of speech
    flutterTts.setVolume(1.0); //volume of speech
    flutterTts.setPitch(1); //pitch of sound

    flutterTts.speak("You are now in spotting obstacles mode");
    activateObstacles();
  }

  void activateObstacles() {
    periodicTimer = Timer.periodic(
      const Duration(seconds: 5),
      (timer) {
        // Update user about remaining time
        var result = flutterTts.speak(_newVoiceText);

        print("TTS-result:" + result.toString());
        print("TTS:" + _newVoiceText);
        isSpoken = true;
        _newVoiceText = "";
      },
    );
  }

  /// Initializes the camera by setting [_cameraController]
  void _initializeCamera() async {
    cameras = await availableCameras();
    // cameras[0] for back-camera
    _cameraController = CameraController(
      cameras[0],
      ResolutionPreset.medium,
      enableAudio: false,
    )..initialize().then((_) async {
        await _controller.startImageStream(onLatestImageAvailable);
        setState(() {});

        /// previewSize is size of each image frame captured by controller
        ///
        /// 352x288 on iOS, 240p (320x240) on Android with ResolutionPreset.low
        ScreenParams.previewSize = _controller.value.previewSize!;
      });
  }

  @override
  Widget build(BuildContext context) {
    // Return empty container while the camera is not initialized
    if (_cameraController == null || !_controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    var aspect = 1 / _controller.value.aspectRatio;

    return Stack(
      children: [
        AspectRatio(
          aspectRatio: aspect,
          child: CameraPreview(_controller),
        ),
        // Stats
        _sosWidget(),
        //_statsWidget(),
        // Bounding boxes
        AspectRatio(
          aspectRatio: aspect,
          child: _boundingBoxes(),
        ),
      ],
    );
  }

  Widget _sosWidget() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        child: IconButton(
          icon: new Icon(Icons.sos_rounded),
          color: Colors.white,
          iconSize: 230.0,
          onPressed: () {
            Navigator.of(context).pop();
            Navigator.push(context,
                MaterialPageRoute(builder: (BuildContext context) {
              return SosView();
            }));
          },
        ),
      ),
    );
  }

  Widget _statsWidget() => (stats != null)
      ? Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            color: Colors.white.withAlpha(150),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: stats!.entries
                    .map((e) => StatsWidget(e.key, e.value))
                    .toList(),
              ),
            ),
          ),
        )
      : const SizedBox.shrink();

  /// Returns Stack of bounding boxes
  Widget _boundingBoxes() {
    if (results == null) {
      return const SizedBox.shrink();
    }
    if (isSpoken) {
      String direction;
      results!.forEach((element) {
        if (element.score > 0.5) {
          if (element.location.left > 150) {
            direction = "right";
          } else {
            direction = "left";
          }
          if (element.location.width > 100) {
            direction = "front";
          }
          _newVoiceText = _newVoiceText +
              " " +
              element.label +
              " to your " +
              direction +
              ".";
        }
      });
      if (_newVoiceText != "") {
        isSpoken = false;
      }
    }

    return Stack(
        children: results!.map((box) => BoxWidget(result: box)).toList());
  }

  /// Callback to receive each frame [CameraImage] perform inference on it
  void onLatestImageAvailable(CameraImage cameraImage) async {
    _detector?.processFrame(cameraImage);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.inactive:
        _cameraController?.stopImageStream();
        _detector?.stop();
        _subscription?.cancel();
        break;
      case AppLifecycleState.resumed:
        _initStateAsync();
        break;
      default:
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _detector?.stop();
    _subscription?.cancel();
    super.dispose();
  }
}
