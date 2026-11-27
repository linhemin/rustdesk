import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../session_viewport.dart';

/// Pure geometry and hit-testing mirroring `AwesunControlLayout` in iOS Swift.
enum AwesunMouseRegion {
  hub,
  left,
  right,
  wheelTop,
  wheelBottom,
  ring,
  close,
}

class AwesunMouseLayout {
  const AwesunMouseLayout({
    required this.center,
    required this.pointer,
    required this.minCenter,
    required this.maxCenter,
  });

  final Offset center;
  final Offset pointer;
  final Offset minCenter;
  final Offset maxCenter;
}

class AwesunControlGeometry {
  AwesunControlGeometry._();

  static const double hubRadius = 31;
  static const double arcRadius = 61;
  static const double arcWidth = 29;
  static const double arcSpanDeg = 37;
  static const double wheelOffset = 59;
  static const double wheelRadius = 14;
  static const Offset closeOffset = Offset(70, -70);
  static const double ringRadius = 60;
  static const double ringThickness = 28;
  static const double mouseSize = 188;
  static const Offset pointerGap = Offset(90, 70);
  static const double controlRadius = 20;
  static const double controlEdge = 14;

  static AwesunMouseLayout layoutFor(
    Offset? anchor,
    Size size, {
    double bottomObstruction = 0,
  }) {
    final areaHeight = math.max(1.0, size.height - bottomObstruction);
    final rightMargin = arcRadius + arcWidth / 2;
    final lowerMargin = wheelOffset + wheelRadius;
    final minCenter = Offset(
      math.min(pointerGap.dx, size.width / 2),
      math.min(pointerGap.dy, areaHeight / 2),
    );
    final maxCenter = Offset(
      math.max(minCenter.dx, size.width - rightMargin),
      math.max(minCenter.dy, areaHeight - lowerMargin),
    );
    final raw = anchor ?? Offset(size.width * 0.62, areaHeight * 0.56);
    final center = Offset(
      raw.dx.clamp(minCenter.dx, maxCenter.dx),
      raw.dy.clamp(minCenter.dy, maxCenter.dy),
    );
    final pointer = Offset(
      (center.dx - pointerGap.dx).clamp(4.0, math.max(4.0, size.width - 4.0)),
      (center.dy - pointerGap.dy).clamp(4.0, math.max(4.0, areaHeight - 4.0)),
    );
    return AwesunMouseLayout(
      center: center,
      pointer: pointer,
      minCenter: minCenter,
      maxCenter: maxCenter,
    );
  }

  /// Hit-test a local point relative to the mouse center (0, 0).
  static AwesunMouseRegion? hitRegion(
    Offset localFromCenter, {
    required bool wheelOpen,
  }) {
    if ((localFromCenter - closeOffset).distance <= 17) {
      return AwesunMouseRegion.close;
    }
    if (wheelOpen) {
      final d = localFromCenter.distance;
      return (d - ringRadius).abs() <= ringThickness / 2 + 4
          ? AwesunMouseRegion.ring
          : null;
    }
    if (localFromCenter.distance <= hubRadius) {
      return AwesunMouseRegion.hub;
    }
    if ((localFromCenter - const Offset(0, -wheelOffset)).distance <= 20) {
      return AwesunMouseRegion.wheelTop;
    }
    if ((localFromCenter - const Offset(0, wheelOffset)).distance <= 20) {
      return AwesunMouseRegion.wheelBottom;
    }
    final dist = localFromCenter.distance;
    if ((dist - arcRadius).abs() <= arcWidth / 2 + 4) {
      final deg =
          math.atan2(localFromCenter.dy, localFromCenter.dx) * 180 / math.pi;
      if (deg.abs() <= arcSpanDeg + 6) {
        return AwesunMouseRegion.right;
      }
      if ((180 - deg.abs()).abs() <= arcSpanDeg + 6) {
        return AwesunMouseRegion.left;
      }
    }
    return null;
  }
}

class AwesunVisualPalette {
  AwesunVisualPalette._();

  static const mouseFill = Color(0xBA141B28);
  static const mouseStroke = Color(0x47FFFFFF);
  static const activeBlue = Color(0xE03B82F6);
  static const activeIce = Color(0xFF60A5FA);
  static const activeStroke = Color(0xE693C5FD);
  static const sheetFill = Color(0xF2101622);
  static const orbFill = Color(0xDC141B28);
  static const ink = Color(0xFFF1F5FA);
  static const dim = Color(0x9EE2EAF6);
  static const danger = Color(0xFFEF4444);
  static const amber = Color(0xFFF59E0B);
}

/// Unified Flutter implementation of the Awesun (仿向日葵) remote session overlay
/// for Android (matching the iOS native Swift AwesunSessionView visuals & logic).
class AwesunFlutterOverlay extends StatefulWidget {
  const AwesunFlutterOverlay({
    super.key,
    required this.touchMode,
    required this.canInput,
    required this.canSwitchMode,
    required this.displayLocked,
    required this.soundOn,
    required this.qualityVisible,
    required this.displayCount,
    required this.onMovePointer,
    required this.onLeftClick,
    required this.onRightClick,
    required this.onMiddleClick,
    required this.onLeftDragStart,
    required this.onLeftDragEnd,
    required this.onScroll,
    required this.onToggleLock,
    required this.onSelectTouchMode,
    required this.onOpenSystemKeyboard,
    required this.onOpenVirtualKeyboard,
    required this.onOpenDisplaySettings,
    required this.onToggleQuality,
    required this.onOpenChat,
    required this.onOpenMore,
    required this.onDisconnect,
    this.onToggleSound,
    this.onSwitchDisplay,
    this.onPointerVisibilityChanged,
    this.onPanCanvas,
    this.onMinimize,
    this.onScreenshot,
    this.showRemoteCursor = false,
    this.canShowRemoteCursor = false,
    this.onToggleRemoteCursor,
    this.translateLabel,
    this.initialMouseVisible = true,
    this.initialMouseCollapsed = false,
    this.showFirstRunTour = false,
    this.onDismissFirstRunTour,
  });

