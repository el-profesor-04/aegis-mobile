import 'dart:math' as math;

class ImpactClassConfig {
  final double lambdaHr;
  final String label;
  final double? halfLifeHrs;

  const ImpactClassConfig({
    required this.lambdaHr,
    required this.label,
    this.halfLifeHrs,
  });
}

const Map<String, ImpactClassConfig> impactClassConfig = {
  'C1': ImpactClassConfig(lambdaHr: 0.030, label: 'Transient', halfLifeHrs: 23),
  'C2': ImpactClassConfig(lambdaHr: 0.006, label: 'Short-term', halfLifeHrs: 116),
  'C3': ImpactClassConfig(lambdaHr: 0.0009, label: 'Acute', halfLifeHrs: 770),
  'C4': ImpactClassConfig(lambdaHr: 0.0001, label: 'Persistent', halfLifeHrs: 6931),
  'C5': ImpactClassConfig(lambdaHr: 0.0, label: 'Chronic', halfLifeHrs: null),
  'C6': ImpactClassConfig(lambdaHr: 0.001, label: 'Cyclic', halfLifeHrs: 693),
};

double calculateRelevance(double s0, double lambdaHr, double hoursSince) {
  if (lambdaHr == 0) return s0;
  return s0 * math.exp(-lambdaHr * hoursSince);
}
