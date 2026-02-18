import "dotenv/config";
import type { SSEEvent, SSECompleteEvent, TinyFishOptions } from "./types.js";

const TINYFISH_BASE_URL = "https://agent.tinyfish.ai/v1/automation";

export interface TinyFishClientConfig {
  apiKey?: string;
  defaultStealth?: boolean;
  defaultProxyCountry?: "US" | "GB" | "CA" | "DE" | "FR" | "JP" | "AU";
  onProgress?: (purpose: string) => void;
}

export class TinyFishClient {
  private apiKey: string;
  private defaultStealth: boolean;
  private defaultProxyCountry?: string;
  private onProgress?: (purpose: string) => void;

  constructor(config: TinyFishClientConfig = {}) {
    const key = config.apiKey ?? process.env.TINYFISH_API_KEY;
    if (!key) {
      throw new Error(
        "TINYFISH_API_KEY is required. Set it in .env or pass apiKey in config."
      );
    }
    this.apiKey = key;
    this.defaultStealth = config.defaultStealth ?? true;
    this.defaultProxyCountry = config.defaultProxyCountry;
    this.onProgress = config.onProgress;
  }

  /**
   * Run an automation via SSE streaming endpoint.
   * Returns the final result JSON when the automation completes.
   */
  async run<T = unknown>(
    url: string,
    goal: string,
    options?: Partial<Pick<TinyFishOptions, "browser_profile" | "proxy_config">>
  ): Promise<T> {
    const body: TinyFishOptions = {
      url,
      goal,
      browser_profile: options?.browser_profile ??
        (this.defaultStealth ? "stealth" : "default"),
      proxy_config: options?.proxy_config ?? (this.defaultProxyCountry
        ? { enabled: true, country_code: this.defaultProxyCountry as TinyFishOptions["proxy_config"] extends { country_code?: infer C } ? C : never }
        : undefined),
    };

    const response = await fetch(`${TINYFISH_BASE_URL}/run-sse`, {
      method: "POST",
      headers: {
        "X-API-Key": this.apiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });

    if (!response.ok) {
      const text = await response.text().catch(() => "");
      throw new Error(
        `TinyFish API error ${response.status}: ${text || response.statusText}`
      );
    }

    if (!response.body) {
      throw new Error("No response body — SSE streaming not supported");
    }

    return this.parseSSEStream<T>(response.body);
  }

  /**
   * Run an automation via the synchronous endpoint.
   * Simpler but no progress updates — blocks until done.
   */
  async runSync<T = unknown>(
    url: string,
    goal: string,
    options?: Partial<Pick<TinyFishOptions, "browser_profile" | "proxy_config">>
  ): Promise<T> {
    const body: TinyFishOptions = {
      url,
      goal,
      browser_profile: options?.browser_profile ??
        (this.defaultStealth ? "stealth" : "default"),
      proxy_config: options?.proxy_config ?? (this.defaultProxyCountry
        ? { enabled: true, country_code: this.defaultProxyCountry as TinyFishOptions["proxy_config"] extends { country_code?: infer C } ? C : never }
        : undefined),
    };

    const response = await fetch(`${TINYFISH_BASE_URL}/run`, {
      method: "POST",
      headers: {
        "X-API-Key": this.apiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });

    if (!response.ok) {
      const text = await response.text().catch(() => "");
      throw new Error(
        `TinyFish API error ${response.status}: ${text || response.statusText}`
      );
    }

    const result = await response.json();
    if (result.status === "COMPLETED") {
      return (result.resultJson ?? result.result) as T;
    }
    throw new Error(
      result.error?.message ?? `Automation failed with status: ${result.status}`
    );
  }

  /**
   * Run with an async generator that yields progress events,
   * then returns the final result. Useful for UIs and logging.
   */
  async *runWithProgress<T = unknown>(
    url: string,
    goal: string,
    options?: Partial<Pick<TinyFishOptions, "browser_profile" | "proxy_config">>
  ): AsyncGenerator<SSEEvent, T, undefined> {
    const body: TinyFishOptions = {
      url,
      goal,
      browser_profile: options?.browser_profile ??
        (this.defaultStealth ? "stealth" : "default"),
      proxy_config: options?.proxy_config ?? (this.defaultProxyCountry
        ? { enabled: true, country_code: this.defaultProxyCountry as TinyFishOptions["proxy_config"] extends { country_code?: infer C } ? C : never }
        : undefined),
    };

    const response = await fetch(`${TINYFISH_BASE_URL}/run-sse`, {
      method: "POST",
      headers: {
        "X-API-Key": this.apiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });

    if (!response.ok) {
      const text = await response.text().catch(() => "");
      throw new Error(
        `TinyFish API error ${response.status}: ${text || response.statusText}`
      );
    }

    if (!response.body) {
      throw new Error("No response body — SSE streaming not supported");
    }

    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";

    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split("\n");
        buffer = lines.pop() ?? "";

        for (const line of lines) {
          if (!line.startsWith("data: ")) continue;

          let event: SSEEvent;
          try {
            event = JSON.parse(line.slice(6));
          } catch {
            continue;
          }

          if (event.type === "PROGRESS") {
            yield event;
          } else if (event.type === "COMPLETE") {
            const complete = event as SSECompleteEvent;
            if (complete.status === "COMPLETED") {
              return (complete.resultJson ?? complete.result) as T;
            }
            throw new Error(
              complete.error?.message ?? `Automation failed: ${complete.status}`
            );
          }
        }
      }
    } finally {
      reader.releaseLock();
    }

    throw new Error("SSE stream ended without a COMPLETE event");
  }

  // --- Private ---

  private async parseSSEStream<T>(body: ReadableStream<Uint8Array>): Promise<T> {
    const reader = body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";

    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split("\n");
        buffer = lines.pop() ?? "";

        for (const line of lines) {
          if (!line.startsWith("data: ")) continue;

          let event: SSEEvent;
          try {
            event = JSON.parse(line.slice(6));
          } catch {
            continue;
          }

          if (event.type === "PROGRESS") {
            this.onProgress?.(event.purpose);
          } else if (event.type === "COMPLETE") {
            const complete = event as SSECompleteEvent;
            if (complete.status === "COMPLETED") {
              return (complete.resultJson ?? complete.result) as T;
            }
            throw new Error(
              complete.error?.message ?? `Automation failed: ${complete.status}`
            );
          }
        }
      }
    } finally {
      reader.releaseLock();
    }

    throw new Error("SSE stream ended without a COMPLETE event");
  }
}
