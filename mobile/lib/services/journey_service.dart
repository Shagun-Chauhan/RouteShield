import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../providers/providers.dart';

/// Ends a journey exactly once. Existing repository calls are reused; nothing is cleared locally
/// unless the backend (or demo repository) accepted the change, so a failed request leaves the
/// journey active instead of silently losing it.
class JourneyService {
  JourneyService(this._ref);
  final Ref _ref;
  bool _finishing = false;

  bool get busy => _finishing;

  /// Returns null on success, otherwise a message to show the user.
  Future<String?> finish(Journey j, {bool cancel = false}) async {
    if (_finishing) return null; // duplicate tap
    if (_ref.read(activeJourneyProvider)?.id != j.id) return null; // already ended
    _finishing = true;
    try {
      await _ref.read(repositoryProvider).completeJourney(j.id, cancelled: cancel);
      _ref.read(activeJourneyProvider.notifier).state = null; // stops tracking (see livePositionProvider)
      _ref.read(selectedRouteProvider.notifier).state = null;
      return null;
    } catch (e) {
      return 'Could not ${cancel ? 'cancel' : 'complete'} the journey: $e. It is still active.';
    } finally {
      _finishing = false;
    }
  }
}

final journeyServiceProvider = Provider<JourneyService>((ref) => JourneyService(ref));
