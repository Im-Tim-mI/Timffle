/**
 * The socket helper's installers: one file for each system, published in a
 * release of Timffle's download repository on GitHub; which of them belongs to
 * the user's system (worked out before anything is clicked); and how the
 * download is started.
 *
 * The extension only asks the browser to download the file, which the user
 * then runs themselves: it does not fetch, check, unpack or run anything, and
 * needs no permission for that (a tab opened on a file that the server marks as
 * an attachment becomes a download and closes by itself).
 */
import { text } from "./i18n";

/** The repository whose releases hold nothing but the helper's installers. */
export const HELPER_REPOSITORY = "https://github.com/Im-Tim-mI/Timffle-Helper";

/**
 * The release the installers are taken from: the helper's own version
 * (`const version` in timffle/helper/main.go). It is pinned, not "latest", so
 * that this extension installs the helper it was made for even after a newer,
 * different helper is published for newer extensions.
 */
export const HELPER_RELEASE = "v1.4.0";

export type HelperFamily = "windows" | "macos" | "linux";

export interface HelperInstaller {
    id: string;
    family: HelperFamily;
    /** The system as people name it. Product and processor names read the same in every language. */
    label: string;
    /** The name of the file in the release (and of the file the user gets). */
    file: string;
}

/** Same names as timffle/helper/package-installers.py writes; a test compares the two. */
export const HELPER_INSTALLERS: readonly HelperInstaller[] = [
    {
        id: "windows-x64",
        family: "windows",
        label: "Windows 64-bit",
        file: "timffle-helper-windows-x64.exe",
    },
    {
        id: "windows-arm64",
        family: "windows",
        label: "Windows ARM64",
        file: "timffle-helper-windows-arm64.exe",
    },
    {
        id: "windows-x86",
        family: "windows",
        label: "Windows 32-bit",
        file: "timffle-helper-windows-x86.exe",
    },
    {
        id: "macos-arm64",
        family: "macos",
        label: "macOS Apple silicon",
        file: "timffle-helper-macos-arm64.zip",
    },
    {
        id: "macos-x64",
        family: "macos",
        label: "macOS Intel",
        file: "timffle-helper-macos-x64.zip",
    },
    {
        id: "linux-x64",
        family: "linux",
        label: "Linux x64",
        file: "timffle-helper-linux-x64.tar.gz",
    },
    {
        id: "linux-arm64",
        family: "linux",
        label: "Linux ARM64",
        file: "timffle-helper-linux-arm64.tar.gz",
    },
];

/** Where one installer is downloaded from. */
export function installerUrl(installer: HelperInstaller): string {
    return `${HELPER_REPOSITORY}/releases/download/${HELPER_RELEASE}/${installer.file}`;
}

/** The release page, which lists every file. */
export const HELPER_RELEASES_URL = `${HELPER_REPOSITORY}/releases/tag/${HELPER_RELEASE}`;

/** What to type in a terminal to unpack and run a Linux download that sits in the current folder. */
export function linuxCommand(installer: HelperInstaller): string {
    const program = installer.file.replace(/\.tar\.gz$/u, "");
    return `tar xzf ${installer.file} && ./${program}`;
}

/** What the browser tells about the system; every field can be missing. */
export interface SystemHints {
    /** `navigator.userAgentData.platform`: "Windows", "macOS", "Linux", "Chrome OS", "Android", ... */
    platform?: string | undefined;
    /** The processor family: "x86" (Intel, AMD) or "arm". */
    architecture?: string | undefined;
    /** "64" or "32": of the processor, not of the browser. */
    bitness?: string | undefined;
    /** The `User-Agent` text, which tells less and less but is all that some browsers have. */
    userAgent?: string | undefined;
}

function familyOf(hints: SystemHints): HelperFamily | undefined {
    const agent = hints.userAgent ?? "";
    // These run Chrome but cannot run the helper (no native programs for extensions).
    if (/\b(?:Android|CrOS)\b/u.test(agent)) {
        return undefined;
    }
    const platform = (hints.platform ?? "").toLowerCase();
    if (platform !== "") {
        if (platform.startsWith("windows")) {
            return "windows";
        }
        if (platform === "macos") {
            return "macos";
        }
        return platform === "linux" ? "linux" : undefined;
    }
    if (/\bWindows NT\b/u.test(agent)) {
        return "windows";
    }
    if (/\b(?:iPhone|iPad|iPod)\b/u.test(agent)) {
        return undefined;
    }
    if (/\bMacintosh\b/u.test(agent)) {
        return "macos";
    }
    return /\bLinux\b/u.test(agent) ? "linux" : undefined;
}

/** The processor the hints name: "x86" or "arm", and whether it is a 64-bit one. */
function processorOf(hints: SystemHints): {
    kind: "x86" | "arm" | undefined;
    bits: 32 | 64 | undefined;
} {
    const agent = hints.userAgent ?? "";
    const architecture = (hints.architecture ?? "").toLowerCase();
    let kind: "x86" | "arm" | undefined;
    if (architecture === "x86" || architecture === "arm") {
        kind = architecture;
    } else if (/\b(?:ARM64|aarch64|arm64)\b/u.test(agent)) {
        kind = "arm";
    } else if (/\b(?:Win64|WOW64|x64|x86_64|amd64|AMD64)\b/u.test(agent)) {
        kind = "x86";
    }
    let bits: 32 | 64 | undefined;
    if (hints.bitness === "64" || hints.bitness === "32") {
        bits = hints.bitness === "64" ? 64 : 32;
    } else if (
        /\b(?:ARM64|aarch64|arm64|Win64|WOW64|x64|x86_64|amd64|AMD64)\b/u.test(
            agent,
        )
    ) {
        bits = 64;
    }
    return { kind, bits };
}

