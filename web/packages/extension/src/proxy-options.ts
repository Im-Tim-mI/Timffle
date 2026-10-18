import {
    getProxySettings,
    replaceProxySettings,
    sameProxySettings,
    SettingsConflictError,
} from "./proxy-settings";
import { PROXY_STORAGE_KEY, validateProxySettings } from "./socket-proxy";
import type {
    ProxyMode,
    ProxySettings,
    ProxyValidationError,
} from "./socket-proxy";
import { HELPER_STATUS_REQUEST } from "./socket-bridge-protocol";
import type { HelperStatus } from "./socket-bridge-protocol";

const VALIDATION_MESSAGES: Record<ProxyValidationError, string> = {
    invalid_settings: "設定格式無效。 / Invalid settings format.",
    url_required:
        "使用自訂 WebSocket 代理時，請填寫 URL 範本。 / Enter a URL template to use a custom WebSocket proxy.",
    invalid_url:
        "請使用有效的 ws:// 或 wss:// URL，不含空白、反斜線或未知佔位符。 / Use a valid ws:// or wss:// URL without whitespace, backslashes or unknown placeholders.",
    missing_placeholders:
        "URL 必須同時包含 {host} 和 {port}。 / The URL must include both {host} and {port}.",
    credentials:
        "URL 不可包含使用者名稱或密碼欄位；請使用代理程式提供的 token 查詢參數。 / URL username/password fields are not allowed; use the proxy's token query parameter.",
    fragment:
        "WebSocket URL 不可包含 # 片段。 / WebSocket URLs must not contain a # fragment.",
    dynamic_endpoint:
        "代理伺服器位址必須固定；{host} 和 {port} 僅可放在路徑或查詢參數。 / Keep the proxy endpoint fixed; placeholders belong only in the path or query.",
    invalid_origin:
        "每行只能填寫一個完整 HTTP/HTTPS 來源（協定、主機、選用連接埠），不可含路徑、帳密、查詢或萬用字元。 / Enter one exact HTTP/HTTPS origin per line, without paths, credentials, queries or wildcards.",
    origins_required:
        "使用自訂 WebSocket 代理時，請至少指定一個一律允許的網站來源。 / With a custom WebSocket proxy, allow at least one website origin.",
};

const CONFLICT_MESSAGE =
    "同一個網站不能同時在「一律允許」與「一律拒絕」清單中。 / A website cannot be on both the always-allowed and the always-denied list.";

const CHANGED_ELSEWHERE_MESSAGE =
    "設定已在別處變更（例如彈出視窗或詢問視窗），這次的修改沒有儲存。已改為顯示最新設定，請再改一次。 / The settings were changed elsewhere (for example in the popup or a question window), so your edit was not saved. The latest settings are shown; please edit again.";

const UPDATED_ELSEWHERE_MESSAGE =
    "設定已在別處變更（例如彈出視窗），已顯示最新設定。 / The settings were changed elsewhere (for example in the popup); the latest settings are shown.";

const STALE_MESSAGE =
    "設定已在別處變更（例如彈出視窗）。你的修改尚未儲存；儲存時會改為顯示最新設定，不會覆蓋那邊的變更。 / The settings were changed elsewhere (for example in the popup). Your edit is not saved yet; saving will show the latest settings instead of overwriting that change.";

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
            settings.enabled
                ? "已儲存並啟用：清單內的網站直接使用，其他網站會先詢問你。請重新載入網頁；此狀態不代表已連線。 / Saved and enabled: listed websites use sockets directly, other websites are asked first. Reload the page; this is not a connection test."
                : "Socket 連線已停用。變更後請重新載入網頁。 / Sockets disabled. Reload the page after changes.",
        );
    }

    async function checkHelper() {
        helperCheck.disabled = true;
        helperStatus.textContent = "檢查中… / Checking…";
        helperStatus.dataset["state"] = "info";
        const result = await queryHelper();
        if (result.installed) {
            const version = result.version ?? "?";
            helperStatus.textContent = `已安裝（版本 ${version}） / Installed (version ${version})`;
            helperStatus.dataset["state"] = "info";
        } else {
            helperStatus.textContent =
                result.error === "helper_incompatible"
                    ? "版本不相容：請使用同一下載包的插件與連線小幫手，重新安裝小幫手後再檢查。 / Incompatible version: install the helper matching this extension."
                    : result.error === "helper_missing"
                      ? "尚未安裝：請執行下載包 helper 資料夾裡對應系統的安裝檔，完成後按「重新檢查」。 / Not installed: run the installer for your system in the download's helper folder, then check again."
                      : "無法啟動或回應逾時：請確認安裝是否完成，並查看作業系統的安全提示後再檢查。 / Helper unavailable: check installation and operating-system security prompts, then retry.";
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
        setStatus("無法讀取本機設定。 / Could not read local settings.", true);
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
                setStatus(STALE_MESSAGE, true);
            } else {
                baseline = latest;
                displaySettings(latest);
                setStatus(UPDATED_ELSEWHERE_MESSAGE);
            }
        })();
    });

    form.addEventListener("change", () => {
        showMode();
        dirty = true;
    });
    form.addEventListener("input", () => {
        dirty = true;
        setStatus("尚未儲存。 / Unsaved changes.");
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
            setStatus(VALIDATION_MESSAGES[result.error], true);
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
            setStatus(CONFLICT_MESSAGE, true);
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
                    setStatus(CHANGED_ELSEWHERE_MESSAGE, true);
                } catch {
                    setStatus(
                        "無法讀取本機設定。 / Could not read local settings.",
                        true,
                    );
                }
            } else {
                // Browser errors can include input; never display or log the URL/token.
                setStatus(
                    "儲存失敗；原有設定未確認變更，請重試。 / Save failed; changes were not confirmed. Please retry.",
                    true,
                );
            }
        } finally {
            save.disabled = false;
        }
    });
}
