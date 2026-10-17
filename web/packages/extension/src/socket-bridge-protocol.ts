/** Shared, bounded messages for page <-> content <-> background <-> helper. */
export const SOCKET_PORT_NAME = "ruffle-socket";
export const NATIVE_HOST_NAME = "ruffle_socket_helper";
export const HELPER_STATUS_REQUEST = "socket_helper_status";
export const HELPER_VERSION = "1.1.0";
export const HELPER_PROTOCOL = 2;
export const MAX_SEND_BYTES = 65536;
export const MAX_RECEIVE_BYTES = 32768;
export const MAX_BUFFERED_BYTES = 1024 * 1024;
export const MAX_QUEUED_SENDS = 1024;
export const MAX_GLOBAL_SOCKETS = 16;
// A game frame may hold login + game + chat sockets while an old one is still
// draining or a reconnect is in progress; each layer also frees slots slightly later.
export const MAX_FRAME_SOCKETS = 8;
export const STALL_TIMEOUT_MS = 30000;
// Includes native host process start-up (e.g. a first antivirus scan on Windows).
export const HELLO_TIMEOUT_MS = 10000;

export interface HelperStatus {
    installed: boolean;
    version?: string;
    protocol?: number;
    error?: string;
}

export type PageRequest =
    | { op: "open"; sid: number; host: string; port: number }
    | { op: "send"; sid: number; data: ArrayBuffer }
    | { op: "ack" | "close"; sid: number };

export type PageEvent =
    | { op: "opened" | "sent" | "closed"; sid: number }
    | { op: "data"; sid: number; data: ArrayBuffer }
    | { op: "error"; sid: number; code: string };

export interface OpenRequest {
    type: "open";
    host: string;
    port: number;
}

export interface SendRequest {
    type: "send";
    data: string;
}

export type HelperReply =
    | { type: "hello"; version: string; protocol: number }
    | { type: "opened" | "sent" | "closed" }
    | { type: "data"; data: string }
    | { type: "error"; code: string };

export function isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === "object" && value !== null;
}

export function isSocketId(value: unknown): value is number {
    return Number.isSafeInteger(value) && (value as number) > 0;
}

/** Shape check only; the helper applies its public-address destination policy. */
export function isValidHost(value: unknown): value is string {
    return (
        typeof value === "string" &&
        value.length > 0 &&
        value.length <= 255 &&
        // eslint-disable-next-line no-control-regex
        !/[\s\u0000-\u001f\u007f/\\?#@%]/u.test(value)
    );
}

export function isValidPort(value: unknown): value is number {
    return (
        Number.isInteger(value) &&
        (value as number) >= 1 &&
        (value as number) <= 65535
    );
}

/** Canonical RFC 4648 base64 only, with a limit on decoded bytes before allocation. */
function isBase64(value: unknown, maxBytes: number): value is string {
    if (
        typeof value !== "string" ||
        value.length > 4 * Math.ceil(maxBytes / 3) ||
        value.length % 4 !== 0
    ) {
        return false;
    }
    const padding = value.endsWith("==") ? 2 : value.endsWith("=") ? 1 : 0;
    return (
        (value.length / 4) * 3 - padding <= maxBytes &&
        /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/][AQgw]==|[A-Za-z0-9+/]{2}[AEIMQUYcgkosw048]=)?$/u.test(
            value,
        )
    );
}

export function isOpenRequest(value: unknown): value is OpenRequest {
    return (
        isRecord(value) &&
        value["type"] === "open" &&
        isValidHost(value["host"]) &&
        isValidPort(value["port"])
    );
}

export function isSendRequest(value: unknown): value is SendRequest {
    return (
        isRecord(value) &&
        value["type"] === "send" &&
        isBase64(value["data"], MAX_SEND_BYTES)
    );
}

export function isHelperReply(value: unknown): value is HelperReply {
    if (!isRecord(value)) {
        return false;
    }
    switch (value["type"]) {
        case "hello":
            return (
                typeof value["version"] === "string" &&
                /^[0-9]+\.[0-9]+\.[0-9]+$/u.test(value["version"]) &&
                value["version"].length <= 32 &&
                Number.isSafeInteger(value["protocol"])
            );
        case "opened":
        case "sent":
        case "closed":
            return true;
        case "data":
            return isBase64(value["data"], MAX_RECEIVE_BYTES);
        case "error":
            return (
                typeof value["code"] === "string" &&
                /^[a-z_]{1,32}$/u.test(value["code"])
            );
        default:
            return false;
    }
}

/** The protocol number is the contract; a helper bug-fix release keeps working. */
export function isCompatibleHello(reply: HelperReply): boolean {
    return reply.type === "hello" && reply.protocol === HELPER_PROTOCOL;
}

export function isPageRequest(value: unknown): value is PageRequest {
    if (!isRecord(value) || !isSocketId(value["sid"])) {
        return false;
    }
    switch (value["op"]) {
        case "open":
            return isValidHost(value["host"]) && isValidPort(value["port"]);
        case "send":
            return (
                value["data"] instanceof ArrayBuffer &&
                value["data"].byteLength <= MAX_SEND_BYTES
            );
        case "ack":
        case "close":
            return true;
        default:
            return false;
    }
}

export function isPageEvent(value: unknown): value is PageEvent {
    if (!isRecord(value) || !isSocketId(value["sid"])) {
        return false;
    }
    switch (value["op"]) {
        case "opened":
        case "sent":
        case "closed":
            return true;
        case "data":
            return (
                value["data"] instanceof ArrayBuffer &&
                value["data"].byteLength <= MAX_RECEIVE_BYTES
            );
        case "error":
            return (
                typeof value["code"] === "string" &&
                /^[a-z_]{1,32}$/u.test(value["code"])
            );
        default:
            return false;
    }
}

export function bytesToBase64(bytes: Uint8Array): string {
    let binary = "";
    for (let i = 0; i < bytes.length; i += 0x8000) {
        binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
    }
    return btoa(binary);
}

export function base64ToBytes(base64: string): Uint8Array<ArrayBuffer> {
    const binary = atob(base64);
    return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}
