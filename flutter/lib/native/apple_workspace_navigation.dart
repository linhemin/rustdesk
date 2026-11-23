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
    this.onQuickConnect,
    this.quickConnectLabel,
    this.navigationOnly = false,
  }) : assert(labels.length == symbols.length);

  final List<String> labels;
  final List<String> symbols;
  final int selected;
  final ValueChanged<int> onSelect;
  final bool compact;
  final String? brand;
  final String? settingsLabel;
  final VoidCallback? onSettings;
  final VoidCallback? onQuickConnect;
  final String? quickConnectLabel;
  final bool navigationOnly;

  @override
  State<AppleWorkspaceNavigation> createState() =>
      _AppleWorkspaceNavigationState();
}

class _AppleWorkspaceNavigationState extends State<AppleWorkspaceNavigation> {
  static const _viewType = 'rustdesk/apple_workspace_navigation';
  static const _layoutChannel = MethodChannel('$_viewType/layout');
  MethodChannel? _channel;
  Brightness? _brightness;
  bool? _hasSystemTabs;
  double? _systemHeight;
  Size? _viewport;
  EdgeInsets? _viewPadding;

  Map<String, Object> get _configuration => {
        'labels': widget.labels,
        'symbols': widget.symbols,
        'selected': widget.selected,
        'compact': widget.compact,
        if (widget.navigationOnly) 'navigationOnly': true,
        if (widget.brand != null) 'brand': widget.brand!,
        if (widget.settingsLabel != null) 'settings': widget.settingsLabel!,
        'dark': _brightness == Brightness.dark,
        if (widget.onQuickConnect != null) ...{
          'quickConnect': widget.quickConnectLabel ?? widget.labels.first,
          'rtl': Directionality.of(context) == TextDirection.rtl,
          'textScale': MediaQuery.textScalerOf(context).scale(10) / 10,
        },
      };

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      unawaited(_resolveSystemTabs());
    }
  }

  Future<void> _resolveSystemTabs() async {
    var available = false;
    try {
      available =
          await _layoutChannel.invokeMethod<bool>('usesSystemTabs') ?? false;
    } on MissingPluginException {
      // Older native hosts continue to use the compatibility layout.
    }
    if (mounted) setState(() => _hasSystemTabs = available);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      final viewport = MediaQuery.sizeOf(context);
      final padding = MediaQuery.viewPaddingOf(context);
      if (_viewport != viewport || _viewPadding != padding) {
        _viewport = viewport;
        _viewPadding = padding;
        if (_systemHeight != null) {
          _systemHeight = null;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _updateNativeView();
          });
        }
      }
    }
    final brightness = Theme.of(context).brightness;
    if (_brightness != brightness) {
      _brightness = brightness;
      _updateNativeView();
    }
    if (widget.onQuickConnect != null) _updateNativeView();
  }

  @override
  void didUpdateWidget(covariant AppleWorkspaceNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected ||
        widget.compact != oldWidget.compact ||
        widget.navigationOnly != oldWidget.navigationOnly ||
        widget.brand != oldWidget.brand ||
        widget.settingsLabel != oldWidget.settingsLabel ||
        widget.quickConnectLabel != oldWidget.quickConnectLabel ||
        (widget.onQuickConnect == null) != (oldWidget.onQuickConnect == null) ||
        !listEquals(widget.labels, oldWidget.labels) ||
        !listEquals(widget.symbols, oldWidget.symbols)) {
      _updateNativeView();
    }
  }

  void _onPlatformViewCreated(int viewId) {
    if (!mounted) return;
    _channel?.setMethodCallHandler(null);
    final channel = MethodChannel('$_viewType/$viewId');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (!mounted || _channel != channel) return;
      if (call.method == 'settings') {
        widget.onSettings?.call();
      } else if (call.method == 'quickConnect') {
        widget.onQuickConnect?.call();
      } else if (call.method == 'select') {
        final index = call.arguments;
        if (index is int && index >= 0 && index < widget.labels.length) {
          widget.onSelect(index);
        }
      } else if (call.method == 'systemHeight') {
        _setSystemHeight(call.arguments);
      }
    });
    _updateNativeView();
  }

  void _updateNativeView() {
    if (_channel case final channel?) {
      unawaited(_sendConfiguration(channel));
    }
  }

  Future<void> _sendConfiguration(MethodChannel channel) async {
    final height = await channel.invokeMethod<Object>('update', _configuration);
    if (mounted && _channel == channel) _setSystemHeight(height);
  }

  void _setSystemHeight(Object? value) {
    if (!widget.compact || _hasSystemTabs != true || value is! num) return;
    final height = value.toDouble();
    if (!height.isFinite || height <= 0 || height == _systemHeight) return;
    setState(() => _systemHeight = height);
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  double _phoneWidth(BuildContext context) {
    final caption = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    );
    // UIKit reserves horizontal space inside the host before sizing the glass.
    // A 222 pt host compresses the standard two-item bar by 8 pt on iPhone.
    var itemWidth = _hasSystemTabs == true ? 110.0 : 106.0;
    for (final label in widget.labels) {
      caption.text = TextSpan(
          text: label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600));
      caption.layout();
      if (caption.width + 28 > itemWidth) itemWidth = caption.width + 28;
    }
    caption.dispose();
    // Keep the compact host wide enough for the longest localized caption.
    return itemWidth * widget.labels.length + 10;
  }

  UiKitView _iosView() => UiKitView(
        key: ValueKey((widget.compact, widget.onQuickConnect != null)),
        viewType: _viewType,
        creationParams: _configuration,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      );

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      if (widget.onQuickConnect != null) {
        final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
        final height = 54.0 + (10 * (textScale - 1)).clamp(0.0, 40.0);
        return SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Align(
            heightFactor: 1,
            child: SizedBox(
              width: widget.labels.length * 78.0 + 8 + 60,
              height: height,
              // Keep the shadow outside the native clip without blocking its gaps.
              child: PhysicalShape(
                clipper: _QuickConnectDockClipper(Directionality.of(context)),
                color: Colors.transparent,
                shadowColor: _brightness == Brightness.dark
                    ? Colors.black.withOpacity(0.48)
                    : const Color(0xff0f172a).withOpacity(0.14),
                elevation: _brightness == Brightness.dark ? 12 : 10,
                clipBehavior: Clip.antiAlias,
                child: _iosView(),
              ),
            ),
          ),
        );
      }
      if (widget.compact && _hasSystemTabs != false) {
        // Start with enough space to lay out UIKit. It then supplies the occupied
        // height, including the device's bottom safe area.
        final height =
            _systemHeight ?? 84.0 + MediaQuery.viewPaddingOf(context).bottom;
        return SafeArea(
          top: false,
          bottom: false,
          minimum: const EdgeInsets.symmetric(horizontal: 20),
          child: Align(
            heightFactor: 1,
            child: SizedBox(
              width: _phoneWidth(context),
              height: height,
              child: _hasSystemTabs == true ? _iosView() : null,
            ),
          ),
        );
      }
      final landscape =
          MediaQuery.orientationOf(context) == Orientation.landscape;
      final extraTextHeight =
          (MediaQuery.textScalerOf(context).scale(11) - 11).clamp(0.0, 40.0);
      final height =
          widget.compact ? (landscape ? 52.0 : 63.0) + extraTextHeight : 72.0;
      final width = widget.compact
          ? _phoneWidth(context)
          : widget.labels.length * 124.0 + 16;
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
              child: _iosView(),
            ),
          ),
        ),
      );
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      return AppKitView(
        key: ValueKey(widget.navigationOnly),
        viewType: _viewType,
        creationParams: _configuration,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      );
    }
    return const SizedBox.shrink();
  }
}

class _QuickConnectDockClipper extends CustomClipper<Path> {
  const _QuickConnectDockClipper(this.direction);
  final TextDirection direction;

  @override
  Path getClip(Size size) {
    final rtl = direction == TextDirection.rtl;
    final tabs = Rect.fromLTWH(rtl ? 60 : 0, 0, size.width - 60, size.height);
    final action = Rect.fromLTWH(
        rtl ? 0 : size.width - 50, (size.height - 50) / 2, 50, 50);
    return Path()
      ..addRRect(
          RRect.fromRectAndRadius(tabs, Radius.circular(size.height / 2)))
      ..addOval(action);
  }

  @override
  bool shouldReclip(_QuickConnectDockClipper oldClipper) =>
      direction != oldClipper.direction;
}
