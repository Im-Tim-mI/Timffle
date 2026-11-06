//! `flash.system.System` native methods

use crate::avm2::Error;
use crate::avm2::activation::Activation;
use crate::avm2::e4x::E4XNode;
use crate::avm2::error::{make_error_2017, make_error_2018};
use crate::avm2::function::FunctionArgs;
use crate::avm2::object::ScriptObject;
use crate::avm2::parameters::ParametersExt;
use crate::avm2::value::Value;
use crate::string::AvmString;
use ruffle_common::sandbox::SandboxType;

/// Implements `flash.system.System.setClipboard` method
pub fn set_clipboard<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    // The following restrictions only apply to the plugin.
    // Timffle: the browser plugin only allows this while a user event (mouse,
    // keyboard) is being handled; `Avm2::in_user_interaction` tracks that.
    #[cfg(target_family = "wasm")]
    if !activation.avm2().in_user_interaction {
        return Err(crate::avm2::error::make_error_2176(activation));
    }

    let new_content = args.get_string_non_null(activation, 0, "text")?;
    activation
        .context
        .ui
        .set_clipboard_content(new_content.to_string());

    Ok(Value::Undefined)
}

/// Timffle: `System.exit(code)`. The browser plugin raises #2018, any
/// sandbox other than local-trusted raises #2017, and the standalone player
/// quits (the desktop front end ends its event loop; a host without that
/// ability ignores the call, as `UiBackend::exit` documents).
pub fn exit<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    if cfg!(target_family = "wasm") {
        return Err(make_error_2018(activation));
    }

    let movie = activation.caller_movie_or_root();
    if !matches!(movie.sandbox_type(), SandboxType::LocalTrusted) {
        return Err(make_error_2017(activation));
    }

    let code = args.get_u32(0);
    activation.context.ui.exit(code);
    Ok(Value::Undefined)
}

/// Timffle: `System.pause()`. A debugger hook: the release Flash Player
/// (32.0.0.465 measured) keeps running scripts, timers and frames after
/// `pause()`, so there is nothing to stop here.
pub fn pause<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(Value::Undefined)
}

/// Timffle: `System.resume()`; see [`pause`].
pub fn resume<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(Value::Undefined)
}

/// Timffle: `System.ime`: the player's single `IME` instance (an abstract
/// class, so the object is made here like `Stage.stageVideos`). Created on
/// first use and kept for the life of the player.
pub fn get_ime<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    if let Some(existing) = activation.avm2().system_ime {
        return Ok(existing.into());
    }
    let class = activation.avm2().classes().ime;
    let ime = ScriptObject::custom_object(
        activation.gc(),
        class.inner_class_definition(),
        Some(class.prototype()),
        class.instance_vtable(),
    );
    activation.avm2().system_ime = Some(ime);
    Ok(ime.into())
}

/// Timffle: `System.processCPUUsage` is an AIR feature; Flash Player
/// reports 0 (measured on 32.0.0.465).
pub fn get_process_cpu_usage<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(0.into())
}

/// Timffle: `System.useCodePage`, shared with AVM1's `System.useCodePage`:
/// when true, text loaded by `URLLoader`/`URLStream`/`loadVariables` is
/// decoded with the system code page (Windows-1252 here) instead of UTF-8.
pub fn get_use_code_page<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(activation.context.system.use_codepage.into())
}

pub fn set_use_code_page<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    activation.context.system.use_codepage = args.get_bool(0);
    Ok(Value::Undefined)
}

/// Timffle: `System.vmVersion`, the AVM2 build string of Flash Player 32.
pub fn get_vm_version<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(AvmString::new_utf8(activation.gc(), "2.1 sec cyclone").into())
}

/// Timffle: `System.freeMemory` (see `crate::memory`).
pub fn get_free_memory<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let (_, free, _) = crate::memory::flash_memory_figures();
    Ok((free as f64).into())
}

/// Timffle: `System.privateMemory` (see `crate::memory`).
pub fn get_private_memory<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let (_, _, private) = crate::memory::flash_memory_figures();
    Ok((private as f64).into())
}

/// Timffle: `System.totalMemoryNumber` (see `crate::memory`).
pub fn get_total_memory_number<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let (total, _, _) = crate::memory::flash_memory_figures();
    Ok((total as f64).into())
}

/// Timffle: `System.pauseForGCIfCollectionImminent(imminence)`. Flash runs
/// a collection now when its own estimate of how close the next one is
/// reaches `imminence` (0..1; `NaN` means the default 0.75). The estimate
/// here is the share of the live heap allocated since the collector last
/// woke up (gc-arena's allocation debt over the live object count): when it
/// reaches the threshold a whole cycle runs right after this update, as
/// `Loader.unloadAndStop(true)` does. Any argument is accepted, like Flash.
pub fn pause_for_gc_if_collection_imminent<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let mut imminence = args.get_f64(0);
    if imminence.is_nan() {
        imminence = 0.75;
    }
    let imminence = imminence.clamp(0.0, 1.0);

    let metrics = activation.gc().metrics();
    let live = metrics.total_gc_count().max(1) as f64;
    let estimate = (metrics.allocation_debt() / live).clamp(0.0, 1.0);
    if estimate >= imminence {
        *activation.context.full_gc_requested = true;
    }
    Ok(Value::Undefined)
}

/// Timffle: `System.disposeXML(node)`. Flash (32.0.0.465 measured) cuts the
/// tree *below* the node so it can be collected piecemeal: every descendant
/// loses its parent link and its own children, while the node itself keeps
/// its child list, attributes and name (attributes keep their parent). A
/// text node or `null` is left alone. Descendants are marked disposed so
/// their `parent()` answers `null` (a root's answers `undefined`).
pub fn dispose_xml<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let Some(xml) = args.try_get_object(0).and_then(|o| o.as_xml_object()) else {
        return Ok(Value::Undefined);
    };
    let mc = activation.gc();
    let node = xml.node();
    let children: Vec<E4XNode<'gc>> = node_children(node);
    for child in children {
        child.set_parent(None, mc);
        child.set_disposed();
        dispose_descendants(child, mc);
    }
    Ok(Value::Undefined)
}

fn node_children<'gc>(node: E4XNode<'gc>) -> Vec<E4XNode<'gc>> {
    match &*node.kind() {
        crate::avm2::e4x::E4XNodeKind::Element { children, .. } => children.clone(),
        _ => Vec::new(),
    }
}

fn dispose_descendants<'gc>(node: E4XNode<'gc>, mc: &gc_arena::Mutation<'gc>) {
    for child in node_children(node) {
        child.set_disposed();
        dispose_descendants(child, mc);
    }
    node.remove_all_children(mc);
}
