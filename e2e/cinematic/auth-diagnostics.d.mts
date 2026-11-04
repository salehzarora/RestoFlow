export function isPasswordGrantRequest(url: string, method: string, apiOrigin: string): boolean;
export function authRequestEvidence(url: string, postData: string | null,
  expected: { email: string; password: string }): {
  grantType: string; submittedEmailMatchesFixture: boolean; submittedPasswordMatchesFixture: boolean;
};
export function authResponseEvidence(result: { status: number; contentType?: string; data: unknown }, durationMs: number): {
  httpStatus: number | null; contentType: string; errorCode: string; oauthError: string; durationMs: number | null;
};
