import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Explicit timed hold for emergency SOS activation.
///
/// Uses [Listener] pointer events (not [GestureDetector.onLongPress]) so a
/// continuous hold is not cancelled by the gesture arena at ~500ms.
/// SOS fires only after [holdDuration] of uninterrupted press.
class SosHoldButton extends StatefulWidget {
  /// Authoritative hold threshold for SOS activation.
  static const Duration holdDuration = Duration(seconds: 3);

  final VoidCallback? onActivated;
  final bool enabled;
  final Color emergencyColor;
  final double size;

  const SosHoldButton({
    super.key,
    required this.onActivated,
    required this.emergencyColor,
    this.enabled = true,
    this.size = 164,
  });

  @override
  State<SosHoldButton> createState() => SosHoldButtonState();
}

@visibleForTesting
class SosHoldButtonState extends State<SosHoldButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _holdController;

  bool _holding = false;
  bool _activated = false;
  int? _activePointer;

  /// 0.0 idle → 1.0 at [SosHoldButton.holdDuration].
  double get progress => _holdController.value;

  bool get isHolding => _holding;

  bool get didActivate => _activated;

  @override
  void initState() {
    super.initState();
    _holdController = AnimationController(
      vsync: this,
      duration: SosHoldButton.holdDuration,
    )
      ..addStatusListener(_onHoldStatus)
      ..addListener(_onHoldTick);
  }

  void _onHoldTick() {
    // Belt-and-suspenders: value-based completion for test clock jumps.
    if (_holdController.value >= 1.0) {
      _completeHoldIfActive();
    }
  }

  void _onHoldStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _completeHoldIfActive();
  }

  void _completeHoldIfActive() {
    if (!_holding || _activated || !widget.enabled) return;
    _activated = true;
    _holding = false;
    _activePointer = null;
    widget.onActivated?.call();
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {
      // Platform channels may be unavailable in unit tests.
    }
    if (mounted) {
      _holdController.reset();
      setState(() {});
    }
  }

  void _cancelHold() {
    if (_activated) return;
    if (!_holding && _holdController.value == 0) {
      _activePointer = null;
      return;
    }
    _holding = false;
    _activePointer = null;
    _holdController.stop();
    _holdController.reset();
    if (mounted) setState(() {});
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled || _activated) return;
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    _holding = true;
    _activated = false;
    _holdController.forward(from: 0);
    if (mounted) setState(() {});
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_activePointer != null && event.pointer != _activePointer) return;
    _cancelHold();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_activePointer != null && event.pointer != _activePointer) return;
    _cancelHold();
  }

  @override
  void didUpdateWidget(covariant SosHoldButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _holding) {
      _cancelHold();
    }
    // Allow a new hold after SOS flow finishes loading.
    if (widget.enabled && !oldWidget.enabled) {
      _activated = false;
    }
  }

  @override
  void dispose() {
    _holdController.removeStatusListener(_onHoldStatus);
    _holdController.removeListener(_onHoldTick);
    _holdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return Semantics(
      label:
          'Emergency SOS button. Hold for 3 seconds to record your location. '
          'Contacts are not auto-notified — call 000 or dial contacts. '
          'Release before 3 seconds to cancel.',
      button: true,
      enabled: widget.enabled,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: widget.enabled ? _onPointerDown : null,
        onPointerUp: widget.enabled ? _onPointerUp : null,
        onPointerCancel: widget.enabled ? _onPointerCancel : null,
        child: AnimatedBuilder(
          animation: _holdController,
          builder: (context, child) {
            final p = _holdController.value;
            return SizedBox(
              width: size,
              height: size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: size,
                    height: size,
                    child: CircularProgressIndicator(
                      value: _holding || p > 0 ? p : 0,
                      strokeWidth: 5,
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                      color: Colors.white,
                    ),
                  ),
                  child!,
                ],
              ),
            );
          },
          child: Container(
            width: size - 16,
            height: size - 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.10),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.35),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 30,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Container(
              margin: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.emergencyColor,
                boxShadow: [
                  BoxShadow(
                    color: widget.emergencyColor.withValues(alpha: 0.5),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: !widget.enabled
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.sos_rounded,
                          color: Colors.white,
                          size: 54,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _holding ? 'HOLDING…' : 'HOLD 3s',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
