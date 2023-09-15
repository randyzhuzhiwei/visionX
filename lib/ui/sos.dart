import 'package:flutter/material.dart';
import 'package:live_object_detection_ssd_mobilenet/ui/home_view.dart';
import 'package:torch_light/torch_light.dart';
import 'dart:async';

class SosView extends StatelessWidget {
  const SosView({super.key});

  @override
  Widget build(BuildContext context) {
    Timer periodicHelpTimer;
    bool isTorchAvailable = false;
    bool isTorchOn = false;

    periodicHelpTimer = Timer.periodic(
      const Duration(seconds: 3),
      (timer) {
        if (!isTorchOn) {
          try {
            TorchLight.enableTorch();
            isTorchOn = true;
          } on Exception catch (_) {
            // Handle error
          }
        } else {
          try {
            TorchLight.disableTorch();
            isTorchOn = false;
          } on Exception catch (_) {
            // Handle error
          }
        }
      },
    );

    return Scaffold(
      key: GlobalKey(),
      backgroundColor: Colors.black,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Colors.white,
        title: Image.asset(
          'assets/images/tfl_logo.png',
          fit: BoxFit.contain,
        ),
      ),
      body: Container(
        alignment: Alignment.center,
        child: IconButton(
          icon: new Icon(Icons.stop_circle_rounded),
          color: Colors.white,
          iconSize: 230.0,
          onPressed: () {
            Navigator.pop(context);
            Navigator.push(context,
                MaterialPageRoute(builder: (BuildContext context) {
              return HomeView();
            }));
          },
        ),
      ),
    );
  }
}