  final bool touchMode;
  final bool canInput;
  final bool canSwitchMode;
  final bool displayLocked;
  final bool soundOn;
  final bool qualityVisible;
  final int displayCount;
  final ValueChanged<Offset> onMovePointer;
  final ValueChanged<Offset> onLeftClick;
  final ValueChanged<Offset> onRightClick;
  final ValueChanged<Offset> onMiddleClick;
  final ValueChanged<Offset> onLeftDragStart;
  final VoidCallback onLeftDragEnd;
  final void Function(int steps, Offset pointer) onScroll;
  final VoidCallback onToggleLock;
  final ValueChanged<bool> onSelectTouchMode;
  final VoidCallback onOpenSystemKeyboard;
  final VoidCallback onOpenVirtualKeyboard;
  final VoidCallback onOpenDisplaySettings;
  final VoidCallback onToggleQuality;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenMore;
  final VoidCallback onDisconnect;
  final VoidCallback? onToggleSound;
  final VoidCallback? onSwitchDisplay;
  final ValueChanged<bool>? onPointerVisibilityChanged;
  final void Function(Offset pointer, Offset panDelta)? onPanCanvas;
  final VoidCallback? onMinimize;
  final VoidCallback? onScreenshot;
  final bool showRemoteCursor;
  final bool canShowRemoteCursor;
  final ValueChanged<bool>? onToggleRemoteCursor;
  final String Function(String key)? translateLabel;
  final bool initialMouseVisible;
  final bool initialMouseCollapsed;
  final bool showFirstRunTour;
  final VoidCallback? onDismissFirstRunTour;

  @override
  State<AwesunFlutterOverlay> createState() => _AwesunFlutterOverlayState();
}

class _AwesunFlutterOverlayState extends State<AwesunFlutterOverlay> {
  static const double _dragThreshold = 5.0;
  static const double _scrollStepRadians = 0.30;

  late bool _mouseVisible = widget.initialMouseVisible;
  late bool _mouseCollapsed = widget.initialMouseCollapsed;
  Offset? _mouseAnchor;
  bool _mouseDockRight = true;
  double _mouseDockFraction = 0.48;

  bool _lockRight = true;
  double _lockFraction = 0.12;

  bool _wheelOpen = false;
  double? _wheelAngle;
  double _wheelRemainder = 0;

  AwesunMouseRegion? _pressedRegion;
  bool _leftDragging = false;
  Offset _gestureStart = Offset.zero;
  Offset _anchorAtGestureStart = Offset.zero;
  bool _moved = false;

  bool _functionsOpen = false;
  bool _guideOpen = false;
  late bool _tourOpen = widget.showFirstRunTour;
  int _tourStep = 0;

  static const double _edgePanIntervalSec = 1.0 / 30.0;
  static const double _panReversalThreshold = 3.0;
  Timer? _edgePanTimer;
  Offset _lastRequestedCenter = Offset.zero;
  Size _lastViewportSize = Size.zero;
  double _panPeakExcursion = 0;
  bool _panBraked = false;
  double _panBrakeLow = 0;

  String _tr(String key) => widget.translateLabel?.call(key) ?? key;

  void _stopEdgePan() {
    _edgePanTimer?.cancel();
    _edgePanTimer = null;
  }

  void _resetEdgePan() {
    _stopEdgePan();
    _panPeakExcursion = 0;
    _panBraked = false;
    _panBrakeLow = 0;
  }

  void _advanceEdgePan() {
    if (!mounted ||
        widget.displayLocked ||
        widget.onPanCanvas == null ||
        (_pressedRegion != AwesunMouseRegion.hub &&
            _pressedRegion != AwesunMouseRegion.left)) {
      _stopEdgePan();
      return;
    }
    final layout = AwesunControlGeometry.layoutFor(
      _mouseAnchor,
      _lastViewportSize,
    );
    final velocity = computeAwesunEdgePanVelocity(
      requestedCenter: _lastRequestedCenter,
      minCenter: layout.minCenter,
      maxCenter: layout.maxCenter,
    );
    if (velocity == Offset.zero) {
      _stopEdgePan();
      return;
    }
    widget.onPanCanvas!(
      layout.pointer,
      velocity * _edgePanIntervalSec,
    );
  }

  void _updateEdgePan(
    Offset requestedCenter,
    AwesunMouseLayout layout,
    Size viewportSize,
  ) {
    _lastRequestedCenter = requestedCenter;
    _lastViewportSize = viewportSize;
    if (widget.displayLocked || widget.onPanCanvas == null) {
      _resetEdgePan();
      return;
    }
    final velocity = computeAwesunEdgePanVelocity(
      requestedCenter: requestedCenter,
      minCenter: layout.minCenter,
      maxCenter: layout.maxCenter,
    );
    if (velocity == Offset.zero) {
      _resetEdgePan();
      return;
    }
    final excursion = (requestedCenter - layout.center).distance;
    if (!_panBraked) {
      if (_panPeakExcursion - excursion >= _panReversalThreshold) {
        _panBraked = true;
        _panBrakeLow = excursion;
        _stopEdgePan();
        return;
      }
      if (excursion > _panPeakExcursion) _panPeakExcursion = excursion;
    } else {
      if (excursion < _panBrakeLow) _panBrakeLow = excursion;
      if (excursion - _panBrakeLow < _panReversalThreshold) {
        return;
      }
      _panBraked = false;
      _panPeakExcursion = excursion;
    }
    if (_edgePanTimer == null) {
      _edgePanTimer = Timer.periodic(
        const Duration(milliseconds: 33),
        (_) => _advanceEdgePan(),
      );
      _advanceEdgePan();
    }
  }

