// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-W1-PROFILE-CANDIDATE-001: the UNWIRED source profile candidate for the
// documented Z-Credit WebService PIN PAD wire contract (execution packet
// docs/BIZBOT_PAYMENTS_ZCREDIT_PILOT_001E_W1_PROFILE_CANDIDATE_001_EXECUTION.md, section 6).
//
// Plain data in the closed schema of engine.mjs (validateProfile); it imports nothing. Every route, member name,
// accepted JSON type, constant and code is a FACT row of the accepted W1 evidence matrix (row IDs inline; the packet
// traces each one to its source, page or section and SHA-256). It holds no base URL (runtime configuration, gate
// Q-047), no credential, KEY, terminal, PIN-pad or card value (a credential spec names only a member of the
// configuration's sealed credential record), no not-found or pending code (none is documented: E2-23, E2-24, Q-048)
// and no optional reference or card-derived field (E4, unmapped). Only the tests import it: index.ts keeps
// providerProfile: null until the packet's wiring gates (Q-047; Q-049 with a matching 001D key formatter; E2-B; the
// deployment retention gate of section 8) are met.

/** Freeze a plain-data tree, so no importer can change the candidate. */
const frozen = (value) => {
  if (value !== null && typeof value === "object") {
    for (const key of Object.keys(value)) frozen(value[key]);
    Object.freeze(value);
  }
  return value;
};

/** A request member read from the attempt's credential record: `secret` names the record's member, never a value. */
const credential = (name, secret) => ({ name, from: "credential", secret });

export const ZCREDIT_PROFILE_CANDIDATE = frozen({
  version: "zcredit-ws-pinpad-candidate-1", // BIZBOT-internal; pinned with the content by the deployment guard
  routes: {
    commit: "/Transaction/CommitFullTransaction", // E1-04
    lookup: "/Transaction/GetTransactionStatusByTransactionUniqueIdForQuery", // E1-05
    release: "/Transaction/ReleasePinpad", // E1-07
  },
  request: {
    // Members in the order of the accepted redacted request fixture (an order the vendor does not document: E1-35).
    commit: [
      credential("TerminalNumber", "terminal_number"), // E1-08: a JSON string
      credential("Password", "password"), // E1-09
      { name: "Track2", from: "pinpad", prefix: "PINPAD" }, // E1-11: the device travels only here (E1-13)
      { name: "CardNumber", from: "const", value: { string: "" } }, // E1-14: left empty
      { name: "ExpDate_MMYY", from: "const", value: { string: "" } }, // E1-14: left empty
      { name: "TransactionSum", from: "amount" }, // E1-16, E5-06: the canonical X.XX number token
      { name: "TransactionType", from: "const", value: { string: "01" } }, // E1-18: a regular charge
      { name: "CurrencyType", from: "currency" }, // E1-17
      { name: "CreditType", from: "const", value: { integer: "1" } }, // E1-19: regular
      { name: "NumberOfPayments", from: "const", value: { integer: "1" } }, // E1-20: as in the request example
      { name: "J", from: "const", value: { integer: "0" } }, // E1-22: a regular charge; no J2 (E1-33)
      { name: "IsCustomerPresent", from: "const", value: { boolean: true } }, // E1-23
      { name: "AuthNum", from: "const", value: { string: "" } }, // E1-28: kept empty
      { name: "TransactionUniqueIdForQuery", from: "status_key" }, // E1-24, E3-01: the stored key (format: Q-049)
      { name: "TransactionUniqueID", from: "duplicate_key" }, // E1-25, E3-02: the stored key (format: Q-049)
      { name: "UseAdvancedDuplicatesCheck", from: "const", value: { boolean: false } }, // E1-26: sent explicitly
    ],
    lookup: [
      credential("TerminalNumber", "terminal_number"), // E1-30
      credential("Password", "password"), // E1-30
      { name: "UniqueQuery", from: "status_key" }, // E1-30, E3-01
    ],
    release: [
      credential("TerminalNumber", "terminal_number"), // E1-31
      credential("Password", "password"), // E1-31
      { name: "Track2", from: "pinpad", prefix: "PINPAD" }, // E1-31: the PIN pad only, no key (E1-32)
    ],
  },
  // One reply map serves the three operations, so the lookup's own phone flag IsTelAuthAbilty is never read (E2-16).
  // Each key accepts only its documented JSON type.
  reply: {
    error_flag: { name: "HasError", accept: ["boolean"] }, // E2-03
    provider_return_code: { name: "ReturnCode", accept: ["number"] }, // E2-04
    approval_type: { name: "ApprovalType", accept: ["string"] }, // E2-09
    phone_authorization: { name: "IsTelApprovalNeeded", accept: ["boolean"] }, // E2-15
    provider_status_code: { name: "StatusCode", accept: ["number"] }, // E2-17
    provider_amount: { name: "TransactionSum", accept: ["number"] }, // E2-26: zero to two decimals (D-064)
    provider_currency: { name: "CurrencyTypeCode", accept: ["number"] }, // E2-27, E5-02
    tip_amount: { name: "TipAmount", accept: ["number"] }, // E2-30: absent or zero is no tip (D-064)
  },
  codes: {
    approval_approved: ["1", "3", "03", "5", "8"], // E2-10 ("03" is the form of the documented examples)
    approval_declined: ["2", "4", "6"], // E2-11: the documented forms only; "0" and "7" are neither (E2-13)
    return_success: ["0"], // E2-04, E2-06
    return_duplicate: ["-88001", "-88002"], // E2-07, E2-08
    lookup_not_found: [], // none documented (E2-24, UNKNOWN; Q-048)
    lookup_pending: [], // none documented (E2-24, UNKNOWN; Q-048)
    status_approved: ["1", "2"], // E2-18
    status_voided: ["3"], // E2-19
    status_refunded: ["4"], // E2-20
    status_partial_refund: ["6"], // E2-21
    status_preauthorization: ["900", "901", "902", "903", "904"], // E2-22
    status_not_found: [], // none documented (E2-23, UNKNOWN; Q-048)
    status_pending: [], // none documented (E2-23, UNKNOWN; Q-048)
    currency_request: { ILS: { integer: "1" } }, // E1-17, E5-01
    currency_reply: { 1: "ILS" }, // E2-27, E5-02 (2 and 3 stay unmapped: E5-07)
  },
});
