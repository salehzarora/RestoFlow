export type WelcomeVideoByteReceipt = { status: number; first: number; last: number; total: number; bytes: number; sha256: string };
export function welcomeVideoResponseEvidence(response: {url:string; status:number; contentRange:string|null; body:Buffer}, source:Buffer):WelcomeVideoByteReceipt;
export function welcomeVideoCoverage(receipts:readonly unknown[], total:number):boolean;
