import {
    getProxySettings,
    replaceProxySettings,
    sameProxySettings,
    SettingsConflictError,
} from "./proxy-settings";
import { text } from "./i18n";
import { PROXY_STORAGE_KEY, validateProxySettings } from "./socket-proxy";
import type {
    ProxyMode,
    ProxySettings,
    ProxyValidationError,
} from "./socket-proxy";
import { HELPER_STATUS_REQUEST } from "./socket-bridge-protocol";
import type { HelperStatus } from "./socket-bridge-protocol";

const VALIDATION_KEYS: Record<ProxyValidationError, string> = {
    invalid_settings: "timffle_error_invalid_settings",
    url_required: "timffle_error_url_required",
    invalid_url: "timffle_error_invalid_url",
    missing_placeholders: "timffle_error_missing_placeholders",
    credentials: "timffle_error_credentials",
    fragment: "timffle_error_fragment",
    dynamic_endpoint: "timffle_error_dynamic_endpoint",
    invalid_origin: "timffle_error_invalid_origin",
    origins_required: "timffle_error_origins_required",
};

async function queryHelper(): Promise<HelperStatus> {
    try {
        const status = (await browser.runtime.sendMessage({
            type: HELPER_STATUS_REQUEST,
        })) as HelperStatus | undefined;
        return status ?? { installed: false, error: "no_response" };
    } catch {
        return { installed: false, error: "no_response" };
    }
}