  void _notifyPointerVisibility() {
    widget.onPointerVisibilityChanged?.call(
      widget.canInput && _mouseVisible && !_mouseCollapsed && !_functionsOpen,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _notifyPointerVisibility();
    });
  }

  @override
  void didUpdateWidget(covariant AwesunFlutterOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.displayLocked && !oldWidget.displayLocked) {
      _resetEdgePan();
    }
    if (oldWidget.canInput != widget.canInput) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _notifyPointerVisibility();
      });
    }
  }

  @override
  void dispose() {
    _resetEdgePan();
    if (_leftDragging) {
      widget.onLeftDragEnd();
    }
    super.dispose();
  }

  void _handleMousePanDown(
    Offset localInWidget,
    AwesunMouseLayout layout,
    Size viewportSize,
  ) {
    final fromCenter = localInWidget -
        const Offset(
          AwesunControlGeometry.mouseSize / 2,
          AwesunControlGeometry.mouseSize / 2,
        );
    final region = AwesunControlGeometry.hitRegion(
      fromCenter,
      wheelOpen: _wheelOpen,
    );
    if (region == null) return;

    _pressedRegion = region;
    _gestureStart = localInWidget;
    _anchorAtGestureStart = layout.center;
    _moved = false;
    _wheelRemainder = 0;

    if (region == AwesunMouseRegion.left) {
      HapticFeedback.selectionClick();
      _leftDragging = true;
      widget.onLeftDragStart(layout.pointer);
    } else if (region == AwesunMouseRegion.ring) {
      _wheelAngle = math.atan2(fromCenter.dy, fromCenter.dx);
    }
    setState(() {});
  }

  void _handleMousePanUpdate(
    Offset localInWidget,
    Offset delta,
    Size viewportSize,
  ) {
    final region = _pressedRegion;
    if (region == null) return;

    final fromCenter = localInWidget -
        const Offset(
          AwesunControlGeometry.mouseSize / 2,
          AwesunControlGeometry.mouseSize / 2,
        );

    if (region == AwesunMouseRegion.ring) {
      final angle = math.atan2(fromCenter.dy, fromCenter.dx);
      final prev = _wheelAngle;
      if (prev != null) {
        var diff = angle - prev;
        if (diff > math.pi) diff -= 2 * math.pi;
        if (diff < -math.pi) diff += 2 * math.pi;
        _wheelRemainder += diff;
        final steps = (_wheelRemainder / _scrollStepRadians).truncate();
        if (steps != 0) {
          _wheelRemainder -= steps * _scrollStepRadians;
          final layout = AwesunControlGeometry.layoutFor(
            _mouseAnchor,
            viewportSize,
          );
          widget.onScroll(-steps, layout.pointer);
        }
      }
      setState(() => _wheelAngle = angle);
      return;
    }

    if ((localInWidget - _gestureStart).distance >= _dragThreshold) {
      _moved = true;
    }
    if ((region == AwesunMouseRegion.hub || region == AwesunMouseRegion.left) &&
        _moved) {
      final requested = _anchorAtGestureStart + (localInWidget - _gestureStart);
      final next = AwesunControlGeometry.layoutFor(requested, viewportSize);
      setState(() => _mouseAnchor = next.center);
      widget.onMovePointer(next.pointer);
      _updateEdgePan(requested, next, viewportSize);
    }
  }

  void _handleMousePanEnd(Size viewportSize) {
    _resetEdgePan();
    final region = _pressedRegion;
    if (region == null) return;
    final layout = AwesunControlGeometry.layoutFor(_mouseAnchor, viewportSize);

    if (_leftDragging) {
      _leftDragging = false;
      widget.onLeftDragEnd();
    } else if (!_moved) {
      switch (region) {
        case AwesunMouseRegion.hub:
          HapticFeedback.selectionClick();
          widget.onLeftClick(layout.pointer);
          break;
        case AwesunMouseRegion.right:
          HapticFeedback.selectionClick();
          widget.onRightClick(layout.pointer);
          break;
        case AwesunMouseRegion.wheelBottom:
          HapticFeedback.selectionClick();
          widget.onMiddleClick(layout.pointer);
          break;
        case AwesunMouseRegion.wheelTop:
          HapticFeedback.selectionClick();
          _wheelOpen = true;
          _wheelAngle = -math.pi / 4;
          break;
        case AwesunMouseRegion.close:
          HapticFeedback.selectionClick();
          if (_wheelOpen) {
            _wheelOpen = false;
          } else {
            _mouseCollapsed = true;
            _notifyPointerVisibility();
          }
          break;
        case AwesunMouseRegion.left:
        case AwesunMouseRegion.ring:
          break;
      }
    }
    setState(() {
      _pressedRegion = null;
      _moved = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      final padding = MediaQuery.paddingOf(context);
      final layout = AwesunControlGeometry.layoutFor(_mouseAnchor, size);
      final showMouse = widget.canInput &&
          _mouseVisible &&
          !_functionsOpen &&
          !_guideOpen;

      return Stack(
        fit: StackFit.expand,
        children: [
          if (showMouse && !_mouseCollapsed) ...[
            // Offset pointer cursor (top-left of thumb so finger never blocks target).
            Positioned(
              left: layout.pointer.dx,
              top: layout.pointer.dy,
              child: const IgnorePointer(
                child: SizedBox(
                  width: 16,
                  height: 22,
                  child: CustomPaint(painter: _AwesunPointerPainter()),
                ),
              ),
            ),
            // 188x188 Awesun radial virtual mouse cluster.
            Positioned(
              left: layout.center.dx - AwesunControlGeometry.mouseSize / 2,
              top: layout.center.dy - AwesunControlGeometry.mouseSize / 2,
              width: AwesunControlGeometry.mouseSize,
              height: AwesunControlGeometry.mouseSize,
              child: _AwesunHitTarget(
                wheelOpen: _wheelOpen,
                onDown: (pos) => _handleMousePanDown(pos, layout, size),
                onMove: (pos, delta) =>
                    _handleMousePanUpdate(pos, delta, size),
                onUp: () => _handleMousePanEnd(size),
                child: CustomPaint(
                  painter: _AwesunMousePainter(
                    wheelOpen: _wheelOpen,
                    wheelAngle: _wheelAngle,
                    pressed: _pressedRegion,
                    dragging: _leftDragging,
                  ),
                ),
              ),
            ),
          ],

          if (showMouse && _mouseCollapsed)
            _buildDockOrb(
              size: size,
              right: _mouseDockRight,
              fraction: _mouseDockFraction,
              topInset: padding.top,
              bottomInset: padding.bottom,
              icon: Icons.mouse_rounded,
              color: AwesunVisualPalette.activeIce,
              tooltip: _tr('Virtual mouse'),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _mouseCollapsed = false);
                _notifyPointerVisibility();
              },
              onDockChanged: (r, f) => setState(() {
                _mouseDockRight = r;
                _mouseDockFraction = f;
              }),
            ),

          if (!_functionsOpen && !_guideOpen) ...[
            // Draggable display lock edge orb.
            _buildDockOrb(
              size: size,
              right: _lockRight,
              fraction: _lockFraction,
              topInset: padding.top,
              bottomInset: padding.bottom,
              icon: widget.displayLocked
                  ? Icons.lock_rounded
                  : Icons.lock_open_rounded,
              color: widget.displayLocked
                  ? AwesunVisualPalette.amber
                  : AwesunVisualPalette.ink,
              tooltip: _tr('Lock display'),
              onTap: () {
                HapticFeedback.selectionClick();
                widget.onToggleLock();
              },
              onDockChanged: (r, f) => setState(() {
                _lockRight = r;
                _lockFraction = f;
              }),
            ),

            // Bottom-right vertical 3-button glass rail.
            Positioned(
              right: AwesunControlGeometry.controlEdge,
              bottom: math.max(padding.bottom + 14, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.canInput) ...[
                    _GlassOrbButton(
                      tooltip: _tr('Keyboard'),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        widget.onOpenVirtualKeyboard();
                      },
                      child: const SizedBox(
                        width: 20,
                        height: 20,
                        child: CustomPaint(painter: _AwesunKeyboardGlyphPainter()),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _GlassOrbButton(
                      tooltip: _tr('Virtual mouse'),
                      highlighted: _mouseVisible && !_mouseCollapsed,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          if (!_mouseVisible) {
                            _mouseVisible = true;
                            _mouseCollapsed = false;
                          } else {
                            _mouseCollapsed = !_mouseCollapsed;
                          }
                        });
                        _notifyPointerVisibility();
                      },
                      child: Icon(
                        Icons.mouse_rounded,
                        size: 19,
                        color: _mouseVisible && !_mouseCollapsed
                            ? AwesunVisualPalette.activeIce
                            : AwesunVisualPalette.ink,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  _GlassOrbButton(
                    tooltip: _tr('Actions'),
                    accent: true,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _functionsOpen = true);
                      _notifyPointerVisibility();
                    },
                    child: const SizedBox(
                      width: 20,
                      height: 20,
                      child: CustomPaint(painter: _AwesunWheelGlyphPainter()),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_functionsOpen) _buildActionsSheet(context),
          if (_guideOpen) _buildGuideSheet(context),
          if (_tourOpen && !_functionsOpen && !_guideOpen)
            _buildFirstRunTourBanner(context, padding.top),
        ],
      );
    });
  }

  Widget _buildFirstRunTourBanner(BuildContext context, double topInset) {
    const steps = [
      '1/3 · Drag the center disc to move the pointer; push screen edge to pan',
      '2/3 · Tap left/right arcs to click, or top/bottom dots to open scroll ring',
      '3/3 · Tap the bottom-right wheel for actions, cursor toggles, and more tools',
    ];
    void dismiss() {
      setState(() => _tourOpen = false);
      widget.onDismissFirstRunTour?.call();
    }

    return Positioned(
      top: topInset + 12,
      left: 16,
      right: 68,
      child: Material(
        color: AwesunVisualPalette.sheetFill,
        elevation: 6,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AwesunVisualPalette.mouseStroke),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  size: 18, color: AwesunVisualPalette.activeIce),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  steps[_tourStep.clamp(0, steps.length - 1)],
                  style: const TextStyle(
                    color: AwesunVisualPalette.ink,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ),
              TextButton(
                onPressed: dismiss,
                child: Text(
                  _tr('Skip'),
                  style: const TextStyle(
                      color: AwesunVisualPalette.dim, fontSize: 12),
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                onPressed: () {
                  if (_tourStep + 1 < steps.length) {
                    setState(() => _tourStep++);
                  } else {
                    dismiss();
                  }
                },
                child: Text(
                  _tourStep + 1 < steps.length ? _tr('Next') : _tr('OK'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDockOrb({
    required Size size,
    required bool right,
    required double fraction,
    required double topInset,
    required double bottomInset,
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
    required void Function(bool right, double fraction) onDockChanged,
  }) {
    final edge = AwesunControlGeometry.controlEdge;
    final diameter = AwesunControlGeometry.controlRadius * 2;
    final minY = topInset + edge;
    final maxY = math.max(minY, size.height - bottomInset - diameter - 160);
    final top = (fraction * size.height).clamp(minY, maxY);
    return Positioned(
      left: right ? null : edge,
      right: right ? edge : null,
      top: top,
      child: GestureDetector(
        onPanEnd: (details) {},
        onPanUpdate: (details) {
          final nextTop = (top + details.delta.dy).clamp(minY, maxY);
          final nextRight = details.globalPosition.dx >= size.width / 2;
          onDockChanged(nextRight, nextTop / math.max(1, size.height));
        },
        child: _GlassOrbButton(
          tooltip: tooltip,
          onTap: onTap,
          child: Icon(icon, size: 19, color: color),
        ),
      ),
    );
  }

  Widget _buildActionsSheet(BuildContext context) {
    void close() {
      setState(() => _functionsOpen = false);
      _notifyPointerVisibility();
    }

    Widget tile({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool active = false,
      bool danger = false,
    }) {
      return Material(
        color: danger
            ? AwesunVisualPalette.danger.withOpacity(0.16)
            : active
                ? AwesunVisualPalette.activeBlue.withOpacity(0.24)
                : Colors.white.withOpacity(0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: danger
                ? AwesunVisualPalette.danger.withOpacity(0.35)
                : active
                    ? AwesunVisualPalette.activeIce.withOpacity(0.45)
                    : Colors.white.withOpacity(0.08),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: danger
                      ? const Color(0xFFFCA5A5)
                      : active
                          ? const Color(0xFF93C5FD)
                          : AwesunVisualPalette.ink,
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: danger
                        ? const Color(0xFFFCA5A5)
                        : active
                            ? const Color(0xFF93C5FD)
                            : AwesunVisualPalette.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget modeCard({
      required bool selected,
      required IconData icon,
      required String title,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: Material(
          color: selected
              ? AwesunVisualPalette.activeBlue.withOpacity(0.24)
              : Colors.white.withOpacity(0.06),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: selected
                  ? AwesunVisualPalette.activeIce.withOpacity(0.55)
                  : Colors.white.withOpacity(0.08),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF3B82F6)
                          : Colors.white.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(icon, size: 16, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AwesunVisualPalette.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Positioned.fill(
      child: GestureDetector(
        onTap: close,
        child: Container(
          color: Colors.black.withOpacity(0.45),
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: double.infinity,
              constraints: BoxConstraints(
                maxWidth: 520,
                maxHeight: MediaQuery.sizeOf(context).height * 0.78,
              ),
              decoration: const BoxDecoration(
                color: AwesunVisualPalette.sheetFill,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  top: BorderSide(color: Color(0x26FFFFFF)),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _tr('Actions'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AwesunVisualPalette.ink,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: close,
                            icon: const Icon(Icons.close_rounded,
                                size: 20, color: AwesunVisualPalette.ink),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Session quick grid
                            GridView.count(
                              crossAxisCount: 4,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              childAspectRatio: 1.12,
                              children: [
                                tile(
                                  icon: Icons.link_off_rounded,
                                  label: _tr('Disconnect'),
                                  danger: true,
                                  onTap: () {
                                    close();
                                    widget.onDisconnect();
                                  },
                                ),
                                if (widget.onMinimize != null)
                                  tile(
                                    icon: Icons.picture_in_picture_alt_rounded,
                                    label: _tr('Minimize'),
                                    onTap: () {
                                      close();
                                      widget.onMinimize!();
                                    },
                                  ),
                                if (widget.onToggleSound != null)
                                  tile(
                                    icon: widget.soundOn
                                        ? Icons.volume_up_rounded
                                        : Icons.volume_off_rounded,
                                    label: _tr('Audio'),
                                    active: widget.soundOn,
                                    onTap: widget.onToggleSound!,
                                  ),
                                if (widget.onScreenshot != null)
                                  tile(
                                    icon: Icons.camera_alt_outlined,
                                    label: _tr('Screenshot'),
                                    onTap: () {
                                      close();
                                      widget.onScreenshot!();
                                    },
                                  ),
                                if (widget.displayCount > 1 &&
                                    widget.onSwitchDisplay != null)
                                  tile(
                                    icon: Icons.desktop_windows_rounded,
                                    label: _tr('Display'),
                                    onTap: () {
                                      close();
                                      widget.onSwitchDisplay!();
                                    },
                                  ),
                                tile(
                                  icon: Icons.chat_bubble_outline_rounded,
                                  label: _tr('Chat'),
                                  onTap: () {
                                    close();
                                    widget.onOpenChat();
                                  },
                                ),
                                tile(
                                  icon: Icons.tune_rounded,
                                  label: _tr('More'),
                                  onTap: () {
                                    close();
                                    widget.onOpenMore();
                                  },
                                ),
                              ],
                            ),
                            if (widget.canInput) ...[
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _tr('Input mode'),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AwesunVisualPalette.dim,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      foregroundColor:
                                          AwesunVisualPalette.activeIce,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _functionsOpen = false;
                                        _guideOpen = true;
                                      });
                                    },
                                    child: Text(_tr('Gestures')),
                                  ),
                                ],
                              ),
                              if (widget.canSwitchMode) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    modeCard(
                                      selected: !widget.touchMode,
                                      icon: Icons.mouse_rounded,
                                      title: _tr('Mouse mode'),
                                      onTap: () =>
                                          widget.onSelectTouchMode(false),
                                    ),
                                    const SizedBox(width: 8),
                                    modeCard(
                                      selected: widget.touchMode,
                                      icon: Icons.touch_app_rounded,
                                      title: _tr('Touch mode'),
                                      onTap: () =>
                                          widget.onSelectTouchMode(true),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 10),
                              Material(
                                color: Colors.white.withOpacity(0.06),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(
                                    color: Colors.white.withOpacity(0.08),
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SwitchListTile(
                                      dense: true,
                                      activeColor: const Color(0xFF3B82F6),
                                      title: Text(
                                        _tr('Virtual mouse'),
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w500,
                                          color: AwesunVisualPalette.ink,
                                        ),
                                      ),
                                      value: _mouseVisible,
                                      onChanged: (v) {
                                        setState(() {
                                          _mouseVisible = v;
                                          if (v) _mouseCollapsed = false;
                                        });
                                        _notifyPointerVisibility();
                                      },
                                    ),
                                    if (widget.canShowRemoteCursor &&
                                        widget.onToggleRemoteCursor != null) ...[
                                      Divider(
                                        height: 1,
                                        indent: 16,
                                        endIndent: 16,
                                        color: Colors.white.withOpacity(0.08),
                                      ),
                                      SwitchListTile(
                                        dense: true,
                                        activeColor: const Color(0xFF3B82F6),
                                        title: Text(
                                          _tr('Show remote cursor'),
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w500,
                                            color: AwesunVisualPalette.ink,
                                          ),
                                        ),
                                        value: widget.showRemoteCursor,
                                        onChanged: widget.onToggleRemoteCursor,
                                      ),
                                    ],
                                    Divider(
                                      height: 1,
                                      indent: 16,
                                      endIndent: 16,
                                      color: Colors.white.withOpacity(0.08),
                                    ),
                                    SwitchListTile(
                                      dense: true,
                                      activeColor: const Color(0xFF3B82F6),
                                      title: Text(
                                        _tr('Lock canvas'),
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w500,
                                          color: AwesunVisualPalette.ink,
                                        ),
                                      ),
                                      value: widget.displayLocked,
                                      onChanged: (_) => widget.onToggleLock(),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _tr('Keyboard'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AwesunVisualPalette.dim,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: tile(
                                      icon: Icons.keyboard_alt_outlined,
                                      label: _tr('Soft keyboard'),
                                      onTap: () {
                                        close();
                                        widget.onOpenSystemKeyboard();
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: tile(
                                      icon: Icons.keyboard_rounded,
                                      label: _tr('Virtual keyboard'),
                                      onTap: () {
                                        close();
                                        widget.onOpenVirtualKeyboard();
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 16),
                            Text(
                              _tr('Display'),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AwesunVisualPalette.dim,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: tile(
                                    icon: Icons.display_settings_rounded,
                                    label: _tr('Display settings'),
                                    onTap: () {
                                      close();
                                      widget.onOpenDisplaySettings();
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: tile(
                                    icon: Icons.monitor_heart_outlined,
                                    label: _tr('Show quality monitor'),
                                    active: widget.qualityVisible,
                                    onTap: () {
                                      close();
                                      widget.onToggleQuality();
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGuideSheet(BuildContext context) {
    void close() {
      setState(() => _guideOpen = false);
      _notifyPointerVisibility();
    }

    const items = [
      ('Center hub', 'Drag to move cursor, tap to left-click'),
      ('Left arc (L)', 'Tap for left-click, hold & drag to select'),
      ('Right arc (R)', 'Tap for right-click'),
      ('Top wheel', 'Open circular scroll ring'),
      ('Bottom middle', 'Tap for middle-click'),
      ('Close (×)', 'Exit scroll ring or dock to edge'),
    ];

    return Positioned.fill(
      child: GestureDetector(
        onTap: close,
        child: Container(
          color: Colors.black.withOpacity(0.45),
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 520),
              decoration: const BoxDecoration(
                color: AwesunVisualPalette.sheetFill,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(top: BorderSide(color: Color(0x26FFFFFF))),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _tr('Virtual mouse'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AwesunVisualPalette.ink,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: close,
                            icon: const Icon(Icons.close_rounded,
                                size: 20, color: AwesunVisualPalette.ink),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 2.35,
                        children: [
                          for (final (k, v) in items)
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    k,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AwesunVisualPalette.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    v,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      color: AwesunVisualPalette.dim,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Only claims pointer hits that actually land inside one of the Awesun mouse shapes,
/// letting touches on empty corners pass straight through to the remote canvas!
class _AwesunHitTarget extends StatefulWidget {
  const _AwesunHitTarget({
    required this.wheelOpen,
    required this.onDown,
    required this.onMove,
    required this.onUp,
    required this.child,
  });

  final bool wheelOpen;
  final ValueChanged<Offset> onDown;
  final void Function(Offset local, Offset delta) onMove;
  final VoidCallback onUp;
  final Widget child;

  @override
  State<_AwesunHitTarget> createState() => _AwesunHitTargetState();
}

class _AwesunHitTargetState extends State<_AwesunHitTarget> {
  int? _activePointer;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (_activePointer != null) return;
        final fromCenter = event.localPosition -
            const Offset(
              AwesunControlGeometry.mouseSize / 2,
              AwesunControlGeometry.mouseSize / 2,
            );
        if (AwesunControlGeometry.hitRegion(fromCenter,
                wheelOpen: widget.wheelOpen) ==
            null) {
          return;
        }
        _activePointer = event.pointer;
        widget.onDown(event.localPosition);
      },
      onPointerMove: (event) {
        if (event.pointer != _activePointer) return;
        widget.onMove(event.localPosition, event.delta);
      },
      onPointerUp: (event) {
        if (event.pointer != _activePointer) return;
        _activePointer = null;
        widget.onUp();
      },
      onPointerCancel: (event) {
        if (event.pointer != _activePointer) return;
        _activePointer = null;
        widget.onUp();
      },
      child: widget.child,
    );
  }
}

class _GlassOrbButton extends StatelessWidget {
  const _GlassOrbButton({
    required this.tooltip,
    required this.onTap,
    required this.child,
    this.accent = false,
    this.highlighted = false,
  });

  final String tooltip;
  final VoidCallback onTap;
  final Widget child;
  final bool accent;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final borderColor = (accent || highlighted)
        ? AwesunVisualPalette.activeIce.withOpacity(0.55)
        : AwesunVisualPalette.mouseStroke;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AwesunVisualPalette.orbFill,
        shape: CircleBorder(side: BorderSide(color: borderColor, width: 1.0)),
        elevation: 6,
        shadowColor: Colors.black.withOpacity(0.45),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: AwesunControlGeometry.controlRadius * 2,
            height: AwesunControlGeometry.controlRadius * 2,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class _AwesunMousePainter extends CustomPainter {
  const _AwesunMousePainter({
    required this.wheelOpen,
    required this.wheelAngle,
    required this.pressed,
    required this.dragging,
  });

  final bool wheelOpen;
  final double? wheelAngle;
  final AwesunMouseRegion? pressed;
  final bool dragging;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);

    if (wheelOpen) {
      _paintScrollRing(canvas, c);
    } else {
      _paintArc(canvas, c, left: true);
      _paintArc(canvas, c, left: false);
      _paintHub(canvas, c);
      _paintSmallButton(
        canvas,
        c + const Offset(0, -AwesunControlGeometry.wheelOffset),
        top: true,
        active: pressed == AwesunMouseRegion.wheelTop,
      );
      _paintSmallButton(
        canvas,
        c + const Offset(0, AwesunControlGeometry.wheelOffset),
        top: false,
        active: pressed == AwesunMouseRegion.wheelBottom,
      );
    }

    _paintCloseButton(canvas, c + AwesunControlGeometry.closeOffset);
  }

  void _paintArc(Canvas canvas, Offset c, {required bool left}) {
    final active = (left && (pressed == AwesunMouseRegion.left || dragging)) ||
        (!left && pressed == AwesunMouseRegion.right);
    final centerDeg = left ? 180.0 : 0.0;
    final startRad = (centerDeg - AwesunControlGeometry.arcSpanDeg) * math.pi / 180;
    final sweepRad = (AwesunControlGeometry.arcSpanDeg * 2) * math.pi / 180;
    final rect = Rect.fromCircle(center: c, radius: AwesunControlGeometry.arcRadius);

    // Outer luminous rim stroke
    canvas.drawArc(
      rect,
      startRad,
      sweepRad,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = AwesunControlGeometry.arcWidth + 2.4
        ..color = active
            ? AwesunVisualPalette.activeStroke
            : AwesunVisualPalette.mouseStroke,
    );
    // Inner frosted fill stroke
    canvas.drawArc(
      rect,
      startRad,
      sweepRad,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = AwesunControlGeometry.arcWidth
        ..color = active
            ? AwesunVisualPalette.activeBlue
            : AwesunVisualPalette.mouseFill,
    );

    final tp = TextPainter(
      text: TextSpan(
        text: left ? 'L' : 'R',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: active ? Colors.white : AwesunVisualPalette.ink.withOpacity(0.88),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final labelCenter = Offset(
      c.dx + (left ? -AwesunControlGeometry.arcRadius : AwesunControlGeometry.arcRadius),
      c.dy,
    );
    tp.paint(canvas, labelCenter - Offset(tp.width / 2, tp.height / 2));
  }

  void _paintHub(Canvas canvas, Offset c) {
    final active = pressed == AwesunMouseRegion.hub || dragging;
    canvas.drawCircle(
      c,
      AwesunControlGeometry.hubRadius,
      Paint()
        ..color = active
            ? AwesunVisualPalette.activeBlue
            : AwesunVisualPalette.mouseFill,
    );
    canvas.drawCircle(
      c,
      AwesunControlGeometry.hubRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = active
            ? AwesunVisualPalette.activeStroke
            : Colors.white.withOpacity(0.34),
    );
    canvas.drawCircle(
      c,
      AwesunControlGeometry.hubRadius - 6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = Colors.white.withOpacity(0.10),
    );
    // Directional crosshair ticks
    final tickPaint = Paint()
      ..color = Colors.white.withOpacity(active ? 0.85 : 0.45)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c + const Offset(0, -12), c + const Offset(0, -8), tickPaint);
    canvas.drawLine(c + const Offset(0, 8), c + const Offset(0, 12), tickPaint);
    canvas.drawLine(c + const Offset(-12, 0), c + const Offset(-8, 0), tickPaint);
    canvas.drawLine(c + const Offset(8, 0), c + const Offset(12, 0), tickPaint);
    canvas.drawCircle(
      c,
      3.2,
      Paint()..color = active ? Colors.white : AwesunVisualPalette.activeIce,
    );
  }

  void _paintSmallButton(
    Canvas canvas,
    Offset c, {
    required bool top,
    required bool active,
  }) {
    canvas.drawCircle(
      c,
      AwesunControlGeometry.wheelRadius,
      Paint()
        ..color = active
            ? AwesunVisualPalette.activeBlue
            : AwesunVisualPalette.mouseFill,
    );
    canvas.drawCircle(
      c,
      AwesunControlGeometry.wheelRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = active
            ? AwesunVisualPalette.activeStroke
            : AwesunVisualPalette.mouseStroke,
    );
    if (top) {
      // Double up/down scroll chevron
      final p = Paint()
        ..color = Colors.white.withOpacity(0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final up = Path()
        ..moveTo(c.dx - 3.5, c.dy - 1.8)
        ..lineTo(c.dx, c.dy - 5.2)
        ..lineTo(c.dx + 3.5, c.dy - 1.8);
      final down = Path()
        ..moveTo(c.dx - 3.5, c.dy + 1.8)
        ..lineTo(c.dx, c.dy + 5.2)
        ..lineTo(c.dx + 3.5, c.dy + 1.8);
      canvas.drawPath(up, p);
      canvas.drawPath(down, p);
    } else {
      // 5 horizontal middle-wheel grip ridges
      final p = Paint()
        ..color = Colors.white.withOpacity(0.68)
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round;
      for (final dy in const [-5.0, -2.5, 0.0, 2.5, 5.0]) {
        canvas.drawLine(
          Offset(c.dx - 5.5, c.dy + dy),
          Offset(c.dx + 5.5, c.dy + dy),
          p,
        );
      }
    }
  }

  void _paintScrollRing(Canvas canvas, Offset c) {
    final r = AwesunControlGeometry.ringRadius;
    final half = AwesunControlGeometry.ringThickness / 2;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = AwesunControlGeometry.ringThickness
        ..color = AwesunVisualPalette.mouseFill,
    );
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = AwesunVisualPalette.mouseStroke;
    canvas.drawCircle(c, r + half, rim);
    canvas.drawCircle(c, r - half, rim);

    for (var i = 0; i < 24; i++) {
      final a = i * math.pi / 12;
      final major = i % 6 == 0;
      final r1 = major ? r - 5.5 : r - 3.0;
      final r2 = major ? r + 5.5 : r + 3.0;
      canvas.drawLine(
        Offset(c.dx + r1 * math.cos(a), c.dy + r1 * math.sin(a)),
        Offset(c.dx + r2 * math.cos(a), c.dy + r2 * math.sin(a)),
        Paint()
          ..color = major
              ? AwesunVisualPalette.activeIce.withOpacity(0.75)
              : Colors.white.withOpacity(0.24)
          ..strokeWidth = major ? 1.6 : 1.0
          ..strokeCap = StrokeCap.round,
      );
    }

    if (wheelAngle case final angle?) {
      final orb = Offset(c.dx + r * math.cos(angle), c.dy + r * math.sin(angle));
      canvas.drawCircle(
        orb,
        10.5,
        Paint()
          ..color = AwesunVisualPalette.activeIce.withOpacity(0.78)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawCircle(orb, 4.8, Paint()..color = Colors.white);
    }
  }

  void _paintCloseButton(Canvas canvas, Offset c) {
    canvas.drawCircle(c, 12.5, Paint()..color = AwesunVisualPalette.mouseFill);
    canvas.drawCircle(
      c,
      12.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = AwesunVisualPalette.mouseStroke,
    );
    final p = Paint()
      ..color = Colors.white.withOpacity(0.86)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c + const Offset(-4, -4), c + const Offset(4, 4), p);
    canvas.drawLine(c + const Offset(4, -4), c + const Offset(-4, 4), p);
  }

  @override
  bool shouldRepaint(covariant _AwesunMousePainter oldDelegate) =>
      wheelOpen != oldDelegate.wheelOpen ||
      wheelAngle != oldDelegate.wheelAngle ||
      pressed != oldDelegate.pressed ||
      dragging != oldDelegate.dragging;
}

class _AwesunPointerPainter extends CustomPainter {
  const _AwesunPointerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, size.height * 0.62)
      ..lineTo(size.width * 0.60, size.height * 0.66)
      ..lineTo(size.width * 0.79, size.height * 0.92)
      ..lineTo(size.width * 0.57, size.height)
      ..lineTo(size.width * 0.39, size.height * 0.73)
      ..lineTo(size.width * 0.12, size.height * 0.89)
      ..close();
    canvas.drawShadow(path, Colors.black.withOpacity(0.6), 2.5, false);
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xE60B0F17),
    );
  }

  @override
  bool shouldRepaint(covariant _AwesunPointerPainter oldDelegate) => false;
}

class _AwesunKeyboardGlyphPainter extends CustomPainter {
  const _AwesunKeyboardGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()..color = AwesunVisualPalette.ink;
    final dx = size.width / 6;
    for (var i = 0; i < 5; i++) {
      canvas.drawCircle(Offset(dx * (i + 1), size.height * 0.30), 1.3, dotPaint);
    }
    for (var i = 0; i < 4; i++) {
      canvas.drawCircle(
          Offset(dx * (i + 1.5), size.height * 0.52), 1.3, dotPaint);
    }
    canvas.drawLine(
      Offset(size.width * 0.22, size.height * 0.78),
      Offset(size.width * 0.78, size.height * 0.78),
      Paint()
        ..color = AwesunVisualPalette.ink
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _AwesunKeyboardGlyphPainter oldDelegate) => false;
}

class _AwesunWheelGlyphPainter extends CustomPainter {
  const _AwesunWheelGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = AwesunVisualPalette.activeIce
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final midX = size.width / 2;
    final midY = size.height / 2;
    final w = size.width * 0.28;
    final up = Path()
      ..moveTo(midX - w, midY - 2)
      ..lineTo(midX, midY - 7)
      ..lineTo(midX + w, midY - 2);
    final down = Path()
      ..moveTo(midX - w, midY + 2)
      ..lineTo(midX, midY + 7)
      ..lineTo(midX + w, midY + 2);
    canvas.drawPath(up, p);
    canvas.drawPath(down, p);
  }

  @override
  bool shouldRepaint(covariant _AwesunWheelGlyphPainter oldDelegate) => false;
}
