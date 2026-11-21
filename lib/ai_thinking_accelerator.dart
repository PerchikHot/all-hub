/// Experimental planning layer for future multi-model orchestration.
/// This module never claims to speed up inference without measurements.
/// No model is invoked here until a real backend is connected.
enum AiModelTier { lightweight, balanced, advanced }
enum AiWorkload { quick, normal, complex }

class AiThinkingPlan {
  const AiThinkingPlan({
    required this.workload,
    required this.primary,
    required this.verifyWithSecondModel,
    required this.useCache,
    required this.parallelCandidates,
  });

  final AiWorkload workload;
  final AiModelTier primary;
  final bool verifyWithSecondModel;
  final bool useCache;
  final bool parallelCandidates;
}

class AiThinkingAccelerator {
  const AiThinkingAccelerator();

  /// Pure, deterministic routing policy. Future runtimes can consume this
  /// plan, but must measure memory, latency and actual model availability.
  AiThinkingPlan plan({
    required AiWorkload workload,
    bool hasAdvancedModel = false,
    bool hasBalancedModel = false,
    bool allowParallel = false,
    bool sensitive = false,
  }) {
    final tier = switch (workload) {
      AiWorkload.quick => AiModelTier.lightweight,
      AiWorkload.normal => hasBalancedModel
          ? AiModelTier.balanced : AiModelTier.lightweight,
      AiWorkload.complex => hasAdvancedModel
          ? AiModelTier.advanced
          : hasBalancedModel
              ? AiModelTier.balanced
              : AiModelTier.lightweight,
    };
    return AiThinkingPlan(
      workload: workload,
      primary: tier,
      verifyWithSecondModel: workload == AiWorkload.complex &&
          (hasBalancedModel || hasAdvancedModel),
      useCache: !sensitive && workload == AiWorkload.quick,
      parallelCandidates: allowParallel &&
          workload == AiWorkload.complex && hasAdvancedModel,
    );
  }
}
