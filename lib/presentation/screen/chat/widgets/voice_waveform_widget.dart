import 'dart:async';

import 'package:flutter/material.dart';

/// Voice waveform visualizer displayed during voice recording.
///
/// Reacts to real-time [soundLevelStream] and [transcriptionStream] to render
/// an animated audio waveform and live transcribed text.
class VoiceWaveformWidget extends StatefulWidget {
  const VoiceWaveformWidget({
    super.key,
    required this.soundLevelStream,
    required this.transcriptionStream,
    required this.onStopAndSend,
    required this.onCancel,
    this.initialText = '',
    this.isHoldToSpeak = false,
  });

  final Stream<double> soundLevelStream;
  final Stream<String> transcriptionStream;
  final VoidCallback onStopAndSend;
  final VoidCallback onCancel;
  final String initialText;
  final bool isHoldToSpeak;

  @override
  State<VoiceWaveformWidget> createState() => _VoiceWaveformWidgetState();
}

class _VoiceWaveformWidgetState extends State<VoiceWaveformWidget>
    with SingleTickerProviderStateMixin {
  StreamSubscription<double>? _soundLevelSub;
  StreamSubscription<String>? _transcriptionSub;

  double _currentLevel = 0.2;
  String _transcribedText = '';
  late AnimationController _pulseController;

  static const List<double> _baseBarHeights = [
    8.0,
    14.0,
    22.0,
    30.0,
    36.0,
    30.0,
    22.0,
    14.0,
    8.0,
  ];

  @override
  void initState() {
    super.initState();
    _transcribedText = widget.initialText;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _soundLevelSub = widget.soundLevelStream.listen((level) {
      if (mounted) {
        setState(() {
          _currentLevel = level.clamp(0.0, 1.0);
        });
      }
    });

    _transcriptionSub = widget.transcriptionStream.listen((text) {
      if (mounted) {
        setState(() {
          _transcribedText = text;
        });
      }
    });
  }

  @override
  void dispose() {
    _soundLevelSub?.cancel();
    _transcriptionSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = theme.colorScheme.primary;

    final displayText = _transcribedText.trim().isNotEmpty
        ? _transcribedText.trim()
        : (widget.isHoldToSpeak
            ? 'Release mic to send'
            : 'Listening... speak now');

    return Container(
      key: const Key('voice_waveform_container'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        border: Border.all(color: const Color(0xFF334155)),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              FadeTransition(
                opacity: _pulseController,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'LIVE VOICE INPUT',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: const Color(0xFF94A3B8),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              if (widget.isHoldToSpeak)
                Text(
                  'Hold mode',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            key: const Key('voice_waveform_bars'),
            height: 42,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List.generate(_baseBarHeights.length, (index) {
                final baseHeight = _baseBarHeights[index];
                final factor = 1.0 + (_currentLevel * 1.5);
                final barHeight = (baseHeight * factor).clamp(6.0, 42.0);

                return Container(
                  width: 3.5,
                  height: barHeight,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: index == 4
                        ? accentColor
                        : accentColor.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              displayText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _transcribedText.trim().isNotEmpty
                    ? const Color(0xFFF8FAFC)
                    : const Color(0xFF94A3B8),
                fontStyle: _transcribedText.trim().isNotEmpty
                    ? FontStyle.normal
                    : FontStyle.italic,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                key: const Key('voice_waveform_cancel_button'),
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Cancel',
                color: const Color(0xFF94A3B8),
                onPressed: widget.onCancel,
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const Key('voice_waveform_send_button'),
                onPressed: widget.onStopAndSend,
                icon: const Icon(Icons.send_rounded, size: 16),
                label: const Text('Send'),
                style: FilledButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  minimumSize: const Size(0, 36),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
