/// Test-only helpers for the auth gate (RF-108). NOT part of the app runtime
/// surface - import only from tests. Lets app tests build a fake
/// [AuthContextFetcher] without depending on `restoflow_core` directly.
library;

import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';

import 'src/auth_context_fetcher.dart';

/// An [AuthContextFetcher] that always succeeds with [context].
AuthContextFetcher fetcherForContext(MyContext context) =>
    () async => Success<MyContext, AuthFailure>(context);

/// An [AuthContextFetcher] that always fails with [failure].
AuthContextFetcher fetcherForFailure(AuthFailure failure) =>
    () async => Failure<MyContext, AuthFailure>(failure);
