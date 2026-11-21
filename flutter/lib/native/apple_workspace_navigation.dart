import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Embeds the system navigation bar on iOS or sidebar on macOS.
///
/// On iOS, place this inside the bottom safe area. It uses 64 logical pixels
/// in compact mode and 72 otherwise. On macOS, give the sidebar bounded width
/// and height. Callers supply their existing navigation on other platforms.
class AppleWorkspaceNavigation extends StatefulWidget {
  const AppleWorkspaceNavigation({
    super.key,
    required this.labels,
    required this.symbols,
    required this.selected,
    required this.onSelect,
    required this.compact,
  }) : assert(labels.length == symbols.length);

  final List<String> labels;
  final List<String> symbols;
  final int selected;
  final ValueChanged<int> onSelect;
  final bool compact;

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
        if (call.method == 'select') {
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
      return SizedBox(
        height: widget.compact ? 64 : 72,
        child: UiKitView(
          viewType: _viewType,
          creationParams: _configuration,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onPlatformViewCreated,
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
