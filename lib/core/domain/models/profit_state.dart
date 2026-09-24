/// Sealed hierarchy representing the profit calculation state for a TAKEN record
/// linked to a GIVEN record.
///
/// Mandated by Business Architecture Spec §10.2:
/// - Defined in :core:domain as a business concept, not a UI detail.
/// - Exposes:
///   * [InterimProfit]: when the linked GIVEN record is still ACTIVE.
///   * [NetProfit]: when the linked GIVEN record is SETTLED.
///   * [NoProfit]: when unlinked, not TAKEN, or broken FK (never crash on broken FK).
sealed class ProfitState {
  const ProfitState();

  const factory ProfitState.interim(double amount) = InterimProfit;
  const factory ProfitState.net(double amount) = NetProfit;
  const factory ProfitState.none() = NoProfit;

  /// Human-readable profit label
  String? get label {
    return switch (this) {
      InterimProfit() => 'Interim Profit',
      NetProfit() => 'Net Profit',
      NoProfit() => null,
    };
  }

  /// Extracted profit amount (if any)
  double? get profitAmount {
    return switch (this) {
      InterimProfit(:final amount) => amount,
      NetProfit(:final amount) => amount,
      NoProfit() => null,
    };
  }
}

class InterimProfit extends ProfitState {
  final double amount;
  const InterimProfit(this.amount);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InterimProfit &&
          runtimeType == other.runtimeType &&
          amount == other.amount;

  @override
  int get hashCode => amount.hashCode;

  @override
  String toString() => 'InterimProfit($amount)';
}

class NetProfit extends ProfitState {
  final double amount;
  const NetProfit(this.amount);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetProfit &&
          runtimeType == other.runtimeType &&
          amount == other.amount;

  @override
  int get hashCode => amount.hashCode;

  @override
  String toString() => 'NetProfit($amount)';
}

class NoProfit extends ProfitState {
  const NoProfit();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoProfit && runtimeType == other.runtimeType;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'NoProfit()';
}
