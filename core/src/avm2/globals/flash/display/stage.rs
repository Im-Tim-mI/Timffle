//! `flash.display.Stage` builtin/prototype

use crate::avm2::Error;
use crate::avm2::activation::Activation;
use crate::avm2::error::{make_error_2008, make_error_3707};
use crate::avm2::function::FunctionArgs;
use crate::avm2::globals::flash::system::capabilities::screen_resolution;
use crate::avm2::globals::slots::flash_events_stage_video_availability_event as availability_slots; // Timffle
use crate::avm2::globals::slots::flash_geom_rectangle as rectangle_slots;
use crate::avm2::object::{ScriptObject, TObject, VectorObject};
use crate::avm2::parameters::ParametersExt;
use crate::avm2::value::Value;
use crate::avm2::vector::VectorStorage;
use crate::display_object::{
    FullScreenSourceRect, StageDisplayState, TDisplayObject, TDisplayObjectContainer,
    TInteractiveObject, WindowMode,
};
use crate::string::{AvmString, WString};
use swf::Color;

/// Timffle: whether the SWF that runs `activation` may script the object
/// that has keyboard focus (`Stage.focus` is null and
/// `Stage.isFocusInaccessible()` true otherwise, as in Flash Player).
fn focus_accessible(activation: &mut Activation<'_, '_>) -> bool {
    match activation.context.focus_tracker.get() {
        Some(focus) => {
            let caller = activation.caller_movie_or_root();
            focus
                .as_displayobject()
                .movie()
                .allows_access_from(caller.url())
        }
        None => true,
    }
}

/// Implement `align`'s getter
pub fn get_align<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let align = activation.context.stage.align();
    let mut s = WString::with_capacity(4, false);
    // Match string values returned by AS.
    // It's possible to have an oxymoronic "TBLR".
    // This acts the same as "TL" (top-left takes priority).
    // This order is different between AVM1 and AVM2!
    use crate::display_object::StageAlign;
    if align.contains(StageAlign::TOP) {
        s.push_byte(b'T');
    }
    if align.contains(StageAlign::BOTTOM) {
        s.push_byte(b'B');
    }
    if align.contains(StageAlign::LEFT) {
        s.push_byte(b'L');
    }
    if align.contains(StageAlign::RIGHT) {
        s.push_byte(b'R');
    }
    let align = AvmString::new(activation.gc(), s);
    Ok(align.into())
}

/// Implement `align`'s setter
pub fn set_align<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let align = args.get_string(activation, 0).parse().unwrap_or_default();
    activation
        .context
        .stage
        .set_align(activation.context, align);
    Ok(Value::Undefined)
}

/// Implement `browserZoomFactor`'s getter
pub fn get_browser_zoom_factor<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if this
        .as_display_object()
        .and_then(|this| this.as_stage())
        .is_some()
    {
        return Ok(activation
            .context
            .renderer
            .viewport_dimensions()
            .scale_factor
            .into());
    }

    Ok(Value::Undefined)
}

/// Implement `color`'s getter
pub fn get_color<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(dobj) = this.as_display_object().and_then(|this| this.as_stage()) {
        let color = dobj.background_color().unwrap_or(Color::WHITE);
        return Ok(color.to_rgba().into());
    }

    Ok(Value::Undefined)
}

/// Implement `color`'s setter
pub fn set_color<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(dobj) = this.as_display_object().and_then(|this| this.as_stage()) {
        let color = Color::from_rgb(args.get_u32(0), 255);
        dobj.set_background_color(Some(color));
    }

    Ok(Value::Undefined)
}

/// Implement `contentsScaleFactor`'s getter
pub fn get_contents_scale_factor<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if this
        .as_display_object()
        .and_then(|this| this.as_stage())
        .is_some()
    {
        return Ok(activation
            .context
            .renderer
            .viewport_dimensions()
            .scale_factor
            .into());
    }

    Ok(Value::Undefined)
}

/// Implement `displayState`'s getter
pub fn get_display_state<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let display_state = AvmString::new_utf8(
        activation.gc(),
        activation.context.stage.display_state().to_string(),
    );
    Ok(display_state.into())
}

/// Implement `displayState`'s setter
pub fn set_display_state<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    if let Ok(mut display_state) = args.get_string(activation, 0).parse() {
        // It's not entirely clear why when setting to FullScreen, desktop flash player at least will
        // set its value to FullScreenInteractive. Overriding until flash logic is clearer.
        if display_state == StageDisplayState::FullScreen {
            display_state = StageDisplayState::FullScreenInteractive;
        }
        activation
            .context
            .stage
            .set_display_state(activation.context, display_state);
    } else {
        return Err(make_error_2008(activation, "displayState"));
    }
    Ok(Value::Undefined)
}

/// Implement `focus`'s getter
pub fn get_focus<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    // Timffle: focus in a sandbox the caller may not script reads as null.
    if !focus_accessible(activation) {
        return Ok(Value::Null);
    }
    Ok(activation
        .context
        .focus_tracker
        .get()
        .map(|o| o.as_displayobject())
        .map(|focus_dobj| focus_dobj.object2_or_null())
        .unwrap_or(Value::Null))
}

