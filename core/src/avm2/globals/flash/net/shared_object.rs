//! `flash.net.SharedObject` builtin/prototype

use crate::avm2::error::{
    Error2004Type, make_error_2004, make_error_2008, make_error_2014, make_error_2130,
    make_error_2134, make_error_2139,
};
use crate::avm2::function::FunctionArgs;
use crate::avm2::object::{EventObject, ScriptObject, SharedObjectObject};
use crate::avm2::parameters::ParametersExt;
use crate::avm2::{Activation, Avm2, Error, Object, Value};
use crate::string::AvmString;
use flash_lso::types::{AMFVersion, Lso};
use ruffle_macros::istr;
use std::borrow::Cow;

fn new_lso<'gc>(
    activation: &mut Activation<'_, 'gc>,
    name: &str,
    data: Object<'gc>,
    // Timffle: the shared object's `objectEncoding`
    amf_version: AMFVersion,
) -> Result<Lso, Error<'gc>> {
    let mut elements = Vec::new();
    let mut object_table = crate::avm2::amf::ObjectTable::default();
    crate::avm2::amf::recursive_serialize(
        activation,
        data,
        &mut elements,
        None,
        amf_version,
        &mut object_table,
    )?;
    // Timffle: a thrown `ObjectEncoding.dynamicPropertyWriter` aborts the flush.
    object_table.take_error()?;
    Ok(Lso::new(
        elements,
        name.split('/')
            .next_back()
            .map(|e| e.to_string())
            .unwrap_or_else(|| "<unknown>".to_string()),
        amf_version,
    ))
}

pub fn get_local<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    // TODO: It appears that Flash does some kind of escaping here:
    // the name "foo\uD800" correspond to a file named "fooE#FB#FB#D.sol".

    let name = args.get_string_non_null(activation, 0, "name")?;
    let name = name.to_utf8_lossy();

    const INVALID_CHARS: &str = "~%&\\;:\"',<>?# ";
    if name.contains(|c| INVALID_CHARS.contains(c)) {
        tracing::error!("SharedObject::get_local: Invalid character in name");
        return Ok(Value::Null);
    }

    let mut movie_url = if let Ok(url) = url::Url::parse(activation.context.root_swf.url()) {
        url
    } else {
        tracing::error!("SharedObject::get_local: Unable to parse movie URL");
        return Ok(Value::Null);
    };
    movie_url.set_query(None);
    movie_url.set_fragment(None);

    let secure = args.get_bool(2);

    // Secure parameter disallows using the shared object from non-HTTPS.
    if secure && movie_url.scheme() != "https" {
        tracing::warn!(
            "SharedObject.get_local: Tried to load a secure shared object from non-HTTPS origin"
        );
        return Ok(Value::Null);
    }

    // Shared objects are sandboxed per-domain.
    // By default, they are keyed based on the SWF URL, but the `localHost` parameter can modify this path.
    let mut movie_path = movie_url.path();
    // Remove leading/trailing slashes.
    movie_path = movie_path.strip_prefix('/').unwrap_or(movie_path);
    movie_path = movie_path.strip_suffix('/').unwrap_or(movie_path);

    let movie_host = if movie_url.scheme() == "file" {
        // Remove drive letter on Windows (TODO: move this logic into DiskStorageBackend?)
        if let [_, b':', b'/', ..] = movie_path.as_bytes() {
            movie_path = &movie_path[3..];
        }
        "localhost"
    } else {
        movie_url.host_str().unwrap_or_default()
    };

    let local_path = &args.try_get_string(1);
    let local_path = if let Some(local_path) = local_path {
        // Empty local path always fails.
        if local_path.is_empty() {
            return Ok(Value::Null);
        }

        // Remove leading/trailing slashes.
        let mut local_path = local_path.to_utf8_lossy();
        if local_path.ends_with('/') {
            match &mut local_path {
                Cow::Owned(p) => {
                    p.pop();
                }
                Cow::Borrowed(p) => *p = &p[..p.len() - 1],
            }
        }
        if local_path.starts_with('/') {
            match &mut local_path {
                Cow::Owned(p) => {
                    p.remove(0);
                }
                Cow::Borrowed(p) => *p = &p[1..],
            }
        }

        // Verify that local_path is a prefix of the SWF path.
        if movie_path.starts_with(local_path.as_ref())
            && (local_path.is_empty()
                || movie_path.len() == local_path.len()
                || movie_path[local_path.len()..].starts_with('/'))
        {
            local_path
        } else {
            tracing::warn!("SharedObject.get_local: localPath parameter does not match SWF path");
            return Ok(Value::Null);
        }
    } else {
        Cow::Borrowed(movie_path)
    };

    // Final SO path: foo.com/folder/game.swf/SOName
    // SOName may be a path containing slashes. In this case, prefix with # to mimic Flash Player behavior.
    let prefix = if name.contains('/') { "#" } else { "" };
    let full_name = format!("{movie_host}/{local_path}/{prefix}{name}");

    // Avoid any paths with `..` to prevent SWFs from crawling the file system on desktop.
    // Flash will generally fail to save shared objects with a path component starting with `.`,
    // so let's disallow them altogether.
    if full_name.split('/').any(|s| s.starts_with('.')) {
        tracing::error!("SharedObject.get_local: Invalid path with .. segments");
        return Ok(Value::Null);
    }

    // Check if this is referencing an existing shared object
    if let Some(so) = activation.context.avm2_shared_objects.get(&full_name) {
        return Ok((*so).into());
    }

    let mut data = None;

    // Load the data object from storage if it existed prior
    if let Some(saved) = activation.context.storage.get(&full_name)
        && let Ok(lso) = flash_lso::read::Reader::default().parse(&saved)
    {
        data = crate::avm2::amf::deserialize_lso(activation, &lso)?.into();
    }

    let data = if let Some(data) = data {
        data
    } else {
        // No data; create a fresh data object.
        ScriptObject::new_object(activation.context)
    };

    let created_shared_object =
        SharedObjectObject::from_data_and_name(activation, data, full_name.clone());

    activation
        .context
        .avm2_shared_objects
        .insert(full_name, created_shared_object);

    Ok(created_shared_object.into())
}

