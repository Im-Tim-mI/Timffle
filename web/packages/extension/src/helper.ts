/**
 * The install page: why the socket helper is needed, which installer to run
 * on which system, and whether the extension finds the helper yet.
 */
import { enableBrowserOnOutdatedChromium, setPageLanguage } from "./utils";
import { localizePage, text } from "./i18n";
import { helperVerdict, queryHelper, statusMessage } from "./helper-status";

window.addEventListener("DOMContentLoaded", () => {
    // A web page can frame an extension page unless the browser refuses it;
    // there is nothing to offer inside a frame.
    if (window.top !== window) {
        document.body.replaceChildren();
        return;
    }
    enableBrowserOnOutdatedChromium();
    setPageLanguage();
    localizePage();
    document.title = text("timffle_helper_page_title");

    const status = document.getElementById("helper-page-status")!;
    const check = document.getElementById(
        "helper-page-check",
    ) as HTMLButtonElement;
    let checking = false;

    async function run() {
        if (checking) {
            return;
        }
        checking = true;
        check.disabled = true;
        status.textContent = text("timffle_helper_checking");
        status.dataset["state"] = "info";
        const verdict = helperVerdict(await queryHelper());
        status.textContent = statusMessage(verdict);
        status.dataset["state"] =
            verdict.kind === "installed" ? "info" : "error";
        check.disabled = false;
        checking = false;
    }

    check.addEventListener("click", () => void run());
    // Coming back to this tab after running the installer: look again.
    document.addEventListener("visibilitychange", () => {
        if (document.visibilityState === "visible") {
            void run();
        }
    });
    void run();
});
