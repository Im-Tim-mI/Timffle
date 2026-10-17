import { getProxySettings, saveProxySettings } from "./proxy-settings";
import { validateProxySettings } from "./socket-proxy";
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
        "啟用前請至少指定一個信任的網站來源。 / Explicitly allow at least one trusted website origin before enabling.",
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
    const save = document.getElementById(
        "socket-proxy-save",
    )! as HTMLButtonElement;
    const status = document.getElementById("socket-proxy-status")!;
    const helperStatus = document.getElementById("socket-helper-status")!;
    const helperCheck = document.getElementById(
        "socket-helper-check",
    )! as HTMLButtonElement;

    function setStatus(message: string, error = false) {
        status.textContent = message;
        status.dataset["state"] = error ? "error" : "info";
    }

    function selectedMode(): ProxyMode {
        return websocketMode.checked ? "websocket" : "helper";
    }

    function showMode() {
        websocketFields.hidden = selectedMode() !== "websocket";
    }

    function displaySettings(settings: ProxySettings) {
        enabled.checked = settings.enabled;
        helperMode.checked = settings.mode === "helper";
        websocketMode.checked = settings.mode === "websocket";
        proxyUrl.value = settings.proxyUrl;
        origins.value = settings.allowedOrigins.join("\n");
        showMode();
    }

    function savedStatus(settings: ProxySettings) {
        setStatus(
            settings.enabled
                ? "已儲存並啟用，僅限允許的來源。請重新載入網頁；此狀態不代表已連線。 / Saved and enabled for allowed origins only. Reload the page; this is not a connection test."
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
        const settings = await getProxySettings();
        displaySettings(settings);
        savedStatus(settings);
    } catch {
        setStatus("無法讀取本機設定。 / Could not read local settings.", true);
    } finally {
        save.disabled = false;
    }

    helperCheck.addEventListener("click", () => void checkHelper());
    void checkHelper();

    form.addEventListener("change", showMode);
    form.addEventListener("input", () => {
        setStatus("尚未儲存。 / Unsaved changes.");
    });
    form.addEventListener("submit", async (event) => {
        event.preventDefault();
        const result = validateProxySettings({
            enabled: enabled.checked,
            mode: selectedMode(),
            proxyUrl: proxyUrl.value,
            allowedOrigins: origins.value.split(/\r?\n/u),
        });
        if (!result.valid) {
            setStatus(VALIDATION_MESSAGES[result.error], true);
            return;
        }
        save.disabled = true;
        try {
            await saveProxySettings(result.settings);
            displaySettings(result.settings);
            savedStatus(result.settings);
        } catch {
            // Browser errors can include input; never display or log the URL/token.
            setStatus(
                "儲存失敗；原有設定未確認變更，請重試。 / Save failed; changes were not confirmed. Please retry.",
                true,
            );
        } finally {
            save.disabled = false;
        }
    });
}
