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
    frameInterpolation: string;
    showFps: boolean;
}

export type Message =
    | LoadMessage
    | PingMessage
    | OpenURLMessage
    | SettingsMessage;

export function isMessage(object: unknown): object is Message {
    return (object as Message).type !== undefined;
}
