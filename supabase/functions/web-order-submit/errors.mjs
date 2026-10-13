/** Public errors contain fixed codes only; never put request or transport data here. */
export class RequestError extends Error {
  constructor(code, status = 400) {
    super(code);
    this.name = "RequestError";
    this.code = code;
    this.status = status;
  }
}
