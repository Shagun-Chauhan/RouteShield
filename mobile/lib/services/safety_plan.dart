enum Situation { lowBattery, connectivityLoss, gpsLoss, routeDeviation, missedCheckIn }

class PlanStep {
  final String title, detail;
  const PlanStep(this.title, this.detail);
}

String situationLabel(Situation s) => switch (s) {
      Situation.lowBattery => 'Low battery',
      Situation.connectivityLoss => 'No connectivity',
      Situation.gpsLoss => 'GPS lost',
      Situation.routeDeviation => 'Off route',
      Situation.missedCheckIn => 'Missed check-in',
    };

/// Rule-based plan compiler. No AI, no invented facts: every step follows from the inputs.
List<PlanStep> compilePlan(Situation s, {required bool hasContacts, int? batteryPct, DateTime? lastLocationAt}) {
  final steps = <PlanStep>[];
  final contactStep = hasContacts
      ? const PlanStep('Tell a trusted contact', 'Use the Contacts screen to call or message someone you trust.')
      : const PlanStep('Add a trusted contact', 'You have none saved. Add one in Contacts before your next journey.');
  String hhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  switch (s) {
    case Situation.lowBattery:
      steps.addAll([
        PlanStep('Turn on Low-Battery Survival Mode', batteryPct == null ? 'Reduces location and network activity.' : 'Battery is at $batteryPct%. Survival Mode reduces location and network activity.'),
        const PlanStep('Lower screen brightness and close other apps', 'This is the quickest way to save power.'),
        contactStep,
        const PlanStep('Note your position', 'Check the last recorded location and its time on the Low-Battery screen.'),
      ]);
    case Situation.connectivityLoss:
      steps.addAll([
        const PlanStep('Rely on saved journey details', 'Your route and contacts are stored on this phone.'),
        const PlanStep('Move to a more open area if it is safe', 'Signal is often better away from tall buildings or tunnels.'),
        const PlanStep('Share location once signal returns', 'Alerts to contacts are sent only when a connection exists.'),
        contactStep,
      ]);
    case Situation.gpsLoss:
      steps.addAll([
        PlanStep('Use the last recorded location', lastLocationAt == null ? 'No location has been recorded yet.' : 'Last recorded at ${hhmm(lastLocationAt)}.'),
        const PlanStep('Check location services', 'Make sure Location is on and permission is granted to RouteShield.'),
        const PlanStep('Use landmarks and signs', 'Follow main roads where possible until GPS returns.'),
        contactStep,
      ]);
    case Situation.routeDeviation:
      steps.addAll([
        const PlanStep('Confirm you meant to leave the route', 'Detours are common. Only continue if you are comfortable.'),
        const PlanStep('Review alternative routes', 'Tap Recover route to fetch and compare updated options.'),
        const PlanStep('Prefer busy, well-lit roads', 'If the area feels unsafe, head to the nearest Safe Haven.'),
        contactStep,
      ]);
    case Situation.missedCheckIn:
      steps.addAll([
        const PlanStep('Check in if you are okay', 'A missed check-in is not treated as proof of an emergency.'),
        const PlanStep('Contacts are notified only with your consent', 'You choose whether to alert them.'),
        contactStep,
        const PlanStep('In immediate danger, call emergency services', 'Dial 112 (India). RouteShield does not replace emergency services.'),
      ]);
  }
  return steps;
}
