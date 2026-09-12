/// Operating mode for the Chat interface.
enum ChatMode {
  /// Direct LLM mode (Fase 1): Local ReAct loop calling OpenAI-compatible LLM directly.
  direct,

  /// Gateway Remote Node mode (Fase 2): Mobile device connected to Hermes Gateway as a remote execution node.
  gateway;

  /// Returns true if the chat interface is in Direct LLM mode.
  bool get isDirect => this == ChatMode.direct;

  /// Returns true if the chat interface is in Gateway Remote Node mode.
  bool get isGateway => this == ChatMode.gateway;
}
