use crate::avm2::bytearray::ByteArrayStorage;
use crate::avm2::error::{
    make_error_2007, make_error_2037, make_error_2041, make_error_2085, make_error_2097,
    make_error_2174,
};
use crate::avm2::function::FunctionArgs;
use crate::avm2::globals::flash::display::loader::request_from_url_request;
use crate::avm2::globals::flash::net::object_to_index_map;
use crate::avm2::globals::slots::flash_net_file_filter as file_filter_slots;
use crate::avm2::globals::slots::flash_net_url_request as url_request_slots;
use crate::avm2::object::{ByteArrayObject, DateObject, FileReference};
use crate::avm2::parameters::ParametersExt;
use crate::avm2::{Activation, Avm2, Error, EventObject, Object, TObject as _, Value};
use crate::backend::navigator::Request;
use crate::backend::ui::FileFilter;
use crate::string::AvmString;
use indexmap::IndexMap;
use url::Url;

pub use crate::avm2::object::file_reference_allocator;

/// Timffle: the `typeFilter` argument of `FileReference.browse()` and
/// `FileReferenceList.browse()`: an Array of well-formed `FileFilter`s or null, else #2097.
pub fn parse_file_filters<'gc>(
    activation: &mut Activation<'_, 'gc>,
    type_filter: Option<Object<'gc>>,
) -> Result<Vec<FileFilter>, Error<'gc>> {
    let mut filters = Vec::new();
    if let Some(obj) = type_filter
        && let Some(array_storage) = obj.as_array_storage()
    {
        for filter in array_storage.iter() {
            if let Some(Value::Object(obj)) = filter {
                let filefilter = activation
                    .avm2()
                    .classes()
                    .filefilter
                    .inner_class_definition();
                if !obj.is_of_type(filefilter) {
                    return Err(make_error_2097(activation));
                }

                let description = obj.get_slot(file_filter_slots::_DESCRIPTION);
                let extension = obj.get_slot(file_filter_slots::_EXTENSION);
                let mac_type = obj.get_slot(file_filter_slots::_MAC_TYPE);

                // The description and extension must be non-empty strings.
                match (description, extension) {
                    (Value::String(description), Value::String(extension))
                        if !description.is_empty() && !extension.is_empty() =>
                    {
                        let mac_type = match mac_type {
                            Value::String(mac_type) if !mac_type.is_empty() => {
                                Some(mac_type.to_string())
                            }
                            _ => None,
                        };

                        filters.push(FileFilter {
                            description: description.to_string(),
                            extensions: extension.to_string(),
                            mac_type,
                        });
                    }
                    _ => return Err(make_error_2097(activation)),
                }
            } else {
                return Err(make_error_2097(activation));
            }
        }
    }
    Ok(filters)
}

pub fn get_creation_date<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let this = this.as_file_reference().unwrap();

    let creation_date = match *this.file_reference() {
        FileReference::None => return Err(make_error_2037(activation)),
        FileReference::FileDialogSelection(ref selection) => {
            if let Some(time) = selection.creation_time() {
                DateObject::from_date_time(activation.context, time).into()
            } else {
                Value::Null
            }
        }
    };

    Ok(creation_date)
}

pub fn get_data<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let this = this.as_file_reference().unwrap();

    let bytearray = match *this.file_reference() {
        FileReference::FileDialogSelection(ref selection) if this.loaded() => {
            let bytes = selection.contents();
            let storage = ByteArrayStorage::from_vec(activation.context, bytes.to_vec());
            ByteArrayObject::from_storage(activation.context, storage)
        }
        // Contrary to other getters `data` will return null instead of throwing.
        _ => return Ok(Value::Null),
    };

    Ok(bytearray.into())
}

pub fn get_modification_date<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let this = this.as_file_reference().unwrap();

    let modification_date = match *this.file_reference() {
        FileReference::None => return Err(make_error_2037(activation)),
        FileReference::FileDialogSelection(ref selection) => {
            if let Some(time) = selection.modification_time() {
                DateObject::from_date_time(activation.context, time).into()
            } else {
                Value::Null
            }
        }
    };

    Ok(modification_date)
}

pub fn get_name<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let this = this.as_file_reference().unwrap();

    let name = match *this.file_reference() {
        FileReference::None => return Err(make_error_2037(activation)),
        FileReference::FileDialogSelection(ref selection) => {
            let name = selection.file_name();
            AvmString::new_utf8(activation.gc(), name).into()
        }
    };

    Ok(name)
}

pub fn get_size<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let this = this.as_file_reference().unwrap();

    let size = match *this.file_reference() {
        FileReference::None => return Err(make_error_2037(activation)),
        FileReference::FileDialogSelection(ref selection) => selection.size().unwrap_or(0),
    };

    Ok(Value::Number(size as f64))
}