/**
 * The installer that belongs to a system, or nothing when there is none for it
 * (a system the helper does not run on, or one the browser did not describe
 * well enough to tell Apple silicon from Intel).
 */
export function chooseInstaller(
    hints: SystemHints,
): HelperInstaller | undefined {
    const family = familyOf(hints);
    if (family === undefined) {
        return undefined;
    }
    const { kind, bits } = processorOf(hints);
    let id: string | undefined;
    switch (family) {
        case "windows":
            if (kind === "arm") {
                id = bits === 64 ? "windows-arm64" : undefined;
            } else if (kind === "x86") {
                id = bits === 32 ? "windows-x86" : "windows-x64";
            } else if (
                // A User-Agent from a 32-bit Windows says neither Win64 nor WOW64.
                bits === undefined &&
                /\bWindows NT\b/u.test(hints.userAgent ?? "")
            ) {
                id = "windows-x86";
            }
            break;
        case "macos":
            // The processor's own word decides: a browser's User-Agent says Intel on Apple silicon too.
            id =
                kind === "arm"
                    ? "macos-arm64"
                    : kind === "x86"
                      ? "macos-x64"
                      : undefined;
            break;
        case "linux":
            if (bits === 64) {
                id =
                    kind === "arm"
                        ? "linux-arm64"
                        : kind === "x86"
                          ? "linux-x64"
                          : undefined;
            }
            break;
    }
    return HELPER_INSTALLERS.find((installer) => installer.id === id);
}

interface NavigatorWithBrandData {
    userAgent?: string;
    userAgentData?: {
        platform?: string;
        getHighEntropyValues?: (hints: string[]) => Promise<{
            architecture?: string;
            bitness?: string;
            platform?: string;
        }>;
    };
}

/** What the browser says about the system it runs on. */
export async function readSystemHints(
    nav: NavigatorWithBrandData = navigator as NavigatorWithBrandData,
): Promise<SystemHints> {
    const data = nav.userAgentData;
    let detail: { architecture?: string; bitness?: string; platform?: string } =
        {};
    if (data && typeof data.getHighEntropyValues === "function") {
        try {
            detail = await data.getHighEntropyValues([
                "architecture",
                "bitness",
                "platform",
            ]);
        } catch {
            /* Refused or unsupported: the low-entropy fields below still say something. */
        }
    }
    return {
        platform: detail.platform ?? data?.platform,
        architecture: detail.architecture,
        bitness: detail.bitness,
        userAgent: nav.userAgent,
    };
}

/** The installer for this computer, decided from what the browser reports. */
export async function detectInstaller(
    nav?: NavigatorWithBrandData,
): Promise<HelperInstaller | undefined> {
    try {
        return chooseInstaller(await readSystemHints(nav));
    } catch {
        return undefined;
    }
}

/**
 * Starts the download: a tab of its own opens on the file's address. GitHub
 * answers that with the file as an attachment, so the browser saves it, shows
 * its download notice and closes the tab again.
 */
export async function startHelperDownload(
    installer: HelperInstaller,
    createTab: (properties: {
        url: string;
        active: boolean;
    }) => Promise<unknown> = (properties) => browser.tabs.create(properties),
): Promise<void> {
    await createTab({ url: installerUrl(installer), active: false });
}

export interface HelperDownloadControls {
    /** The button that downloads. */
    button: HTMLElement;
    /** Names the installer the button gets ("For Windows 64-bit"); stays hidden when the system is unknown. */
    label: HTMLElement;
    /** Called after the browser was asked for the download. */
    started: (installer: HelperInstaller) => void;
    /** Whether this click counts (a window that can pop up under the visitor's fingers ignores the first moments). */
    accepts?: (event: MouseEvent) => boolean;
    /** Replaceable for tests. */
    detect?: () => Promise<HelperInstaller | undefined>;
    download?: (installer: HelperInstaller) => Promise<void>;
    now?: () => number;
}

/** A second click this soon after the last is the same click twice. */
const DOUBLE_CLICK_MS = 2000;

/**
 * Finds out which installer belongs to this computer, says so next to the
 * button and makes a real click on the button start that download. Returns the
 * installer, or nothing when the system is not known (the button then does
 * nothing and the caller should not offer it).
 */
export async function bindHelperDownload({
    button,
    label,
    started,
    accepts = () => true,
    detect = () => detectInstaller(),
    download = (installer) => startHelperDownload(installer),
    now = () => Date.now(),
}: HelperDownloadControls): Promise<HelperInstaller | undefined> {
    const installer = await detect();
    if (installer === undefined) {
        return undefined;
    }
    label.textContent = text("timffle_helper_download_for", [installer.label]);
    label.hidden = false;
    let last = -Infinity;
    button.addEventListener("click", (event) => {
        // Only a person's click: a web page cannot script the popup, but a script click is still not a decision.
        if (
            !event.isTrusted ||
            !accepts(event) ||
            now() - last < DOUBLE_CLICK_MS
        ) {
            return;
        }
        last = now();
        download(installer).then(
            () => started(installer),
            () => {
                // The browser refused to open the tab: nothing started, so allow another try at once.
                last = -Infinity;
            },
        );
    });
    return installer;
}