/// Timffle: implement `isFocusInaccessible`
pub fn is_focus_inaccessible<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok((!focus_accessible(activation)).into())
}

/// Implement `focus`'s setter
pub fn set_focus<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let focus = activation.context.focus_tracker;
    match args.try_get_object(0) {
        None => focus.set(None, activation.context),
        Some(obj) => {
            let dobj = obj
                .as_display_object()
                .and_then(|o| o.as_interactive())
                .expect("AS-side typing guarantees InteractiveObject");

            focus.set(Some(dobj), activation.context);
        }
    };

    Ok(Value::Undefined)
}

/// Implement `frameRate`'s getter
pub fn get_frame_rate<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let mut frame_rate = *activation.context.frame_rate;
    if frame_rate < 0.0 {
        // Uncommon frame rate from the SWF header.
        frame_rate = frame_rate.rem_euclid(256.0);
    }
    Ok(frame_rate.into())
}

/// Implement `frameRate`'s setter
pub fn set_frame_rate<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    if !activation.context.forced_frame_rate {
        let new_frame_rate = args.get_f64(0).clamp(0.01, 1000.0);
        *activation.context.frame_rate = new_frame_rate;
    }

    Ok(Value::Undefined)
}

pub fn get_show_default_context_menu<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(activation.context.stage.show_menu().into())
}

pub fn set_show_default_context_menu<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let show_default_context_menu = args.get_bool(0);
    activation
        .context
        .stage
        .set_show_menu(show_default_context_menu);
    Ok(Value::Undefined)
}

/// Implement `scaleMode`'s getter
pub fn get_scale_mode<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let scale_mode = AvmString::new_utf8(
        activation.gc(),
        activation.context.stage.scale_mode().to_avm_string(),
    );
    Ok(scale_mode.into())
}

/// Implement `scaleMode`'s setter
pub fn set_scale_mode<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    if let Ok(scale_mode) = args.get_string(activation, 0).parse() {
        activation
            .context
            .stage
            .set_scale_mode(activation.context, scale_mode, true);
    } else {
        return Err(make_error_2008(activation, "scaleMode"));
    }
    Ok(Value::Undefined)
}

/// Implement `stageFocusRect`'s getter
pub fn get_stage_focus_rect<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(dobj) = this.as_display_object().and_then(|this| this.as_stage()) {
        return Ok(dobj.stage_focus_rect().into());
    }

    Ok(Value::Undefined)
}

/// Implement `stageFocusRect`'s setter
pub fn set_stage_focus_rect<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(dobj) = this.as_display_object().and_then(|this| this.as_stage()) {
        let rf = args.get_bool(0);
        dobj.set_stage_focus_rect(rf);
    }

    Ok(Value::Undefined)
}

/// Implement `stageWidth`'s getter
pub fn get_stage_width<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(dobj) = this.as_display_object().and_then(|this| this.as_stage()) {
        return Ok(dobj.stage_size().0.into());
    }

    Ok(Value::Undefined)
}

/// Implement `stageWidth`'s setter
pub fn set_stage_width<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    // For some reason this value is settable but it does nothing.
    Ok(Value::Undefined)
}

/// Implement `stageHeight`'s getter
pub fn get_stage_height<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(dobj) = this.as_display_object().and_then(|this| this.as_stage()) {
        return Ok(dobj.stage_size().1.into());
    }

    Ok(Value::Undefined)
}

/// Implement `stageHeight`'s setter
pub fn set_stage_height<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    // For some reason this value is settable but it does nothing.
    Ok(Value::Undefined)
}

/// Implement `allowsFullScreen`'s getter
///
/// Timffle: whether the host (the `allowFullScreen` embed parameter / the
/// player configuration) lets this movie go full screen.
pub fn get_allows_full_screen<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(activation.context.stage.allow_fullscreen().into())
}

/// Implement `allowsFullScreenInteractive`'s getter
///
/// Timffle: the player's full-screen mode always keeps keyboard input (it
/// never restricts keys the way Flash Player's plain full screen does), so
/// `FULL_SCREEN_INTERACTIVE` is allowed exactly when full screen is.
pub fn get_allows_full_screen_interactive<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(activation.context.stage.allow_fullscreen().into())
}

/// Timffle: `fullScreenSourceRect`'s getter (a copy, as in Flash Player).
pub fn get_full_screen_source_rect<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    match activation.context.stage.full_screen_source_rect() {
        Some(rect) => activation.avm2().classes().rectangle.construct(
            activation,
            &[
                rect.x.into(),
                rect.y.into(),
                rect.width.into(),
                rect.height.into(),
            ],
        ),
        None => Ok(Value::Null),
    }
}

/// Timffle: `fullScreenSourceRect`'s setter. Flash Player stores a rounded,
/// size-clamped copy; `null` goes back to showing the whole stage.
pub fn set_full_screen_source_rect<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    // Read the Rectangle's numbers directly: Flash accepts any value here
    // (NaN, 1e9), which would not fit into twips.
    let rect = args.try_get_object(0).map(|object| {
        FullScreenSourceRect::from_f64(
            object.get_slot(rectangle_slots::X).as_f64(),
            object.get_slot(rectangle_slots::Y).as_f64(),
            object.get_slot(rectangle_slots::WIDTH).as_f64(),
            object.get_slot(rectangle_slots::HEIGHT).as_f64(),
        )
    });
    let stage = activation.context.stage;
    stage.set_full_screen_source_rect(activation.context, rect);
    Ok(Value::Undefined)
}