pub fn get_type<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let this = this.as_file_reference().unwrap();

    let type_ = match *this.file_reference() {
        FileReference::None => return Err(make_error_2037(activation)),
        FileReference::FileDialogSelection(ref selection) => {
            let type_ = selection.file_type().unwrap_or_default();
            AvmString::new_utf8(activation.gc(), type_).into()
        }
    };

    Ok(type_)
}

pub fn browse<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let this = this.as_file_reference().unwrap();

    let filters = parse_file_filters(activation, args.try_get_object(0))?;

    let dialog = activation.context.ui.display_file_open_dialog(filters);
    let result = match dialog {
        Some(dialog) => {
            let process = crate::loader::select_file_dialog_avm2(activation.context, this, dialog);

            activation.context.navigator.spawn_future(process);
            true
        }
        None => false,
    };

    Ok(result.into())
}

pub fn load<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let this = this.as_file_reference().unwrap();

    // Somewhat unexpectedly, we don't need to load anything here, because
    // that already happened during browse() or save().

    let size = match *this.file_reference() {
        FileReference::None => return Err(make_error_2037(activation)),
        FileReference::FileDialogSelection(ref selection) => selection.size().unwrap_or(0),
    };

    let size = size as usize;

    let open_evt = EventObject::bare_default_event(activation.context, "open");
    Avm2::dispatch_event(activation.context, open_evt, this.into());

    let progress_evt = EventObject::progress_event(activation, "progress", 0, size);
    Avm2::dispatch_event(activation.context, progress_evt, this.into());

    let open_evt2 = EventObject::bare_default_event(activation.context, "open");
    Avm2::dispatch_event(activation.context, open_evt2, this.into());

    let progress_evt2 = EventObject::progress_event(activation, "progress", size, size);
    Avm2::dispatch_event(activation.context, progress_evt2, this.into());

    this.set_loaded(true);

    let complete_evt = EventObject::bare_default_event(activation.context, "complete");
    Avm2::dispatch_event(activation.context, complete_evt, this.into());

    Ok(Value::Undefined)
}

/// Timffle: `FileReference.cancel()`.
pub fn cancel<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let this = this.as_file_reference().unwrap();

    this.cancel_operations();

    Ok(Value::Undefined)
}

/// Timffle: `FileReference.download(request, defaultFileName)`: the save dialog, then the
/// request (see `loader::download_file_dialog_avm2`). `defaultFileName` falls back to the
/// last path segment of the URL. Flash's character restrictions on the name are not
/// checked (the reference does not say which error that is).
pub fn download<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let this = this.as_file_reference().unwrap();

    let request = args.get_object(activation, 0, "request")?;
    let request = request_from_url_request(activation, request)?;

    let file_name = match args.try_get_string(1) {
        Some(name) if !name.is_empty() => name.to_string(),
        _ => request
            .url()
            .split(['?', '#'])
            .next()
            .unwrap_or("")
            .rsplit('/')
            .next()
            .unwrap_or("")
            .to_string(),
    };
    let domain = Url::parse(request.url())
        .ok()
        .and_then(|url| url.host_str().map(|host| host.to_string()))
        .unwrap_or_else(|| "<unknown domain>".to_string());

    let dialog = activation.context.ui.display_file_save_dialog(
        file_name,
        format!("Select location for download from {domain}"),
    );
    let Some(dialog) = dialog else {
        return Err(make_error_2041(activation));
    };

    let generation = this.generation();
    let process = crate::loader::download_file_dialog_avm2(
        activation.context,
        this,
        dialog,
        request,
        generation,
    );
    activation.context.navigator.spawn_future(process);

    Ok(Value::Undefined)
}

/// Timffle: `FileReference.upload(request, uploadDataFieldName, testUpload)`: the selected
/// file as a multipart/form-data POST in Flash Player's layout (`Filename`, the request's
/// URLVariables as fields, the file under `uploadDataFieldName`, `Upload` = `Submit Query`).
/// `testUpload` is ignored (a Windows-only probe POST). A non-URLVariables POST body is not
/// sent (the reference only specifies URLVariables); GET data goes into the query string.
pub fn upload<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let this = this.as_file_reference().unwrap();

    let request_obj = args.get_object(activation, 0, "request")?;
    let field_name = args
        .try_get_string(1)
        .ok_or_else(|| make_error_2007(activation, "uploadDataFieldName"))?;
    if field_name.is_empty() {
        return Err(make_error_2085(activation, "uploadDataFieldName"));
    }
    let field_name = field_name.to_string();

    let (file_name, data) = match *this.file_reference() {
        FileReference::None => return Err(make_error_2037(activation)),
        FileReference::FileDialogSelection(ref selection) => {
            (selection.file_name(), selection.contents().to_vec())
        }
    };

    // The request's own URLVariables become separate form fields on a POST.
    let method = request_obj
        .get_slot(url_request_slots::_METHOD)
        .coerce_to_string(activation)?;
    let mut fields = IndexMap::new();
    if method.to_utf8_lossy().eq_ignore_ascii_case("POST")
        && let Some(data_obj) = request_obj.get_slot(url_request_slots::_DATA).as_object()
    {
        let urlvariables = activation
            .avm2()
            .classes()
            .urlvariables
            .inner_class_definition();
        if data_obj.is_of_type(urlvariables) {
            fields = object_to_index_map(activation, &data_obj)?;
        }
    }

    // #2007 for a null url; GET data lands in the query string.
    let base_request = request_from_url_request(activation, request_obj)?;
    let url = base_request.url().to_string();

    let (body, content_type) = multipart_upload_body(&file_name, &data, &field_name, &fields);
    let request = Request::post(url, Some((body, content_type)));

    let generation = this.generation();
    let process =
        crate::loader::upload_file_avm2(activation.context, this, request, data.len(), generation);
    activation.context.navigator.spawn_future(process);

    Ok(Value::Undefined)
}