pub fn get_data<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let shared_object = this.as_shared_object().unwrap();

    Ok(shared_object.data().into())
}

pub fn flush<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let shared_object = this.as_shared_object().unwrap();

    let min_disk_space = args.get_i32(0);

    flush_impl(activation, shared_object, min_disk_space).map(Value::from)
}

pub fn flush_impl<'gc>(
    activation: &mut Activation<'_, 'gc>,
    shared_object: SharedObjectObject<'gc>,
    _min_disk_space: i32,
) -> Result<AvmString<'gc>, Error<'gc>> {
    let data = shared_object.data();
    let name = shared_object.name();

    // Timffle: a remote shared object has no file to flush to.
    if shared_object.is_remote() {
        return Err(make_error_2130(activation));
    }

    let mut lso = new_lso(activation, name, data, shared_object.object_encoding())?;
    // Flash does not write empty LSOs to disk
    if lso.body.is_empty() {
        Ok(istr!("flushed"))
    } else {
        let bytes = flash_lso::write::write_to_bytes(&mut lso).unwrap_or_default();
        if activation.context.storage.put(name, &bytes) {
            Ok(istr!("flushed"))
        } else {
            Err(make_error_2130(activation))
        }
    }
    // FIXME - We should dispatch a NetStatusEvent after this function returns
}

pub fn get_size<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let shared_object = this.as_shared_object().unwrap();

    let data = shared_object.data();
    let name = shared_object.name();

    let mut lso = new_lso(activation, name, data, shared_object.object_encoding())?;
    // Flash returns 0 for empty LSOs, but the actual number of bytes (including the header) otherwise
    if lso.body.is_empty() {
        Ok(0.into())
    } else {
        let bytes = flash_lso::write::write_to_bytes(&mut lso).unwrap_or_default();
        Ok(Value::from_usize_lossy(bytes.len()))
    }
}

/// Timffle: `close()` ends a remote shared object's server session. A local
/// shared object is unaffected (Flash keeps `data`, and `flush()` still
/// works after it); a remote one here never had a connection.
pub fn close<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(Value::Undefined)
}

pub fn clear<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let shared_object = this.as_shared_object().unwrap();

    // Clear the local data object.
    shared_object.reset_data(activation.context);

    // Delete data from storage backend.
    // Timffle: a remote shared object has nothing on disk.
    if !shared_object.is_remote() {
        let name = shared_object.name();
        activation.context.storage.remove_key(name);
    }

    Ok(Value::Undefined)
}

/// Timffle: `objectEncoding`, AMF0 (0) or AMF3 (3).
pub fn get_object_encoding<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let shared_object = this.as_object().unwrap().as_shared_object().unwrap();
    Ok(amf_version_number(shared_object.object_encoding()).into())
}

/// Timffle: only 0 and 3 are accepted (ArgumentError #2008, like Flash).
pub fn set_object_encoding<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let shared_object = this.as_object().unwrap().as_shared_object().unwrap();
    let encoding = match args.get_u32(0) {
        0 => AMFVersion::AMF0,
        3 => AMFVersion::AMF3,
        _ => return Err(make_error_2008(activation, "objectEncoding")),
    };
    shared_object.set_object_encoding(encoding);
    Ok(Value::Undefined)
}

fn amf_version_number(version: AMFVersion) -> u32 {
    match version {
        AMFVersion::AMF0 => 0,
        AMFVersion::AMF3 => 3,
    }
}

/// Timffle: `defaultObjectEncoding`; Flash stores any value, and a new
/// shared object serializes with AMF0 when it is 0, AMF3 otherwise.
pub fn get_default_object_encoding<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(activation.avm2().shared_object_default_encoding.into())
}

pub fn set_default_object_encoding<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    activation.avm2().shared_object_default_encoding = args.get_u32(0);
    Ok(Value::Undefined)
}

