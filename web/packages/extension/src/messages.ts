import type { Config } from "ruffle-core";

export interface LoadMessage {
    type: "load";
    config: Config.BaseLoadOptions;
    publicPath: string;
}

export interface PingMessage {
    type: "ping";
}

export interface OpenURLMessage {
    type: "open_url_in_player";
    url: string;
}

/** Timffle: settings that the running players apply at once. */
export interface SettingsMessage {
    type: "settings";
    showFps: boolean;
}

/**
 * Timffle: the page asks whether a movie may read `origin` (the host's
 * crossdomain.xml allows the page), see crossdomain.ts.
 */
export interface CrossDomainMessage {
    type: "cross_domain";
    origin: string;
    seq: number;
}

export interface CrossDomainResultMessage {
    type: "cross_domain_result";
    seq: number;
    allowed: boolean;
}

export type Message =
    | LoadMessage
    | PingMessage
    | OpenURLMessage
    | SettingsMessage
    | CrossDomainMessage
    | CrossDomainResultMessage;

export function isMessage(object: unknown): object is Message {
    return (object as Message).type !== undefined;
}