/// Timffle: `mouseLock`'s getter
pub fn get_mouse_lock<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(activation.context.stage.mouse_lock().into())
}

/// Timffle: `mouseLock`'s setter. Flash Player throws `Error #3707` for any
/// assignment (even `false`) outside full-screen mode.
pub fn set_mouse_lock<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let stage = activation.context.stage;
    if !stage.is_fullscreen() {
        return Err(make_error_3707(activation));
    }
    stage.set_mouse_lock(activation.context, args.get_bool(0));
    Ok(Value::Undefined)
}

/// Timffle: `wmodeGPU`'s getter: true when the page asked for `wmode=gpu`
/// and the content is drawn by a GPU renderer (WebGPU / WebGL / wgpu), the
/// case in which Flash Player reports GPU compositing.
pub fn get_wmode_gpu<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let gpu_renderer = !matches!(activation.context.renderer.name(), "canvas" | "Null");
    Ok((activation.context.stage.window_mode() == WindowMode::Gpu && gpu_renderer).into())
}

/// Timffle: create the `stageVideos` vector. Flash Player 32 offers eight
/// `StageVideo` slots on every platform, GPU or not (whether a video can
/// actually be shown is reported later through `StageVideoAvailabilityEvent`).
/// The class cannot be instantiated from ActionScript (`Error #2012`), so the
/// objects are made here.
pub fn create_stage_videos<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    const STAGE_VIDEO_COUNT: usize = 8;
    let class = activation.avm2().classes().stagevideo;
    let videos = (0..STAGE_VIDEO_COUNT)
        .map(|_| {
            ScriptObject::custom_object(
                activation.gc(),
                class.inner_class_definition(),
                Some(class.prototype()),
                class.instance_vtable(),
            )
            .into()
        })
        .collect();
    let storage = VectorStorage::from_values(videos, false, Some(class.inner_class_definition()));
    Ok(VectorObject::from_vector(storage, activation).into())
}

/// Timffle: fill in the read-only `reason` and `driver` of a
/// `StageVideoAvailabilityEvent` the stage is about to dispatch (its
/// constructor only takes the availability, as in Flash).
pub fn fill_stage_video_availability<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let event = args.get_object(activation, 0, "event")?;
    event.set_slot(availability_slots::REASON, args.get_value(1), activation)?;
    event.set_slot(availability_slots::DRIVER, args.get_value(2), activation)?;
    Ok(Value::Undefined)
}

/// Implement `quality`'s getter
pub fn get_quality<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let quality = activation.context.stage.quality().into_avm_str();
    Ok(AvmString::new_utf8(activation.gc(), quality).into())
}

/// Implement `quality`'s setter
pub fn set_quality<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    // Invalid values result in no change.
    if let Ok(quality) = args.get_string(activation, 0).parse() {
        activation
            .context
            .stage
            .set_quality(activation.context, quality);
    }
    Ok(Value::Undefined)
}

/// Implement `stage3Ds`'s getter
pub fn get_stage3ds<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(stage) = this.as_display_object().and_then(|this| this.as_stage()) {
        let storage = VectorStorage::from_values(
            stage.stage3ds().iter().map(|s| (*s).into()).collect(),
            false,
            Some(activation.avm2().classes().stage3d.inner_class_definition()),
        );
        let stage3ds = VectorObject::from_vector(storage, activation);
        return Ok(stage3ds.into());
    }
    Ok(Value::Undefined)
}

/// Implement `invalidate`
pub fn invalidate<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(stage) = this.as_display_object().and_then(|this| this.as_stage()) {
        stage.set_invalidated(true);
    }
    Ok(Value::Undefined)
}

/// Stage.fullScreenHeight's getter
///
/// Timffle: the screen height Flash reports, the same number as
/// `Capabilities.screenResolutionY` (Flash Player 32 returns the monitor
/// size for both).
pub fn get_full_screen_height<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok((screen_resolution(activation).1 as u32).into())
}

/// Stage.fullScreenWidth's getter
///
/// Timffle: see `fullScreenHeight`.
pub fn get_full_screen_width<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok((screen_resolution(activation).0 as u32).into())
}

pub fn set_tab_children<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(stage) = this.as_display_object().and_then(|this| this.as_stage()) {
        // TODO FP actually refers here to the original root,
        //      even if it has been removed.
        //      See the test tab_ordering_stage_tab_children_remove_root.
        if let Some(root) = stage.root_clip()
            && let Some(root) = root.as_container()
        {
            // Stage's tabChildren setter just propagates the value to the AVM2 root.
            // It does not affect the value of tabChildren of the stage, which is always true.
            let value = args.get_bool(0);
            root.set_tab_children(activation.context, value);
        }
    }

    Ok(Value::Undefined)
}
