import 'package:flutter_ai_agent/domain/entities/skills/skill.dart';

/// Skill descriptor for structured document creation / PDF export.
///
/// Lives in the domain layer so the bundled skills registry can register it
/// without depending on the data layer.
const Skill docBuilderSkillDescriptor = Skill(
  id: 'doc_builder',
  name: 'doc_builder',
  description:
      'Structured document creation, report writing, and styled Markdown-to-PDF export to the device workspace.',
  category: 'Productivity',
  tier: 'Tier 1 Auto',
  version: 'v1.0.0',
  author: 'Flames',
  tools: ['export_document_pdf'],
  prompts: [
    'Create a PDF report summarizing this quarter',
    'Export this markdown as a styled PDF',
  ],
  instructions:
      'Build documents with a clear hierarchy: title, then a one-paragraph executive summary, then numbered sections with headings and subheadings; use Markdown pipe tables for tabular data and fenced code blocks for code/commands. Never invent data the user did not provide. Before exporting, show the user the outline and the exact title. Then call export_document_pdf(title, markdownContent) with the full Markdown body and report the saved absolute path back to the user.',
);