export async function bindProxyOptions(): Promise<void> {
    // A web page can frame an extension page unless the browser refuses it,
    // and could cover this form to have somebody type into it. Framed, this
    // page must not offer anything to edit.
    if (window.top !== window) {
        document.body.replaceChildren();
        return;
    }
    const form = document.getElementById(
        "socket-proxy-form",
    )! as HTMLFormElement;
    const enabled = document.getElementById(
        "socket-proxy-enabled",
    )! as HTMLInputElement;
    const helperMode = document.getElementById(
        "socket-proxy-mode-helper",
    )! as HTMLInputElement;
    const websocketMode = document.getElementById(
        "socket-proxy-mode-websocket",
    )! as HTMLInputElement;
    const websocketFields = document.getElementById(
        "socket-proxy-websocket-fields",
    )!;
    const proxyUrl = document.getElementById(
        "socket-proxy-url",
    )! as HTMLInputElement;
    const origins = document.getElementById(
        "socket-proxy-origins",
    )! as HTMLTextAreaElement;
    const denied = document.getElementById(
        "socket-proxy-denied",
    )! as HTMLTextAreaElement;
    const save = document.getElementById(
        "socket-proxy-save",
    )! as HTMLButtonElement;
    const status = document.getElementById("socket-proxy-status")!;
    const helperStatus = document.getElementById("socket-helper-status")!;
    const helperCheck = document.getElementById(
        "socket-helper-check",
    )! as HTMLButtonElement;

    const modeTexts =
        document.querySelectorAll<HTMLElement>("[data-mode-text]");

    /** The settings as last read from or saved to storage: what the form was made from. */
    let baseline: ProxySettings | undefined;
    /** The form has edits that are not saved. */
    let dirty = false;
    /**
     * Each connection method has its own list of allowed websites; the one box
     * shows the list of the selected method, and the other is kept here.
     */
    const lists: Record<ProxyMode, string> = { helper: "", websocket: "" };
    let shown: ProxyMode = "helper";

    function setStatus(message: string, error = false) {
        status.textContent = message;
        status.dataset["state"] = error ? "error" : "info";
    }

    function selectedMode(): ProxyMode {
        return websocketMode.checked ? "websocket" : "helper";
    }

    function showMode() {
        const mode = selectedMode();
        if (mode !== shown) {
            lists[shown] = origins.value;
            shown = mode;
            origins.value = lists[mode];
        }
        websocketFields.hidden = mode !== "websocket";
        for (const node of modeTexts) {
            node.hidden = node.dataset["modeText"] !== mode;
        }
    }

    function displaySettings(settings: ProxySettings) {
        enabled.checked = settings.enabled;
        helperMode.checked = settings.mode === "helper";
        websocketMode.checked = settings.mode === "websocket";
        proxyUrl.value = settings.proxyUrl;
        lists.helper = settings.allowedOrigins.join("\n");
        lists.websocket = settings.proxyOrigins.join("\n");
        shown = settings.mode;
        origins.value = lists[shown];
        denied.value = settings.deniedOrigins.join("\n");
        dirty = false;
        showMode();
    }

    function savedStatus(settings: ProxySettings) {
        setStatus(
            text(
                settings.enabled
                    ? "timffle_saved_enabled"
                    : "timffle_saved_disabled",
            ),
        );
    }

    async function checkHelper() {
        helperCheck.disabled = true;
        helperStatus.textContent = text("timffle_helper_checking");
        helperStatus.dataset["state"] = "info";
        const result = await queryHelper();
        if (result.installed) {
            const version = result.version ?? "?";
            helperStatus.textContent = text("timffle_helper_installed", [
                version,
            ]);
            helperStatus.dataset["state"] = "info";
        } else {
            helperStatus.textContent = text(
                result.error === "helper_incompatible"
                    ? "timffle_helper_incompatible"
                    : result.error === "helper_missing"
                      ? "timffle_helper_missing"
                      : "timffle_helper_unavailable",
            );
            helperStatus.dataset["state"] = "error";
        }
        helperCheck.disabled = false;
    }

    save.disabled = true;
    try {
        baseline = await getProxySettings();
        displaySettings(baseline);
        savedStatus(baseline);
        save.disabled = false;
    } catch {
        // Saving without knowing what is stored could overwrite it.
        setStatus(text("timffle_read_failed"), true);
    }

    helperCheck.addEventListener("click", () => void checkHelper());
    void checkHelper();

    // The popup and the question windows change the same settings while this
    // page is open. A form that has no edits follows them; one that has is
    // left alone, and refuses to save over them (see the submit handler).
    browser.storage.onChanged.addListener((changes, area) => {
        if (area !== "local" || !(PROXY_STORAGE_KEY in changes)) {
            return;
        }
        void (async () => {
            let latest: ProxySettings;
            try {
                latest = await getProxySettings();
            } catch {
                return;
            }
            if (!baseline || sameProxySettings(latest, baseline)) {
                // Our own save, or a change that is no change.
                return;
            }
            if (dirty) {
                setStatus(text("timffle_stale"), true);
            } else {
                baseline = latest;
                displaySettings(latest);
                setStatus(text("timffle_updated_elsewhere"));
            }
        })();
    });

    form.addEventListener("change", () => {
        showMode();
        dirty = true;
    });
    form.addEventListener("input", () => {
        dirty = true;
        setStatus(text("timffle_unsaved"));
    });
    form.addEventListener("submit", async (event) => {
        event.preventDefault();
        if (!baseline) {
            return;
        }
        lists[shown] = origins.value;
        const allowedLines = lists.helper.split(/\r?\n/u);
        const proxyLines = lists.websocket.split(/\r?\n/u);
        const deniedLines = denied.value.split(/\r?\n/u);
        const result = validateProxySettings({
            enabled: enabled.checked,
            mode: selectedMode(),
            proxyUrl: proxyUrl.value,
            allowedOrigins: allowedLines,
            proxyOrigins: proxyLines,
            deniedOrigins: deniedLines,
        });
        if (!result.valid) {
            setStatus(text(VALIDATION_KEYS[result.error]), true);
            return;
        }
        // Validation lets "refuse" win quietly; the person typing should be told.
        const typedAllowed = validateProxySettings({
            enabled: false,
            mode: "helper",
            proxyUrl: "",
            allowedOrigins: allowedLines,
            proxyOrigins: proxyLines,
        });
        if (
            typedAllowed.valid &&
            [
                ...typedAllowed.settings.allowedOrigins,
                ...typedAllowed.settings.proxyOrigins,
            ].some((origin) => result.settings.deniedOrigins.includes(origin))
        ) {
            setStatus(text("timffle_conflict"), true);
            return;
        }
        save.disabled = true;
        try {
            // Only if nobody changed the settings since this form was made
            // from them; otherwise the old view of the lists would silently
            // undo what was decided elsewhere (e.g. "always deny").
            baseline = await replaceProxySettings(baseline, result.settings);
            displaySettings(baseline);
            savedStatus(baseline);
        } catch (error) {
            if (error instanceof SettingsConflictError) {
                try {
                    baseline = await getProxySettings();
                    displaySettings(baseline);
                    setStatus(text("timffle_changed_elsewhere"), true);
                } catch {
                    setStatus(text("timffle_read_failed"), true);
                }
            } else {
                // Browser errors can include input; never display or log the URL/token.
                setStatus(text("timffle_save_failed"), true);
            }
        } finally {
            save.disabled = false;
        }
    });
}
