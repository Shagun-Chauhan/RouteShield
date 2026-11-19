// Explainable, configurable rule-based segment safety engine.
// RISK (how concerning the known evidence is) and CONFIDENCE (how much evidence we have) are kept separate.
// Missing data never lowers risk: it lowers confidence and is listed under missingInformation.

export type Evidence = {
  lighting?: { level: 'good' | 'poor' | 'none'; observedAt: Date };
  roadCondition?: { level: 'good' | 'fair' | 'poor'; observedAt: Date };
  incidents?: { severity: 1 | 2 | 3; observedAt: Date }[];
  reports?: { category: string; verified: boolean; observedAt: Date }[]; // moderated only
};

export type RiskConfig = {
  weights: { lighting: number; roadCondition: number; incident: number; report: number };
  freshnessHalfLifeDays: number;
  riskBands: { moderate: number; high: number };
  confidenceBands: { medium: number; high: number };
};

export const DEFAULT_CONFIG: RiskConfig = {
  weights: { lighting: 30, roadCondition: 20, incident: 15, report: 10 },
  freshnessHalfLifeDays: 30,
  riskBands: { moderate: 25, high: 55 },
  confidenceBands: { medium: 0.4, high: 0.7 },
};

export type SegmentAssessment = {
  riskScore: number | null; // null = cannot estimate (no evidence at all). NOT "safe".
  riskLevel: 'low' | 'moderate' | 'high' | 'unknown';
  confidence: number; // 0..1
  confidenceLevel: 'low' | 'medium' | 'high';
  freshestEvidenceAt: Date | null;
  reasons: string[];
  missingInformation: string[];
};

const decay = (at: Date, now: Date, halfLife: number) =>
  Math.pow(0.5, Math.max(0, now.getTime() - at.getTime()) / 86_400_000 / halfLife);

export function assessSegment(e: Evidence, now = new Date(), cfg = DEFAULT_CONFIG): SegmentAssessment {
  const reasons: string[] = [];
  const missing: string[] = [];
  let risk = 0;
  let confidenceSum = 0;
  const dates: Date[] = [];
  const w = cfg.weights;

  if (e.lighting) {
    const f = decay(e.lighting.observedAt, now, cfg.freshnessHalfLifeDays);
    const base = e.lighting.level === 'none' ? 1 : e.lighting.level === 'poor' ? 0.6 : 0;
    risk += w.lighting * base * f;
    if (base > 0) reasons.push(`Lighting reported as ${e.lighting.level}`);
    confidenceSum += 0.3 * f; dates.push(e.lighting.observedAt);
  } else missing.push('Lighting information');

  if (e.roadCondition) {
    const f = decay(e.roadCondition.observedAt, now, cfg.freshnessHalfLifeDays);
    const base = e.roadCondition.level === 'poor' ? 1 : e.roadCondition.level === 'fair' ? 0.3 : 0;
    risk += w.roadCondition * base * f;
    if (base > 0) reasons.push(`Road condition reported as ${e.roadCondition.level}`);
    confidenceSum += 0.25 * f; dates.push(e.roadCondition.observedAt);
  } else missing.push('Road condition information');

  if (e.incidents?.length) {
    for (const i of e.incidents) {
      const f = decay(i.observedAt, now, cfg.freshnessHalfLifeDays);
      risk += w.incident * (i.severity / 3) * f;
      dates.push(i.observedAt);
    }
    reasons.push(`${e.incidents.length} incident record(s) on this segment`);
    confidenceSum += 0.25;
  } else missing.push('Incident records');

  if (e.reports?.length) {
    for (const r of e.reports) {
      const f = decay(r.observedAt, now, cfg.freshnessHalfLifeDays);
      risk += w.report * (r.verified ? 1 : 0.4) * f;
      dates.push(r.observedAt);
    }
    reasons.push(`${e.reports.length} community report(s) (${e.reports.filter(r => r.verified).length} verified)`);
    confidenceSum += Math.min(0.2, 0.07 * e.reports.length);
  } else missing.push('Community reports');

  const confidence = Math.min(1, confidenceSum);
  const riskScore = dates.length === 0 ? null : Math.min(100, Math.round(risk));
  const riskLevel = riskScore === null ? 'unknown'
    : riskScore >= cfg.riskBands.high ? 'high'
    : riskScore >= cfg.riskBands.moderate ? 'moderate' : 'low';
  const confidenceLevel = confidence >= cfg.confidenceBands.high ? 'high'
    : confidence >= cfg.confidenceBands.medium ? 'medium' : 'low';
  if (riskScore === null) reasons.push('No evidence available: risk cannot be estimated (this does not mean the road is safe)');
  else if (confidenceLevel === 'low') reasons.push('Low evidence confidence: treat this estimate cautiously');

  const freshestEvidenceAt = dates.length ? new Date(Math.max(...dates.map(d => d.getTime()))) : null;
  return { riskScore, riskLevel, confidence: +confidence.toFixed(2), confidenceLevel, freshestEvidenceAt, reasons, missingInformation: missing };
}
