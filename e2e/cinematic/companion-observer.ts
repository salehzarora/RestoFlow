import { expect, type Page, type Request } from '@playwright/test';

type Json = Record<string, any>;
export type CompanionUi = 'ready' | 'uncertain' | 'native' | 'unavailable' | 'unknown';
const labels = [
    ['ready', 'الخلفية الأعلى دقة جاهزة'],
    ['uncertain', 'لم يُؤكد تحضير الدقة الأعلى'],
    ['native', 'لا يتيح الأصل نسخة أكبر'],
    ['unavailable', 'تعذّر تحضير خلفية أكبر'],
] as const;
export function companionStatus(page: Page) {
    // Flutter also announces a copy outside its semantics tree. Read the
    // real, physically revealed status using the same scope as content Save.
    return page.locator('flt-semantics').getByText(new RegExp(labels.map(([,label])=>label).join('|')));
}
export function classifyCompanion(text: string): CompanionUi {
    const matches = labels.filter(([,label])=>text.includes(label));
    return matches.length === 1 ? matches[0][0] : 'unknown';
}
type Attempt = {
    request: Json;
    http: number | null;
    terminal: 'pending' | 'finished' | 'failed';
    bodyState: 'pending' | 'parsed' | 'unreadable' | 'failed-request';
    failure?: 'aborted' | 'length-mismatch' | 'connection-reset' | 'other-network' | 'invalid-json' | 'non-object' | 'body-read';
    body?: Json;
};
const rung = (value: unknown) => Number.isInteger(value) && Number(value) >= 0 && Number(value) <= 4 ? Number(value) : null;
const publicStatus = (body?: Json) => {
    const status = body?.status;
    return ['published', 'not_needed', 'ladder_next', 'refused', 'unavailable'].includes(status) ? status : 'unclassified';
};

export class CompanionObserver {
    private readonly attempts = new Map<Request, Attempt>();
    private readonly states: CompanionUi[] = [];
    private replayed: boolean | null = null;

    attach(page: Page, endpoint: string) {
        page.on('request', request => {
            if (request.url() !== endpoint || request.method() !== 'POST') return;
            const body = request.postDataJSON();
            if (body?.slot !== 'background') return;
            this.attempts.set(request, { request:body, http:null, terminal:'pending', bodyState:'pending' });
        });
        page.on('response', response => {
            const attempt = this.attempts.get(response.request());
            if (attempt) attempt.http = response.status();
        });
        page.on('requestfailed', request => {
            const attempt = this.attempts.get(request);
            if (!attempt) return;
            attempt.terminal = 'failed';
            attempt.bodyState = 'failed-request';
            const error = request.failure()?.errorText;
            attempt.failure = error === 'net::ERR_ABORTED' ? 'aborted' :
                error === 'net::ERR_CONTENT_LENGTH_MISMATCH' ? 'length-mismatch' :
                error === 'net::ERR_CONNECTION_RESET' ? 'connection-reset' : 'other-network';
        });
        page.on('requestfinished', async request => {
            const attempt = this.attempts.get(request);
            if (!attempt) return;
            attempt.terminal = 'finished';
            try {
                const response = await request.response();
                const json = await response?.json();
                if (!json || typeof json !== 'object' || Array.isArray(json)) {
                    attempt.bodyState = 'unreadable';
                    attempt.failure = 'non-object';
                    return;
                }
                attempt.body = json;
                attempt.bodyState = 'parsed';
            } catch (error) {
                attempt.bodyState = 'unreadable';
                attempt.failure = error instanceof SyntaxError ? 'invalid-json' : 'body-read';
            }
        });
    }

    evidence(baseMediaId?: string) {
        return { uiStates:[...this.states], sameRequestReplay:this.replayed,
            attempts:[...this.attempts.values()].slice(0,40).map(a => ({
                matchesBase:baseMediaId === undefined ? null : a.request.base_media_id === baseMediaId,
                baseRung:rung(a.request.base_rung), rung:rung(a.request.rung),
                http:a.http, terminal:a.terminal, body:a.bodyState, envelope:publicStatus(a.body), failure:a.failure ?? null,
                responseBaseMatches:a.body?.media?.base_media_id === undefined ? null : a.body.media.base_media_id === a.request.base_media_id,
            })) };
    }

    async verify(baseMediaId: string, readUi: () => Promise<CompanionUi>, retry: () => Promise<void>) {
        const matching = () => [...this.attempts.values()].filter(a => a.request.base_media_id === baseMediaId);
        const read = async () => {
            const index = this.states.push('unknown') - 1;
            const value = await readUi();
            if (['ready','uncertain','native','unavailable'].includes(value)) this.states[index] = value;
            return this.states[index];
        };
        let state = await read();
        let start = 0;
        if (state === 'uncertain') {
            const before = matching();
            expect(before.length, 'Uncertain UI must refer to an observed background request for the saved base').toBeGreaterThan(0);
            const pending = before[before.length-1].request;
            start = before.length;
            await retry();
            await expect.poll(() => matching().length, { timeout:120000, message:'Retry sends another request for the saved base' }).toBeGreaterThan(start);
            const replay = matching()[start].request;
            this.replayed = ['request_id','base_media_id','rung','base_rung'].every(k => pending[k] !== undefined && replay[k] === pending[k]);
            expect(this.replayed, 'The actual UI retries the identical uncertain request').toBe(true);
            await expect.poll(() => matching()[start].terminal, { timeout:120000, message:'Observe the retry request terminal event before reading the updated UI' }).not.toBe('pending');
            state = await read();
        }
        expect(state, 'Higher-resolution Dashboard terminal state').toBe('ready');
        const candidates = () => matching().slice(start);
        const result = () => candidates().find(a => a.http === 200 && a.bodyState === 'parsed' &&
            a.body?.ok === true && a.body.status === 'published' && a.body.media?.base_media_id === baseMediaId);
        // A header is not a completed reply. A failed request never resolves
        // Playwright's requestfinished signal; observe its own terminal event.
        await expect.poll(() => !!result() || (candidates().length > 0 && candidates().every(a => a.bodyState !== 'pending')),
            { timeout:120000, message:'Wait for the correlated companion response or its terminal read failure' }).toBe(true);
        const publication = result();
        expect(!!publication, 'Ready UI requires a readable, published Edge envelope for this exact saved base').toBe(true);
        return { body:publication!.body!, replayed:this.replayed === true };
    }
}
