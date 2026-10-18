// A separate isolate preserves the real process-wide uncertainty quarantine.
import 'background_order_alert_registration_uncertainty_test.dart' as fixture;

void main() => fixture.registrationUncertaintyScenario(gatewayFailure: true);
