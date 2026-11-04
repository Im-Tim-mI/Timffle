//! Security Sandbox implementation, see
//! https://help.adobe.com/en_US/as3/dev/WS5b3ccc516d4fbf351e63e3d118a9b90204-7e3f.html

use swf::HeaderExt;
use url::Url;

/// Type of sandbox that defines what a movie can access
/// and how movies interact with each other.
///
/// Note: sandbox type is defined *per SWF*.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SandboxType {
    /// The movie originates from a remote URL.
    ///
    /// In this case domain-based sandbox rules are used,
    /// no filesystem access.
    Remote,

    /// The movie is a local movie with filesystem access.
    ///
    /// This implies no network access.
    LocalWithFile,

    /// The movie is a local movie with network access.
    ///
    /// This implies no filesystem access.
    LocalWithNetwork,

    /// The movie is a trusted local movie with access to both filesystem and network.
    LocalTrusted,

    /// The movie is an AIR application with access to both filesystem and network.
    Application,
}

impl SandboxType {
    /// Infer sandbox type based on SWF URL and its header.
    ///
    /// When the URL is remote, [`SandboxType::Remote`] is used.
    /// When the URL is local, [`SandboxType::LocalWithFile`] or
    /// [`SandboxType::LocalWithNetwork`] is used depending on
    /// the preference from the header.
    pub fn infer(url: &str, header: &HeaderExt) -> Self {
        match Url::parse(url) {
            Ok(url) => {
                if url.scheme() == "file" {
                    if header.use_network_sandbox() {
                        Self::LocalWithNetwork
                    } else {
                        Self::LocalWithFile
                    }
                } else {
                    Self::Remote
                }
            }
            Err(e) => {
                let sandbox_type = Self::LocalWithFile;
                tracing::warn!("Failed to parse URL {url}: {e}, using {sandbox_type:?}");
                sandbox_type
            }
        }
    }
}

// Timffle: the per-SWF allow lists behind `Security.allowDomain()`,
// `Security.allowInsecureDomain()` and `LocalConnection.allowDomain()` /
// `allowInsecureDomain()`, plus the origin rules they are checked against.

/// The scheme and host Flash uses to decide whether two files are in the
/// same security domain. Local files (`file:` URLs, or URLs that do not
/// parse) are all `localhost`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FlashOrigin {
    pub scheme: String,
    pub host: String,
    pub local: bool,
}

impl FlashOrigin {
    pub fn of(url: &str) -> Self {
        match Url::parse(url) {
            Ok(url) if url.scheme() != "file" && url.host_str().is_some() => Self {
                scheme: url.scheme().to_ascii_lowercase(),
                host: url.host_str().unwrap_or_default().to_ascii_lowercase(),
                local: false,
            },
            _ => Self {
                scheme: "file".to_string(),
                host: "localhost".to_string(),
                local: true,
            },
        }
    }

    pub fn is_https(&self) -> bool {
        self.scheme == "https"
    }
}

/// Whether two files are in the same Flash security domain: the same scheme
/// and the same (exact) host. `http://` and `https://` copies of a host are
/// different domains, as in Flash Player.
pub fn same_security_domain(url_a: &str, url_b: &str) -> bool {
    FlashOrigin::of(url_a) == FlashOrigin::of(url_b)
}

/// Domains granted cross-domain access by `allowDomain()` and
/// `allowInsecureDomain()`.
///
/// Flash keeps the two lists apart: an HTTPS file only trusts non-HTTPS
/// callers through `allowInsecureDomain()`. `*` matches every remote domain
/// (not local files); `localhost` matches local files.
#[derive(Clone, Debug, Default)]
pub struct AllowedDomains {
    domains: Vec<String>,
    insecure_domains: Vec<String>,
}

impl AllowedDomains {
    /// Record one `allowDomain()` (`insecure == false`) or
    /// `allowInsecureDomain()` (`insecure == true`) argument.
    pub fn allow(&mut self, domain: &str, insecure: bool) {
        let domain = domain.to_ascii_lowercase();
        let list = if insecure {
            &mut self.insecure_domains
        } else {
            &mut self.domains
        };
        if !list.contains(&domain) {
            list.push(domain);
        }
    }

    fn list_matches(list: &[String], caller: &FlashOrigin) -> bool {
        list.iter().any(|entry| {
            if caller.local {
                entry == "localhost"
            } else {
                entry == "*" || *entry == caller.host
            }
        })
    }

    /// Whether the file at `caller_url` is on the allow lists of the file at
    /// `owner_url`. Same-domain callers always are. An HTTPS owner admits a
    /// non-HTTPS caller only through `allowInsecureDomain()`.
    pub fn allows(&self, owner_url: &str, caller_url: &str) -> bool {
        let owner = FlashOrigin::of(owner_url);
        let caller = FlashOrigin::of(caller_url);
        if owner == caller {
            return true;
        }
        self.allows_origin(&owner, &caller)
    }

    /// `allows()` for already parsed origins, without the same-domain rule.
    pub fn allows_origin(&self, owner: &FlashOrigin, caller: &FlashOrigin) -> bool {
        if Self::list_matches(&self.insecure_domains, caller) {
            return true;
        }
        if owner.is_https() && !caller.is_https() {
            return false;
        }
        Self::list_matches(&self.domains, caller)
    }
}
