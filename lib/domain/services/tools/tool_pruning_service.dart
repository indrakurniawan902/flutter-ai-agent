/// Contract for client-side, heuristic tool pruning.
///
/// The full device tool set is large. Before a completion request is sent to
/// the model, this service narrows the OpenAI tool definitions down to the
/// subset relevant to the user's prompt so the model sees only the tools it
/// likely needs (plus discovery meta-tools it can call to fetch the rest).
abstract class ToolPruningService {
  /// Returns the pruned subset of [fullToolDefinitions] for [prompt].
  ///
  /// When [enabled] is false the input list is returned unchanged. Otherwise
  /// only entries whose function name belongs to a category matched by the
  /// prompt are kept, always alongside the `tool_search` and `tool_describe`
  /// meta-tools. A prompt that matches no category collapses to just those
  /// two meta-tool definitions.
  ///
  /// Each entry keeps the OpenAI tool-map shape:
  /// `{'type': 'function', 'function': {'name': ..., 'description': ...,
  /// 'parameters': ...}}`.
  List<Map<String, dynamic>> prune({
    required String prompt,
    required List<Map<String, dynamic>> fullToolDefinitions,
    required bool enabled,
  });
}
