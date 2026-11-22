import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Embeds the system navigation bar on iOS or sidebar on macOS.
///
/// On iOS, place this in the bottom navigation slot. On macOS, give the sidebar
/// bounded width and height.
class AppleWorkspaceNavigation extends StatefulWidget {
  const AppleWorkspaceNavigation({
    super.key,
    required this.labels,
    required this.symbols,
    required this.selected,
    required this.onSelect,
    required this.compact,
    this.brand,
    this.settingsLabel,
    this.onSettings,
  }) : assert(labels.length == symbols.length);

  final List<String> labels;
  final List<String> symbols;
  final int selected;
  final ValueChanged<int> onSelect;
  final bool compact;
  final String? brand;
  final String? settingsLabel;
  final VoidCallback? onSettings;

  @override
  State<AppleWorkspaceNavigation> createState() =>
      _AppleWorkspaceNavigationState();
}

class _AppleWorkspaceNavigationState extends State<AppleWorkspaceNavigation> {
  static const _viewType = 'rustdesk/apple_workspace_navigation';
  MethodChannel? _channel;
  Brightness? _brightness;

  Map<String, Object> get _configuration => {
        'labels': widget.labels,
        'symbols': widget.symbols,
        'selected': widget.selected,
        'compact': widget.compact,
        if (widget.brand != null) 'brand': widget.brand!,
        if (widget.settingsLabel != null) 'settings': widget.settingsLabel!,
        'dark': _brightness == Brightness.dark,
      };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (_brightness != brightness) {
      _brightness = brightness;
      _updateNativeView();
    }
  }

  @override
  void didUpdateWidget(covariant AppleWorkspaceNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected ||
        widget.compact != oldWidget.compact ||
        widget.brand != oldWidget.brand ||
        widget.settingsLabel != oldWidget.settingsLabel ||
        !listEquals(widget.labels, oldWidget.labels) ||
        !listEquals(widget.symbols, oldWidget.symbols)) {
      _updateNativeView();
    }
  }

  void _onPlatformViewCreated(int viewId) {
    if (!mounted) return;
    _channel?.setMethodCallHandler(null);
    _channel = MethodChannel('$_viewType/$viewId')
      ..setMethodCallHandler((call) async {
        if (call.method == 'settings') {
          widget.onSettings?.call();
        } else if (call.method == 'select') {
          final index = call.arguments;
          if (index is int && index >= 0 && index < widget.labels.length) {
            widget.onSelect(index);
          }
        }
      });
    _updateNativeView();
  }

  void _updateNativeView() {
    if (_channel case final channel?) {
      unawaited(channel.invokeMethod<void>('update', _configuration));
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      final landscape =
          MediaQuery.orientationOf(context) == Orientation.landscape;
      final extraTextHeight =
          (MediaQuery.textScalerOf(context).scale(11) - 11).clamp(0.0, 40.0);
      final height = widget.compact
          ? (landscape ? 52.0 : 63.0) + extraTextHeight
          : 72.0;
      final width = widget.compact ? 440.0 : widget.labels.length * 124.0 + 16;
      final margin = widget.compact ? 20.0 : 12.0;
      final bottomGap = widget.compact
          ? (MediaQuery.viewPaddingOf(context).bottom * 0.6)
              .clamp(8.0, 20.0)
              .toDouble()
          : 6.0;
      return SafeArea(
        top: false,
        bottom: !widget.compact,
        minimum: EdgeInsets.fromLTRB(margin, 0, margin, bottomGap),
        child: Align(
          heightFactor: 1,
          child: SizedBox(
            width: width,
            height: height,
            child: ClipPath.shape(
              shape: const StadiumBorder(),
              child: UiKitView(
                key: ValueKey(widget.compact),
                viewType: _viewType,
                creationParams: _configuration,
                creationParamsCodec: const StandardMessageCodec(),
                onPlatformViewCreated: _onPlatformViewCreated,
              ),
            ),
          ),
        ),
      );
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      return AppKitView(
        viewType: _viewType,
        creationParams: _configuration,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      );
    }
    return const SizedBox.shrink();
  }
}
