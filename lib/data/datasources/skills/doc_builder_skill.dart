import 'dart:async';
import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/common/failure_message.dart';
import 'package:flutter_ai_agent/data/datasources/skills/markdown_pdf_renderer.dart';
import 'package:flutter_ai_agent/domain/entities/skills/doc_builder_skill_descriptor.dart';
import 'package:flutter_ai_agent/domain/entities/skills/skill.dart';
import 'package:flutter_ai_agent/domain/tools/chat/file_workspace_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/security_policy.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/file_workspace_service.dart'
    show DefaultFileSystemWrapper;

/// Skill descriptor + tool factory for structured document creation / PDF
/// export. The rendering path is pure Dart; persistence is routed through the
/// injected [FileSystemWrapper] so the data layer never imports `path_provider`.
class DocBuilderSkill {
  static const String id = 'doc_builder';
  static const String toolName = 'export_document_pdf';

  /// The skill descriptor registered in the bundled registry.
  ///
  /// Single source of truth lives in the domain layer.
  static const Skill descriptor = docBuilderSkillDescriptor;

  /// Registers the [toolName] tool on [registry].
  ///
  /// [fileSystem] is injectable for tests; production uses the platform
  /// documents directory via [DefaultFileSystemWrapper].
  static void registerTools(
    ToolRegistry registry, {
    FileSystemWrapper? fileSystem,
  }) {
    final fs = fileSystem ?? DefaultFileSystemWrapper();
    registry.register(
      RegisteredTool(
        name: toolName,
        description:
            'Renders Markdown content (title, executive summary, sections, tables, code blocks) into a styled PDF document and saves it to the device workspace. Returns the saved absolute path.',
        parameters: const {
          'type': 'object',
          'properties': {
            'title': {
              'type': 'string',
              'description': 'Document title, rendered on a cover-style heading.',
            },
            'markdownContent': {
              'type': 'string',
              'description': 'Full Markdown body of the document.',
            },
            'outputFileName': {
              'type': 'string',
              'description':
                  'Optional file name without extension (default: slugified title).',
            },
          },
          'required': ['title', 'markdownContent'],
        },
        securityTier: SecurityTier.tier1Auto,
        innerWindow: DocBuilderSkill.exportTimeout,
        execute: (args) => exportDocument(
          fileSystem: fs,
          title: args['title']?.toString() ?? '',
          markdownContent: args['markdownContent']?.toString() ?? '',
          outputFileName: args['outputFileName']?.toString(),
        ),
      ),
    );
  }

  /// Upper bound for one render + write cycle. A pathological renderer or a
  /// silent filesystem call must settle as a CacheFailure, never hang the
  /// caller.
  ///
  /// The outer-bound > inner-bound invariant is enforced by the
  /// [RegisteredTool] assert and asserted by a unit test. If this value were
  /// larger than the registry bound, the human-readable CacheFailure would be
  /// replaced by a generic `tool_timeout`.
  static const Duration exportTimeout = Duration(seconds: 8);

  /// Renders [markdownContent] and writes the PDF into
  /// `<documents dir>/documents/`, returning the absolute written path.
  static Future<Either<Failure, String>> exportDocument({
    required FileSystemWrapper fileSystem,
    required String title,
    required String markdownContent,
    String? outputFileName,
    DateTime? now,
  }) async {
    try {
      return await _exportDocument(
        fileSystem: fileSystem,
        title: title,
        markdownContent: markdownContent,
        outputFileName: outputFileName,
        now: now,
      ).timeout(exportTimeout);
    } on TimeoutException {
      return Left(
        CacheFailure(
          'Failed to export PDF document: the renderer did not finish within '
          '${exportTimeout.inSeconds}s',
        ),
      );
    } catch (e) {
      return Left(
        CacheFailure(
          FailureMessage.humanize(e, context: 'Failed to export PDF document'),
        ),
      );
    }
  }

  static Future<Either<Failure, String>> _exportDocument({
    required FileSystemWrapper fileSystem,
    required String title,
    required String markdownContent,
    String? outputFileName,
    DateTime? now,
  }) async {
    final resolvedTitle = title.trim().isEmpty ? 'Untitled document' : title.trim();
    final bytes = await _render(resolvedTitle, markdownContent);

    final baseDir = await fileSystem.getDocumentsDirectory();
    if (baseDir.trim().isEmpty) {
      return const Left(CacheFailure('Documents directory unavailable'));
    }

    final slugSource = (outputFileName == null || outputFileName.trim().isEmpty)
        ? resolvedTitle
        : outputFileName.trim();
    final slug = _slugify(slugSource);
    final stamp = _timestamp(now ?? DateTime.now());
    final separator = baseDir.endsWith('/') ? '' : '/';
    final path = '$baseDir${separator}documents/doc_${slug}_$stamp.pdf';

    await fileSystem.writeFileAsBytes(path, bytes);
    return Right('Document exported successfully to $path');
  }

  static Future<Uint8List> _render(String title, String markdownContent) async {
    final document = pw.Document(
      title: title,
      author: 'Flames',
      creator: 'Flames Doc Builder',
    );
    document.addPage(
      const MarkdownPdfRenderer().render(
        markdown: markdownContent,
        title: title,
      ),
    );
    return Uint8List.fromList(await document.save());
  }

  static String _slugify(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return 'document';
    var out = trimmed.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    out = out.replaceAll(RegExp(r'^_+|_+$'), '');
    if (out.isEmpty) return 'document';
    return out.length > 60 ? out.substring(0, 60) : out;
  }

  static String _timestamp(DateTime now) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}