/// Timffle: `preventBackup` is an AIR (iOS) setting. Flash Player reads
/// back `null` until something was assigned, then the assigned value.
pub fn get_prevent_backup<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(match activation.avm2().shared_object_prevent_backup {
        Some(value) => value.into(),
        None => Value::Null,
    })
}

pub fn set_prevent_backup<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    activation.avm2().shared_object_prevent_backup = Some(args.get_bool(0));
    Ok(Value::Undefined)
}

/// Timffle: `client`, the object the server's callbacks go to; the shared
/// object itself by default.
pub fn get_client<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let shared_object = this.as_shared_object().unwrap();
    Ok(shared_object.client().unwrap_or(this).into())
}

/// Timffle: `client` must be a non-null object (TypeError #2004).
pub fn set_client<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let shared_object = this.as_shared_object().unwrap();
    let Some(client) = args.get_value(0).as_object() else {
        return Err(make_error_2004(activation, Error2004Type::TypeError));
    };
    let client = if Object::ptr_eq(client, this) {
        None
    } else {
        Some(client)
    };
    shared_object.set_client(activation.context, client);
    Ok(Value::Undefined)
}

/// Timffle: `fps` (write-only): how often changes go to the server. Stored;
/// there is no server connection to pace.
pub fn set_fps<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let shared_object = this.as_object().unwrap().as_shared_object().unwrap();
    shared_object.set_fps(args.get_f64(0));
    Ok(Value::Undefined)
}

/// Timffle: `connect(myConnection, params)`. Flash needs a remote shared
/// object and a NetConnection to its server: a local shared object, a null
/// or unconnected NetConnection raise #2139, and a connected NetConnection
/// whose URI is not the object's server dispatches `NetStatusEvent`
/// "SharedObject.UriMismatch" (level error) before #2139. Ruffle's
/// NetConnection reaches no RTMP server (`connect(null)` and Flash Remoting
/// only), so a connected one always mismatches.
pub fn connect<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let shared_object = this.as_shared_object().unwrap();

    if shared_object.is_remote() {
        let connected = args
            .try_get_object(0)
            .and_then(|nc| nc.as_net_connection())
            .and_then(|nc| nc.handle())
            .is_some_and(|handle| activation.context.net_connections.is_connected(handle));
        if connected {
            let event = EventObject::net_status_event(
                activation,
                vec![("code", "SharedObject.UriMismatch"), ("level", "error")],
            );
            Avm2::dispatch_event(activation.context, event, this);
        }
    }

    Err(make_error_2139(activation))
}

/// Timffle: `send(...args)` broadcasts a message through the server to every
/// client of a remote shared object. Without a server connection there is
/// nobody to send to; Flash raises no error either.
pub fn send<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(Value::Undefined)
}

/// Timffle: `setDirty(propertyName)` marks a property for the next sync to
/// the server (#2007 for a null name). A local shared object, and a remote
/// one without a connection, have nothing to synchronize.
pub fn set_dirty<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    args.get_string_non_null(activation, 0, "propertyName")?;
    Ok(Value::Undefined)
}

/// Timffle: `getRemote(name, remotePath, persistence, secure)`. The remote
/// path must name an RTMP-family server (`rtmp`, `rtmpt`, `rtmps`,
/// `rtmpe`, `rtmpte`, `rtmfp`), else #2134 (#2007 for a null name). One
/// object per (name, path, persistence); its data lives in memory only.
pub fn get_remote<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let name = args.get_string_non_null(activation, 0, "name")?;
    let Some(remote_path) = args.try_get_string(1) else {
        return Err(make_error_2134(activation));
    };
    let remote_path = remote_path.to_utf8_lossy();
    let scheme = remote_path
        .split_once("://")
        .map(|(scheme, _)| scheme.to_ascii_lowercase());
    let rtmp_family = ["rtmp", "rtmpt", "rtmps", "rtmpe", "rtmpte", "rtmfp"];
    if !scheme.is_some_and(|s| rtmp_family.contains(&s.as_str())) {
        return Err(make_error_2134(activation));
    }
    let persistence = args.get_value(2).coerce_to_boolean();

    // Remote objects live in the same table as local ones under a key no
    // local name can produce (local keys start with a host name).
    let key = format!(
        "rtmp-remote://{remote_path}/{}/{}",
        name.to_utf8_lossy(),
        persistence
    );
    if let Some(so) = activation.context.avm2_shared_objects.get(&key) {
        return Ok((*so).into());
    }

    let data = ScriptObject::new_object(activation.context);
    let so = SharedObjectObject::new(activation, data, name.to_string(), true);
    activation.context.avm2_shared_objects.insert(key, so);
    Ok(so.into())
}

/// Timffle: `deleteAll(url)` is an AIR feature; Flash Player raises #2014
/// for any URL (#2007 for null) and deletes nothing.
pub fn delete_all<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    args.get_string_non_null(activation, 0, "url")?;
    Err(make_error_2014(activation))
}

/// Timffle: `getDiskUsage(url)` is an AIR feature; Flash Player raises
/// #2014 for any URL (#2007 for null).
pub fn get_disk_usage<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    args.get_string_non_null(activation, 0, "url")?;
    Err(make_error_2014(activation))
}
