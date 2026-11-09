import 'dart:io';

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import 'result_page.dart';

class CapturePage extends StatefulWidget {
  final String carId;
  final String position; // FL/FR/RL/RR/SPARE
  final String scanMode; // "sidewall" | "tread"
  final double? prevDepth;
  final String? prevUpdateDate;

  const CapturePage({
    super.key,
    required this.carId,
    required this.position,
    required this.scanMode,
    this.prevDepth,
    this.prevUpdateDate,
  });

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  CameraController? _controller;
  bool _flashOn = false;
  bool _busy = false;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initCam();
  }

  Future<void> _initCam() async {
    final cams = await availableCameras();
    final cam = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cams.first,
    );
    _controller = CameraController(
      cam,
      ResolutionPreset.max,
      enableAudio: false,
    );
    await _controller!.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;
    _flashOn = !_flashOn;
    await _controller!.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
    if (mounted) setState(() {});
  }

  Future<void> _takeAndSend() async {
    if (_controller == null || !_controller!.value.isInitialized || _busy) {
      return;
    }
    // Don't set _busy = true here, let camera take picture first
    try {
      final x = await _controller!.takePicture();
      // Now set busy to show overlay while sending
      setState(() => _busy = true);
      await _sendFile(File(x.path));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFromGalleryAndSend() async {
    if (_busy) return;
    // Don't set _busy = true here, waiting for picker UI
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
      );
      if (picked == null) return;

      // Now set busy to show overlay while sending
      setState(() => _busy = true);
      await _sendFile(File(picked.path));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// ส่งรูปไป backend AI inference — ใช้ endpoint ใหม่ที่ stateless (/api/infer/scan)
  Future<void> _sendFile(File file) async {
    try {
      final form = FormData.fromMap({
        "mode": widget.scanMode,
        "image": await MultipartFile.fromFile(file.path, filename: "tire.jpg"),
      });

      final res = await Api.dio().post("/api/infer/scan", data: form);

      if (!mounted) return;

      // ไปหน้า Result เพื่อให้ user "ตรวจ/แก้/ยืนยัน"
      final confirmed = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (_) => ResultPage(
            scanMode: widget.scanMode,
            position: widget.position,
            result: res.data as Map<String, dynamic>,
            prevDepth: widget.prevDepth,
            prevUpdateDate: widget.prevUpdateDate,
          ),
        ),
      );

      // ถ้า user ยืนยันผล (ไม่ได้กดถ่ายใหม่) → ส่งค่ากลับ HomePage
      if (!mounted) return;
      if (confirmed != null) {
        Navigator.pop(context, confirmed);
      }
      // ถ้า confirmed == null หมายความว่า user กด "ถ่ายใหม่"
      // → ค้างอยู่ที่ CapturePage เพื่อถ่ายใหม่ได้เลย
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Upload failed: $e")));
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String _getThaiPos(String pos) {
    switch (pos) {
      case 'FL': return 'หน้าซ้าย';
      case 'FR': return 'หน้าขวา';
      case 'RL': return 'หลังซ้าย';
      case 'RR': return 'หลังขวา';
      case 'SPARE': return 'อะไหล่';
      default: return pos;
    }
  }

  String get _title {
    final modeText = widget.scanMode == "sidewall"
        ? "แก้มยาง "
        : "ดอกยาง";
    return "$modeText${_getThaiPos(widget.position)}";
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(_title)),
      body: c == null || !c.value.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: ClipRect(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            var parentRatio =
                                constraints.maxWidth / constraints.maxHeight;
                            var cameraRatio = c.value.aspectRatio;
                            if (cameraRatio > 1) {
                              cameraRatio = 1 / cameraRatio;
                            }
                            double scale = 1.0;
                            if (cameraRatio < parentRatio) {
                              scale = parentRatio / cameraRatio;
                            } else {
                              scale = cameraRatio / parentRatio;
                            }
                            return Transform.scale(
                              scale: scale,
                              child: Center(child: CameraPreview(c)),
                            );
                          },
                        ),
                      ),
                    ),
                    Container(
                      color: Colors.black,
                      padding: const EdgeInsets.only(
                        top: 20,
                        bottom: 40,
                        left: 30,
                        right: 30,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Flash (Left)
                          IconButton(
                            onPressed: _toggleFlash,
                            icon: Icon(
                              _flashOn ? Icons.flash_on : Icons.flash_off,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),

                          // Shutter (Center)
                          GestureDetector(
                            onTap: _busy ? null : _takeAndSend,
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 4,
                                ),
                                color: Colors.white24,
                              ),
                              child: Center(
                                child: Container(
                                  width: 64,
                                  height: 64,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Gallery (Right)
                          IconButton(
                            onPressed: _busy ? null : _pickFromGalleryAndSend,
                            icon: const Icon(
                              Icons.photo_library,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Loading Overlay
                if (_busy)
                  Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: Colors.black,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            color: Color(0xFFFFD700),
                            strokeWidth: 3,
                          ),
                          SizedBox(height: 28),
                          Text(
                            "AI กำลังวิเคราะห์...",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            "กรุณารอสักครู่",
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
