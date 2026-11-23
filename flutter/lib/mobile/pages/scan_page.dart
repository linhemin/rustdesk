import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/workspace.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'package:zxing2/qrcode.dart';

import '../../common.dart';
import '../../models/platform_model.dart';
import '../server_config_qr.dart';
import '../widgets/dialog.dart';

Uri? connectionQrUri(String code, String uriPrefix) {
  final uri = Uri.tryParse(code);
  if (!code.startsWith(uriPrefix) ||
      uri == null ||
      const {'config', 'password'}.contains(uri.authority)) {
    return null;
  }
  return uri;
}

class ScanPage extends StatefulWidget {
  static Future<void> openConnection(BuildContext context) async {
    final result = await Navigator.of(context).push(
        MaterialPageRoute<({String code, bool gallery})>(
            builder: (_) => ScanPage()));
    if (result == null || !context.mounted) return;
    final uri = connectionQrUri(result.code, bind.mainUriPrefixSync());
    if (uri != null) {
      handleUriLink(uri: uri);
    } else {
      showToast(translate('Invalid QR code'));
    }
  }

  static Future<void> open(BuildContext context,
      {ValueChanged<ServerConfig>? onServerConfig}) async {
    final result = await Navigator.of(context).push(
        MaterialPageRoute<({String code, bool gallery})>(
            builder: (_) => ScanPage()));
    if (result == null || !context.mounted) return;
    if (onServerConfig != null) {
      final config =
          serverConfigFromQr(result.code, uriPrefix: bind.mainUriPrefixSync());
      if (config != null) {
        try {
          onServerConfig(ServerConfig.decode(config));
        } catch (_) {
          showToast('Invalid QR code');
        }
        return;
      }
    }
    if (result.gallery && result.code.startsWith(bind.mainUriPrefixSync())) {
      handleUriLink(uriString: result.code);
      return;
    }
    if (!result.code.startsWith('config=')) {
      showToast('Invalid QR code');
      return;
    }
    final ServerConfig config;
    try {
      config = ServerConfig.decode(result.code.substring(7));
    } catch (_) {
      showToast('Invalid QR code');
      return;
    }
    showServerSettingsWithValue(config, gFFI.dialogManager, null);
  }

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  QRViewController? controller;
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  StreamSubscription<Barcode>? scanSubscription;
  bool _pickingImage = false;

  bool get _acceptsResult =>
      mounted &&
      ModalRoute.of(context)?.isCurrent == true &&
      !Navigator.of(context).userGestureInProgress;

  @override
  void reassemble() {
    super.reassemble();
    if (isAndroid && controller != null) {
      controller!.pauseCamera();
    } else if (controller != null) {
      controller!.resumeCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR'),
        actions: [
          _buildImagePickerButton(),
          _buildFlashToggleButton(),
          _buildCameraSwitchButton(),
        ],
      ),
      body: _buildQrView(context),
    );
  }

  Widget _buildQrView(BuildContext context) {
    var scanArea = MediaQuery.of(context).size.width < 400 ||
            MediaQuery.of(context).size.height < 400
        ? 150.0
        : 300.0;
    return QRView(
      key: qrKey,
      onQRViewCreated: _onQRViewCreated,
      overlay: QrScannerOverlayShape(
        borderColor: isIOS ? WorkspaceStyle.ice : Colors.red,
        borderRadius: isIOS ? 16 : 10,
        borderLength: 30,
        borderWidth: isIOS ? 4 : 10,
        cutOutSize: scanArea,
      ),
      onPermissionSet: (_, granted) {
        if (!granted && _acceptsResult) showToast('No permission');
      },
    );
  }

  void _onQRViewCreated(QRViewController controller) {
    if (!mounted) return;
    this.controller = controller;
    scanSubscription?.cancel();
    scanSubscription = controller.scannedDataStream.listen((scanData) {
      final code = scanData.code;
      if (!_pickingImage && code != null && _acceptsResult) {
        Navigator.of(context).pop((code: code, gallery: false));
      }
    });
  }

  Future<void> _pickImage() async {
    if (_pickingImage) return;
    _pickingImage = true;
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file != null && _acceptsResult) {
        final bytes = await File(file.path).readAsBytes();
        if (!_acceptsResult) return;
        var image = img.decodeImage(bytes)!;
        LuminanceSource source = RGBLuminanceSource(
          image.width,
          image.height,
          image.getBytes(order: img.ChannelOrder.abgr).buffer.asInt32List(),
        );
        var bitmap = BinaryBitmap(HybridBinarizer(source));

        var reader = QRCodeReader();
        var result = reader.decode(bitmap);
        Navigator.of(context).pop((code: result.text, gallery: true));
      }
    } catch (e) {
      if (_acceptsResult) showToast('No QR code found');
    } finally {
      _pickingImage = false;
    }
  }

  Widget _buildImagePickerButton() {
    return IconButton(
      color: Colors.white,
      icon: Icon(Icons.image_search),
      iconSize: 32.0,
      onPressed: _pickImage,
    );
  }

  Widget _buildFlashToggleButton() {
    return IconButton(
      color: Colors.yellow,
      icon: Icon(Icons.flash_on),
      iconSize: 32.0,
      onPressed: () async {
        await controller?.toggleFlash();
      },
    );
  }

  Widget _buildCameraSwitchButton() {
    return IconButton(
      color: Colors.white,
      icon: Icon(Icons.switch_camera),
      iconSize: 32.0,
      onPressed: () async {
        await controller?.flipCamera();
      },
    );
  }

  @override
  void dispose() {
    scanSubscription?.cancel();
    super.dispose();
  }
}
