/// Security tiers for tool execution within the agent loop.
///
/// Tier 1: Read-Only / Ambient (auto-execute).
/// Tier 2: Sensitive / Permissioned (auto-execute only if runtime permission is granted).
/// Tier 3: State-Modifying / Destructive (HITL confirmation required).
enum SecurityTier {
  tier1Auto,
  tier2Permission,
  tier3Hitl,
}

/// Security policy helper for checking tool execution constraints.
class SecurityPolicy {
  const SecurityPolicy._();

  /// Whether the tool can be auto-executed without user confirmation.
  static bool isAutoExecute(SecurityTier tier) {
    return tier == SecurityTier.tier1Auto;
  }

  /// Whether the tool requires Human-in-the-Loop approval before execution.
  static bool requiresHitl(SecurityTier tier) {
    return tier == SecurityTier.tier3Hitl;
  }

  /// Whether the tool requires permission evaluation.
  static bool requiresPermission(SecurityTier tier) {
    return tier == SecurityTier.tier2Permission;
  }
}
