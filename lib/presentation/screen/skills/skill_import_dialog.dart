import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:flutter_ai_agent/presentation/screen/skills/cubit/skills_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/skills/cubit/skills_state.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';

/// Modal for importing a community skill package (raw SKILL.md) from a URL.
class SkillImportDialog extends StatelessWidget {
  final SkillsCubit cubit;

  const SkillImportDialog({super.key, required this.cubit});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('skill_import_dialog'),
      backgroundColor: HermesColors.cardSurface,
      title: const Text('Import skill from URL'),
      content: SingleChildScrollView(
        child: _SkillImportDialogBody(cubit: cubit),
      ),
    );
  }
}

class _SkillImportDialogBody extends StatefulWidget {
  final SkillsCubit cubit;

  const _SkillImportDialogBody({required this.cubit});

  @override
  State<_SkillImportDialogBody> createState() => _SkillImportDialogBodyState();
}

class _SkillImportDialogBodyState extends State<_SkillImportDialogBody> {
  late final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SkillsCubit, SkillsState>(
      bloc: widget.cubit,
      builder: (context, state) {
        final loaded = state is SkillsLoaded ? state : null;
        final busy = loaded?.importBusy ?? false;
        final preview = loaded?.importPreview;
        final error = loaded?.importError;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('skill_import_url_field'),
              controller: _controller,
              style: const TextStyle(
                color: HermesColors.inkPrimary,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText:
                    'https://raw.githubusercontent.com/<owner>/<repo>/main/SKILL.md',
                hintStyle: const TextStyle(
                  color: HermesColors.inkMuted,
                  fontSize: 13,
                ),
                prefixIcon: const Icon(
                  Icons.link,
                  size: 20,
                  color: HermesColors.inkSecondary,
                ),
                filled: true,
                fillColor: HermesColors.cardSurface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: HermesColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: HermesColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: HermesColors.electricTeal,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  key: const Key('skill_import_fetch_button'),
                  onPressed: busy
                      ? null
                      : () {
                          widget.cubit.importSkillFromUrl(
                            _controller.text.trim(),
                          );
                        },
                  child: const Text('Fetch'),
                ),
                TextButton(
                  key: const Key('skill_import_cancel_button'),
                  onPressed: () {
                    widget.cubit.clearSkillImport();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Cancel'),
                ),
              ],
            ),
            if (busy)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  key: Key('skill_import_busy'),
                  color: HermesColors.electricTeal,
                  strokeWidth: 2,
                ),
              ),
            if (error != null)
              Text(
                error,
                key: const Key('skill_import_error'),
                style: const TextStyle(color: HermesColors.rose, fontSize: 12),
              ),
            if (preview != null)
              Container(
                key: const Key('skill_import_preview'),
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: HermesColors.cardSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: HermesColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preview.skill.name,
                      key: const Key('skill_import_preview_name'),
                      style: HermesTypography.monospace(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: HermesColors.electricTeal,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Category: ${preview.skill.category}',
                      style: HermesTypography.monospace(fontSize: 12),
                    ),
                    Text(
                      'Tier: ${preview.skill.tier}',
                      style: HermesTypography.monospace(fontSize: 12),
                    ),
                    Text(
                      'Requested tools: '
                      '${preview.skill.tools.isEmpty ? 'none' : preview.skill.tools.join(', ')}',
                      key: const Key('skill_import_tools'),
                      style: HermesTypography.monospace(fontSize: 12),
                    ),
                    Text(
                      'Estimated prompt size: '
                      '~${preview.estimatedPromptChars} chars',
                      key: const Key('skill_import_prompt_size'),
                      style: HermesTypography.monospace(fontSize: 12),
                    ),
                    Text(
                      'Source: ${preview.sourceUrl}',
                      style: HermesTypography.monospace(fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    if (preview.canImport)
                      const Text(
                        'SECURITY SCAN: PASSED',
                        key: Key('skill_import_scan_verdict'),
                        style: TextStyle(
                          color: HermesColors.emerald,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      Container(
                        key: const Key('skill_import_scan_verdict'),
                        child: Text(
                          'SECURITY SCAN: REJECTED - '
                          '${preview.scan.rejectionReason ?? 'Skill rejected by security scan'}',
                          key: const Key('skill_import_rejection_reason'),
                          style: const TextStyle(
                            color: HermesColors.rose,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          key: const Key('skill_import_confirm_button'),
                          onPressed: preview.canImport
                              ? () async {
                                  final s = await widget.cubit
                                      .confirmSkillImport();
                                  if (s != null && context.mounted) {
                                    Navigator.of(context).pop();
                                  }
                                }
                              : null,
                          child: const Text('Import'),
                        ),
                        TextButton(
                          key: const Key('skill_import_cancel_button'),
                          onPressed: () {
                            widget.cubit.clearSkillImport();
                            Navigator.of(context).pop();
                          },
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
