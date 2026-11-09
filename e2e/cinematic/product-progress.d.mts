export type ProductStage =
    'fixture'
  | 'route-setup'
  | 'login'
  | 'baseline-invariants'
  | 'initial-model-count'
  | 'open-product'
  | 'choose-source'
  | 'highres-source-metadata'
  | 'highres-cutout-render'
  | 'highres-original-render'
  | 'save-source'
  | 'save-source-status'
  | 'save-source-result'
  | 'save-source-identifiers'
  | 'original-read-status'
  | 'original-read-result'
  | 'original-source-key'
  | 'original-selection-default'
  | 'replacement-selection-proof'
  | 'private-original-status'
  | 'private-original-bytes'
  | 'original-only-no-processing'
  | 'explicit-prepare'
  | 'candidate-session-reuse'
  | 'existing-close'
  | 'existing-reopen'
  | 'existing-prepare'
  | 'existing-verify'
  | 'cancel-await-model-download'
  | 'cancel-worker'
  | 'cancel-no-automatic-publication'
  | 'cancel-original-bytes'
  | 'fault-start-worker'
  | 'fault-observed'
  | 'fault-no-automatic-publication'
  | 'fault-original-bytes'
  | 'retry-worker'
  | 'worker-ready'
  | 'alpha-bypass-review'
  | 'model-chunk-count'
  | 'cutout-choice-enabled'
  | 'prepublication-no-register'
  | 'light-review-capture'
  | 'dark-review-capture'
  | 'publish-selection'
  | 'selection-readback'
  | 'original-after-publication'
  | 'registration-proof'
  | 'selected-private-read'
  | 'live-menu-readback'
  | 'published-image-fetch'
  | 'published-image-alpha'
  | 'restore-original-selection'
  | 'restore-original-readback'
  | 'close-product'
  | 'publication-counts'
  | 'unchanged-invariants'
  | 'transport-boundary'
  | 'success-evidence';
export type ProductSample = 'burger' | 'fries-cup' | 'platter' | 'drink' | 'burger-highres';
export type ProductOperation = 'save-source' | 'original-read';
export type ProductResponseFacts = {
  operation: ProductOperation; sample: ProductSample | null;
  httpStatus: number | null; envelopeOk: boolean | null;
  responseCode: 'permission_denied' | 'source_not_found' | '42501' | 'missing' | 'unclassified';
};
export type PublisherVariant = 'w480' | 'w960' | 'other';
export type PublisherPromiseState = 'pending' | 'fulfilled' | 'rejected';
export type PublisherReplyFacts = {
  ordinal: number; group: number | null; variant: PublisherVariant; httpStatus: number | null;
  stage: ProductStage | null; sample: ProductSample | null;
  finishedPromise: PublisherPromiseState; finishedPromiseStage: ProductStage | null;
  requestFinished: boolean; requestFinishedStage: ProductStage | null;
  requestFailed: boolean; requestFailedStage: ProductStage | null;
};
export type PublisherReplyReceipt = {
  limits: { replies: number; groups: number };
  observed: number; recorded: number; droppedReplies: number; groupOverflow: number; truncated: boolean;
  counts: { pending: number; fulfilled: number; rejected: number; requestFinished: number; requestFailed: number };
  replies: PublisherReplyFacts[];
};
export type PublisherReplyObservation = { variant?: unknown; status?: unknown; groupKey?: unknown; finished?: unknown };
export const PUBLISHER_REPLY_LIMITS: { readonly replies: 128; readonly groups: 32 };
export type ProductProgress = {
  advance(stage: ProductStage, sample?: ProductSample | null): void;
  complete(): void;
  recordResponse(operation: ProductOperation, status: unknown, body: unknown): void;
  observePublisherReply(requestKey: unknown, facts: PublisherReplyObservation | null | undefined): void;
  markPublisherRequestFinished(requestKey: unknown): void;
  markPublisherRequestFailed(requestKey: unknown): void;
  snapshot(): {
    status: 'PASS' | 'FAIL'; failedStage: ProductStage | null; sample: ProductSample | null;
    completedStages: { stage: ProductStage; sample: ProductSample | null }[];
    responses: ProductResponseFacts[];
    publisherReplies: PublisherReplyReceipt;
  };
};
export function createProductProgress(): ProductProgress;
export function captureProductResponse(progress: ProductProgress, operation: ProductOperation,
  status: unknown, readBody: () => Promise<unknown>): Promise<void>;
