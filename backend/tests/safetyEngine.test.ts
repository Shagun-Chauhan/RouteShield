import { assessSegment } from '../src/services/safetyEngine';
const now = new Date('2026-10-30T12:00:00Z');
const daysAgo = (d: number) => new Date(now.getTime() - d * 86_400_000);

test('no evidence => unknown risk, never "low"/safe', () => {
  const a = assessSegment({}, now);
  expect(a.riskScore).toBeNull();
  expect(a.riskLevel).toBe('unknown');
  expect(a.confidenceLevel).toBe('low');
  expect(a.missingInformation.length).toBe(4);
});
test('poor fresh lighting raises risk and is explained', () => {
  const a = assessSegment({ lighting: { level: 'none', observedAt: daysAgo(1) } }, now);
  expect(a.riskScore).toBeGreaterThan(20);
  expect(a.reasons.join(' ')).toMatch(/Lighting/);
});
test('old evidence decays', () => {
  const fresh = assessSegment({ lighting: { level: 'none', observedAt: daysAgo(1) } }, now);
  const old = assessSegment({ lighting: { level: 'none', observedAt: daysAgo(120) } }, now);
  expect(old.riskScore!).toBeLessThan(fresh.riskScore!);
});
test('risk and confidence are independent', () => {
  const a = assessSegment({ lighting: { level: 'good', observedAt: daysAgo(1) }, roadCondition: { level: 'good', observedAt: daysAgo(1) } }, now);
  expect(a.riskLevel).toBe('low');
  expect(a.confidence).toBeGreaterThan(0.4);
});
test('verified reports weigh more than unverified', () => {
  const v = assessSegment({ reports: [{ category: 'hazard', verified: true, observedAt: daysAgo(1) }] }, now);
  const u = assessSegment({ reports: [{ category: 'hazard', verified: false, observedAt: daysAgo(1) }] }, now);
  expect(v.riskScore!).toBeGreaterThan(u.riskScore!);
});
