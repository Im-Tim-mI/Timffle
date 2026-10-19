/**
 * The install page: why the socket helper is needed, the installer for each
 * system (the one for this computer marked), how to run it, and whether the
 * extension finds the helper yet.
 */
import { enableBrowserOnOutdatedChromium, setPageLanguage } from "./utils";
import { fillRich, localizePage, text } from "./i18n";
import { helperVerdict, queryHelper, statusMessage } from "./helper-status";
import {
    detectInstaller,
    HELPER_INSTALLERS,
    HELPER_RELEASES_URL,
    installerUrl,
    linuxCommand,
} from "./helper-download";

/** One download link per installer, under the system it belongs to. */
function listInstallers(detected: string | undefined) {
    for (const installer of HELPER_INSTALLERS) {
        const list = document.querySelector(
            `.helper-systems [data-family="${installer.family}"] .helper-files`,
        );
        if (!list) {
            continue;
        }
        const link = document.createElement("a");
        link.href = installerUrl(installer);
        // A tab of its own: the file is saved and the tab closes, and this page stays.
        link.target = "_blank";
        link.rel = "noopener noreferrer";
        link.textContent = installer.label;
        link.dataset["installer"] = installer.id;
        if (installer.id === detected) {
            link.setAttribute("aria-current", "true");
            link.classList.add("helper-yours");
        }
        const file = document.createElement("code");
        file.dir = "ltr";
        file.translate = false;
        file.textContent = installer.file;
        const item = document.createElement("li");
        item.append(link, " ", file);
        // The one for this computer first.
        if (installer.id === detected) {
            list.prepend(item);
        } else {
            list.append(item);
        }
    }
}

window.addEventListener("DOMContentLoaded", async () => {
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

    const releases = document.getElementById(
        "helper-releases",
    ) as HTMLAnchorElement;
    releases.href = HELPER_RELEASES_URL;

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

    const detected = await detectInstaller();
    listInstallers(detected?.id);
    // The command for a Linux download names the file, which depends on the processor.
    const linuxInstaller =
        detected?.family === "linux"
            ? detected
            : HELPER_INSTALLERS.find(({ id }) => id === "linux-x64")!;
    fillRich(
        document.getElementById("helper-step-linux")!,
        text("timffle_helper_step_linux", [linuxCommand(linuxInstaller)]),
    );
});
