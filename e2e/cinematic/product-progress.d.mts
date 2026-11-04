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
  | 'private-original-status'
  | 'private-original-bytes'
  | 'existing-await-auto'
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
export type ProductProgress = {
  advance(stage: ProductStage, sample?: ProductSample | null): void;
  complete(): void;
  recordResponse(operation: ProductOperation, status: unknown, body: unknown): void;
  snapshot(): {
    status: 'PASS' | 'FAIL'; failedStage: ProductStage | null; sample: ProductSample | null;
    completedStages: { stage: ProductStage; sample: ProductSample | null }[];
    responses: ProductResponseFacts[];
  };
};
export function createProductProgress(): ProductProgress;
export function captureProductResponse(progress: ProductProgress, operation: ProductOperation,
  status: unknown, readBody: () => Promise<unknown>): Promise<void>;