/// The multipart/form-data body Flash Player sends for `FileReference.upload()` (AS3
/// reference, `upload()`), with CRLF line ends. The boundary is derived from the content so
/// that it is reproducible, and extended until it occurs nowhere in the parts.
fn multipart_upload_body(
    file_name: &str,
    data: &[u8],
    field_name: &str,
    fields: &IndexMap<String, String>,
) -> (Vec<u8>, String) {
    use std::hash::{Hash, Hasher};

    let mut hasher = fnv::FnvHasher::default();
    file_name.hash(&mut hasher);
    data.hash(&mut hasher);
    field_name.hash(&mut hasher);
    for (name, value) in fields {
        name.hash(&mut hasher);
        value.hash(&mut hasher);
    }
    let mut boundary = format!("----------{:016x}", hasher.finish());
    let contains = |boundary: &str, bytes: &[u8]| {
        bytes
            .windows(boundary.len())
            .any(|window| window == boundary.as_bytes())
    };
    while contains(&boundary, data)
        || contains(&boundary, file_name.as_bytes())
        || fields
            .iter()
            .any(|(n, v)| contains(&boundary, n.as_bytes()) || contains(&boundary, v.as_bytes()))
    {
        boundary.push('x');
    }

    let mut body = Vec::with_capacity(data.len() + 512);
    let part = |body: &mut Vec<u8>, disposition: &str| {
        body.extend_from_slice(b"--");
        body.extend_from_slice(boundary.as_bytes());
        body.extend_from_slice(b"\r\nContent-Disposition: form-data; ");
        body.extend_from_slice(disposition.as_bytes());
        body.extend_from_slice(b"\r\n");
    };

    part(&mut body, "name=\"Filename\"");
    body.extend_from_slice(b"\r\n");
    body.extend_from_slice(file_name.as_bytes());
    body.extend_from_slice(b"\r\n");
    for (name, value) in fields {
        part(&mut body, &format!("name=\"{name}\""));
        body.extend_from_slice(b"\r\n");
        body.extend_from_slice(value.as_bytes());
        body.extend_from_slice(b"\r\n");
    }
    part(
        &mut body,
        &format!("name=\"{field_name}\"; filename=\"{file_name}\""),
    );
    body.extend_from_slice(b"Content-Type: application/octet-stream\r\n\r\n");
    body.extend_from_slice(data);
    body.extend_from_slice(b"\r\n");
    part(&mut body, "name=\"Upload\"");
    body.extend_from_slice(b"\r\nSubmit Query\r\n");
    body.extend_from_slice(b"--");
    body.extend_from_slice(boundary.as_bytes());
    body.extend_from_slice(b"--\r\n");

    let content_type = format!("multipart/form-data; boundary={boundary}");
    (body, content_type)
}

pub fn save_internal<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let this = this.as_file_reference().unwrap();
    let byte_array = args
        .try_get_object(0)
        .expect("AS code ensures data is non-null");

    let mut byte_array = byte_array.as_bytearray_mut().unwrap();

    let mut data = Vec::new();
    byte_array.swap_storage_with(&mut data);
    // The ByteArray is now empty, and `data` stores the data previously
    // contained in it

    let file_name = args
        .try_get_string(1)
        .expect("AS code ensures defaultFileName is non-null");

    // Create and spawn dialog
    let dialog = activation.context.ui.display_file_save_dialog(
        file_name.to_string(),
        format!("Select location to save the file {file_name}"),
    );

    match dialog {
        Some(dialog) => {
            let process = crate::loader::save_file_dialog(activation.context, this, dialog, data);

            activation.context.navigator.spawn_future(process);
        }
        None => return Err(make_error_2174(activation)),
    }

    Ok(Value::Undefined)
}
