/**
 * The one exception to "the helper only connects to public addresses": a
 * website whose own address is on the local network (http://192.168.0.5/)
 * may, once it is allowed, connect back to that one address. Only an IP
 * literal counts, never a name, so no DNS answer can point the exception at
 * another device. The address comes from the browser's sender origin, never
 * from the page, and the helper checks it again.
 */

/** The first helper that knows the exception; an older one refuses the website's own address. */
export const MIN_LAN_HELPER_VERSION = "1.4.0";

const OCTET = "(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])";
/** A dotted quad as the URL parser writes it: four decimal numbers, no leading zeros. */
const IPV4 = new RegExp(`^${OCTET}\\.${OCTET}\\.${OCTET}\\.${OCTET}$`, "u");
/**
 * fc00::/7 as the URL parser writes it: the first group is never zero, so it
 * is never shortened and always has its four digits.
 */
const ULA = /^\[(f[cd][0-9a-f]{2}:[0-9a-f:]*)\]$/u;

/**
 * The private address an origin is served from, as a bare lower-case IP
 * (no brackets, no port): 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 or
 * fc00::/7. Anything else (a host name, this computer, link-local, carrier
 * NAT, IPv4-mapped IPv6, a public address, not http/https) gives undefined.
 */
export function lanHostOf(origin: string): string | undefined {
    let url: URL;
    try {
        url = new URL(origin);
    } catch {
        return undefined;
    }
    if (
        !["http:", "https:"].includes(url.protocol) ||
        url.username ||
        url.password
    ) {
        return undefined;
    }
    // The parser's canonical host: 0xc0a80001 and 3232235521 are 192.168.0.1
    // to the browser as well.
    const host = url.hostname.toLowerCase();
    const v4 = IPV4.exec(host);
    if (v4) {
        const [a, b] = [Number(v4[1]), Number(v4[2])];
        return a === 10 ||
            (a === 172 && b >= 16 && b <= 31) ||
            (a === 192 && b === 168)
            ? host
            : undefined;
    }
    return ULA.exec(host)?.[1];
}

/** Whether a destination host names the address `lan`; brackets and letter case do not matter. */
export function isLanDestination(host: string, lan: string): boolean {
    return host.replace(/^\[(.*)\]$/u, "$1").toLowerCase() === lan;
}

/** Numeric dotted comparison: "1.10.0" is at least "1.4.0". Anything that is not such a version is not. */
export function versionAtLeast(
    version: string | undefined,
    min: string,
): boolean {
    const parse = (value: string | undefined) =>
        value !== undefined &&
        value.length <= 32 &&
        /^[0-9]{1,9}(?:\.[0-9]{1,9})*$/u.test(value)
            ? value.split(".").map(Number)
            : undefined;
    const have = parse(version);
    const want = parse(min);
    if (!have || !want) {
        return false;
    }
    for (let i = 0; i < Math.max(have.length, want.length); i++) {
        const [a, b] = [have[i] ?? 0, want[i] ?? 0];
        if (a !== b) {
            return a > b;
        }
    }
    return true;
}
