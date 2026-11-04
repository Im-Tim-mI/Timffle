use crate::avm2::bytearray::Endian;
use crate::avm2::error::{
    Error2004Type, make_error_1126, make_error_2004, make_error_2007, make_error_2162,
    make_error_2164, make_error_2165, make_error_2172,
};
use crate::avm2::function::FunctionArgs;
use crate::avm2::globals::slots::{
    flash_display_shader as shader_slots, flash_display_shader_input as shader_input_slots,
    flash_display_shader_job as shader_job_slots,
    flash_display_shader_parameter as shader_parameter_slots,
};
use crate::avm2::object::EventObject;
use crate::avm2::parameters::ParametersExt;
use crate::avm2::{Activation, Avm2, Error, Object, TObject as _, Value};
use crate::context::UpdateContext;
use crate::pixel_bender::PixelBenderTypeExt;
use crate::string::AvmString;

use gc_arena::Collect;

use ruffle_render::backend::{PixelBenderOutput, PixelBenderTarget};
use ruffle_render::bitmap::PixelRegion;
use ruffle_render::pixel_bender::{
    OUT_COORD_NAME, PixelBenderMetadata, PixelBenderParam, PixelBenderParamQualifier,
    PixelBenderShaderHandle, PixelBenderType, PixelBenderTypeOpcode,
};
use ruffle_render::pixel_bender_support::{
    FloatPixelData, ImageInputTexture, PixelBenderShaderArgument,
};

/// Get the default value for a shader parameter from its metadata.
/// If no default is found, returns a empty value of the appropriate type.
fn get_default_shader_param_value(
    metadata: &[PixelBenderMetadata],
    param_type: PixelBenderTypeOpcode,
) -> PixelBenderType {
    for meta in metadata {
        if meta.key == "defaultValue" {
            return meta.value.clone();
        }
    }

    match param_type {
        PixelBenderTypeOpcode::TFloat => PixelBenderType::TFloat(0.0),
        PixelBenderTypeOpcode::TFloat2 => PixelBenderType::TFloat2(0.0, 0.0),
        PixelBenderTypeOpcode::TFloat3 => PixelBenderType::TFloat3(0.0, 0.0, 0.0),
        PixelBenderTypeOpcode::TFloat4 => PixelBenderType::TFloat4(0.0, 0.0, 0.0, 0.0),
        PixelBenderTypeOpcode::TFloat2x2 => PixelBenderType::TFloat2x2([0.0; 4]),
        PixelBenderTypeOpcode::TFloat3x3 => PixelBenderType::TFloat3x3([0.0; 9]),
        PixelBenderTypeOpcode::TFloat4x4 => PixelBenderType::TFloat4x4([0.0; 16]),
        PixelBenderTypeOpcode::TInt => PixelBenderType::TInt(0),
        PixelBenderTypeOpcode::TInt2 => PixelBenderType::TInt2(0, 0),
        PixelBenderTypeOpcode::TInt3 => PixelBenderType::TInt3(0, 0, 0),
        PixelBenderTypeOpcode::TInt4 => PixelBenderType::TInt4(0, 0, 0, 0),
        PixelBenderTypeOpcode::TString => PixelBenderType::TString(String::new()),
        PixelBenderTypeOpcode::TBool => PixelBenderType::TBool(0),
        PixelBenderTypeOpcode::TBool2 => PixelBenderType::TBool2(0, 0),
        PixelBenderTypeOpcode::TBool3 => PixelBenderType::TBool3(0, 0, 0),
        PixelBenderTypeOpcode::TBool4 => PixelBenderType::TBool4(0, 0, 0, 0),
    }
}

pub fn get_shader_args<'gc>(
    shader_obj: Object<'gc>,
    activation: &mut Activation<'_, 'gc>,
) -> Result<
    (
        PixelBenderShaderHandle,
        Vec<PixelBenderShaderArgument<'static>>,
    ),
    Error<'gc>,
> {
    // FIXME - determine what errors Flash Player throws here
    // instead of using `expect`
    let shader_data = shader_obj
        .get_slot(shader_slots::_DATA)
        .as_object()
        .expect("Missing ShaderData object")
        .as_shader_data()
        .expect("ShaderData object is not a ShaderData instance");

    let shader_handle = shader_data.pixel_bender_shader();
    let shader_handle = shader_handle
        .as_ref()
        .expect("ShaderData object has no shader");
    let shader = shader_handle.0.parsed_shader();

    let args = shader
        .params
        .iter()
        .enumerate()
        .filter(|(_, param)| {
            !matches!(
                param,
                PixelBenderParam::Normal {
                    qualifier: PixelBenderParamQualifier::Output,
                    ..
                }
            )
        })
        .map(|(index, param)| {
            match param {
                PixelBenderParam::Normal {
                    param_type,
                    name,
                    metadata,
                    ..
                } => {
                    if name == OUT_COORD_NAME {
                        // Pass in a dummy value - this will be ignored in favor of the actual pixel coordinate
                        return Ok(PixelBenderShaderArgument::ValueInput {
                            index: index as u8,
                            value: PixelBenderType::TFloat2(f32::NAN, f32::NAN),
                        });
                    }
                    let shader_param = shader_data
                        .get_dynamic_property(AvmString::new_utf8(activation.gc(), name))
                        .expect("Missing normal property");

                    let pb_val = if let Some(shader_param) = shader_param.as_object()
                        && shader_param.is_of_type(
                            activation
                                .avm2()
                                .classes()
                                .shaderparameter
                                .inner_class_definition(),
                        ) {
                        let value = shader_param.get_slot(shader_parameter_slots::_VALUE);
                        PixelBenderType::from_avm2_value(activation, value, param_type)?
                    } else {
                        // The ShaderParameter was replaced with a primitive or non-ShaderParameter object.
                        // Flash ignores this and uses the default value from shader metadata.
                        get_default_shader_param_value(metadata, *param_type)
                    };

                    Ok(PixelBenderShaderArgument::ValueInput {
                        index: index as u8,
                        value: pb_val,
                    })
                }
                PixelBenderParam::Texture {
                    index,
                    channels,
                    name,
                } => {
                    let shader_input = shader_data
                        .get_dynamic_property(AvmString::new_utf8(activation.gc(), name))
                        .expect("Missing property")
                        .as_object()
                        .expect("Shader input is not an object");

                    if !shader_input.is_of_type(
                        activation
                            .avm2()
                            .classes()
                            .shaderinput
                            .inner_class_definition(),
                    ) {
                        panic!("Expected shader input to be of class ShaderInput");
                    }

                    let input = shader_input.get_slot(shader_input_slots::_INPUT);

                    let width = shader_input.get_slot(shader_input_slots::_WIDTH).as_u32();
                    let height = shader_input.get_slot(shader_input_slots::_HEIGHT).as_u32();

                    let input_channels = shader_input
                        .get_slot(shader_input_slots::_CHANNELS)
                        .as_u32();

                    assert_eq!(*channels as u32, input_channels);

                    let texture = if let Some(input) = input.as_object() {
                        let input_texture = if let Some(bitmap) = input.as_bitmap_data() {
                            ImageInputTexture::Bitmap(
                                bitmap.bitmap_handle(activation.gc(), activation.context.renderer),
                            )
                        } else if let Some(byte_array) = input.as_bytearray() {
                            assert_eq!(byte_array.endian(), Endian::Little);

                            let (bytes, _) = byte_array.bytes().as_chunks::<4>();
                            let floats = bytemuck::cast_slice::<[u8; 4], f32>(bytes);

                            make_float_texture(
                                activation,
                                name,
                                floats,
                                width,
                                height,
                                input_channels,
                            )?
                        } else if let Some(vector) = input.as_vector_storage() {
                            let values: &[Value<'gc>] = vector.storage().as_ref();

                            make_float_texture(
                                activation,
                                name,
                                values,
                                width,
                                height,
                                input_channels,
                            )?
                        } else {
                            panic!("Unexpected input object {input:?}");
                        };
                        Some(input_texture)
                    } else {
                        // Null input
                        None
                    };

                    Ok(PixelBenderShaderArgument::ImageInput {
                        index: *index,
                        channels: *channels,
                        name: name.clone(),
                        texture,
                    })
                }
            }
        })
        .collect::<Result<Vec<PixelBenderShaderArgument<'_>>, Error<'gc>>>()?;
    Ok((shader_handle.clone(), args))
}

trait PixelSource {
    fn collect<const N: usize>(&self, num_pixels: usize) -> Option<Vec<[f32; N]>>;
}

impl PixelSource for &[f32] {
    fn collect<const N: usize>(&self, num_pixels: usize) -> Option<Vec<[f32; N]>> {
        let (floats, _) = self.as_chunks::<N>();
        Some(floats.get(..num_pixels)?.to_vec())
    }
}

impl<'gc> PixelSource for &[Value<'gc>] {
    fn collect<const N: usize>(&self, num_pixels: usize) -> Option<Vec<[f32; N]>> {
        let (chunks, _) = self.as_chunks::<N>();
        Some(
            chunks
                .get(..num_pixels)?
                .iter()
                .map(|vals| vals.map(|val| val.as_f64() as f32))
                .collect(),
        )
    }
}

fn make_float_texture<'gc, S: PixelSource>(
    activation: &mut Activation<'_, 'gc>,
    shader_name: &str,
    source: S,
    width: u32,
    height: u32,
    input_channels: u32,
) -> Result<ImageInputTexture<'static>, Error<'gc>> {
    let num_pixels = (width * height) as usize;
    let err = || make_error_2165(activation, shader_name);

    let data = match input_channels {
        1 => FloatPixelData::R(source.collect::<1>(num_pixels).ok_or_else(err)?),
        2 => FloatPixelData::Rg(source.collect::<2>(num_pixels).ok_or_else(err)?),
        3 => FloatPixelData::Rgb(source.collect::<3>(num_pixels).ok_or_else(err)?),
        4 => FloatPixelData::Rgba(source.collect::<4>(num_pixels).ok_or_else(err)?),
        _ => panic!("Unexpected number of channels: {input_channels}"),
    };

    Ok(ImageInputTexture::Floats {
        width,
        height,
        data,
    })
}

// Timffle: `ShaderJob._state` values (see ShaderJob.as).
const STATE_NEW: i32 = 0;
const STATE_QUEUED: i32 = 1;
const STATE_DONE: i32 = 2;

/// Timffle: a `ShaderJob` started with `start(false)`, waiting for the end of the script turn.
/// The shader handle and arguments are copied at `start()` time like Flash copies the Shader.
#[derive(Collect)]
#[collect(no_drop)]
pub struct PendingShaderJob<'gc> {
    job: Object<'gc>,
    #[collect(require_static)]
    shader: PixelBenderShaderHandle,
    #[collect(require_static)]
    arguments: Vec<PixelBenderShaderArgument<'static>>,
}

/// Implements `ShaderJob.start`.
///
/// Timffle: validates like Flash Player 32 (measured in D58Misc / D59ShaderQueue): a second
/// `start()` on the same job is ArgumentError #2172; `shader` / `target` null are TypeError #2007;
/// a target that is not BitmapData / ByteArray / Vector.<Number>, or a zero `width` / `height`
/// with a ByteArray / Vector target, is ArgumentError #2004; an image input without data is
/// ArgumentError #2164; a fixed Vector target is RangeError #1126. `start(true)` runs now,
/// `start(false)` queues the job (target untouched until it runs, `progress` 0).
pub fn start<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let wait_for_completion = args.get_bool(0);

    if this
        .get_slot(shader_job_slots::_STATE)
        .coerce_to_i32(activation)?
        != STATE_NEW
    {
        return Err(make_error_2172(activation));
    }

    let Some(shader) = this.get_slot(shader_job_slots::_SHADER).as_object() else {
        return Err(make_error_2007(activation, "shader"));
    };
    let target = this.get_slot(shader_job_slots::_TARGET);
    if matches!(target, Value::Null | Value::Undefined) {
        return Err(make_error_2007(activation, "target"));
    }
    let Some(target) = target.as_object() else {
        // A primitive (e.g. a String) target.
        return Err(make_error_2004(activation, Error2004Type::ArgumentError));
    };

    let is_bitmap = target.as_bitmap_data().is_some();
    if !is_bitmap && target.as_bytearray().is_none() {
        match target.as_vector_storage() {
            Some(vector) if vector.is_fixed() => return Err(make_error_1126(activation)),
            Some(_) => {}
            None => return Err(make_error_2004(activation, Error2004Type::ArgumentError)),
        }
    }
    if !is_bitmap {
        let output_width = this.get_slot(shader_job_slots::_WIDTH).as_i32();
        let output_height = this.get_slot(shader_job_slots::_HEIGHT).as_i32();
        if output_width <= 0 || output_height <= 0 {
            return Err(make_error_2004(activation, Error2004Type::ArgumentError));
        }
    }

    let (shader_handle, arguments) = get_shader_args(shader, activation)?;

    for argument in &arguments {
        if let PixelBenderShaderArgument::ImageInput {
            texture: None,
            name,
            ..
        } = argument
        {
            return Err(make_error_2164(activation, name));
        }
    }

    match shader_handle.0.parsed_shader().output_channels() {
        Some(3 | 4) => {}
        channels => {
            tracing::warn!(
                "Unsupported number of shader output channels: {channels:?}, expected 3 or 4"
            );
            return Err(make_error_2162(activation));
        }
    }

    this.set_slot(shader_job_slots::_STATE, STATE_QUEUED.into(), activation)?;
    this.set_slot(shader_job_slots::_PROGRESS, 0.0.into(), activation)?;

    let pending = PendingShaderJob {
        job: this,
        shader: shader_handle,
        arguments,
    };
    if wait_for_completion {
        run_job(activation, pending, false)?;
    } else {
        activation.context.avm2.shader_jobs.push(pending);
    }

    Ok(Value::Undefined)
}

/// Timffle: runs the background jobs queued by `start(false)`, in order, and dispatches their
/// `complete` events. Called by `Player::run_actions` at the end of each script turn.
pub fn run_pending(context: &mut UpdateContext<'_>) {
    while !context.avm2.shader_jobs.is_empty() {
        let pending = context.avm2.shader_jobs.remove(0);
        let mut activation = Activation::from_nothing(context);
        if let Err(error) = run_job(&mut activation, pending, true) {
            tracing::error!("Background ShaderJob failed: {error:?}");
        }
    }
}

/// Timffle: executes one job and writes its result into the target (nothing is written into a
/// disposed BitmapData, but the job still completes). With `dispatch`, a `ShaderEvent.COMPLETE`
/// carrying the target is dispatched on the job afterwards.
fn run_job<'gc>(
    activation: &mut Activation<'_, 'gc>,
    pending: PendingShaderJob<'gc>,
    dispatch: bool,
) -> Result<(), Error<'gc>> {
    let PendingShaderJob {
        job: this,
        shader: shader_handle,
        arguments,
    } = pending;

    if this
        .get_slot(shader_job_slots::_STATE)
        .coerce_to_i32(activation)?
        != STATE_QUEUED
    {
        // Cancelled while queued: no result, no event.
        return Ok(());
    }

    let target = this
        .get_slot(shader_job_slots::_TARGET)
        .as_object()
        .expect("ShaderJob.target is not an object");

    let output_width = this.get_slot(shader_job_slots::_WIDTH).as_u32();

    let output_height = this.get_slot(shader_job_slots::_HEIGHT).as_u32();

    let disposed_bitmap = target
        .as_bitmap_data()
        .is_some_and(|bitmap| bitmap.disposed());

    if !disposed_bitmap {
        let pixel_bender_target = if let Some(bitmap) = target.as_bitmap_data() {
            let target_bitmap = bitmap.sync(activation.context.renderer);
            // Perform both a GPU->CPU and CPU->GPU sync before writing to it.
            // FIXME - are both necessary?
            let mut target_bitmap_data = target_bitmap.borrow_mut(activation.gc());
            target_bitmap_data.update_dirty_texture(activation.context.renderer);

            PixelBenderTarget::Bitmap(target_bitmap_data.bitmap_handle(activation.context.renderer))
        } else {
            PixelBenderTarget::Bytes {
                width: output_width,
                height: output_height,
            }
        };

        let output = activation
            .context
            .renderer
            .run_pixelbender_shader(shader_handle, &arguments, &pixel_bender_target)
            .expect("Failed to run shader");

        match output {
            PixelBenderOutput::Bitmap(sync_handle) => {
                let target_bitmap = target
                    .as_bitmap_data()
                    .unwrap()
                    .sync(activation.context.renderer);
                let mut target_bitmap_data = target_bitmap.borrow_mut(activation.gc());
                let width = target_bitmap_data.width();
                let height = target_bitmap_data.height();
                target_bitmap_data.set_gpu_dirty(
                    activation.gc(),
                    sync_handle,
                    PixelRegion::for_whole_size(width, height),
                );
            }
            PixelBenderOutput::Bytes(pixels) => {
                if let Some(mut bytearray) = target.as_bytearray_mut() {
                    // Timffle: the floats are written in the ByteArray's own byte order, so
                    // readFloat() gives them back (Flash Player 32 returns the right values
                    // from a default big-endian ByteArray).
                    let floats = bytemuck::cast_slice::<u8, f32>(&pixels);
                    let mut ordered = Vec::with_capacity(pixels.len());
                    for float in floats {
                        match bytearray.endian() {
                            Endian::Big => ordered.extend_from_slice(&float.to_be_bytes()),
                            Endian::Little => ordered.extend_from_slice(&float.to_le_bytes()),
                        }
                    }
                    bytearray.write_at(&ordered, 0).unwrap();
                } else if let Some(mut vector) = target.as_vector_storage_mut(activation.gc()) {
                    let new_values = bytemuck::cast_slice::<u8, f32>(&pixels)
                        .iter()
                        .map(|p| Value::from(*p as f64));
                    vector.replace_storage_with_iter(new_values);
                } else {
                    return Err(make_error_2004(activation, Error2004Type::ArgumentError));
                }
            }
        }
    }

    this.set_slot(shader_job_slots::_STATE, STATE_DONE.into(), activation)?;
    this.set_slot(shader_job_slots::_PROGRESS, 1.0.into(), activation)?;

    if dispatch {
        let (bitmap, bytes, vector) = if target.as_bitmap_data().is_some() {
            (target.into(), Value::Null, Value::Null)
        } else if target.as_bytearray().is_some() {
            (Value::Null, target.into(), Value::Null)
        } else {
            (Value::Null, Value::Null, target.into())
        };
        let shader_event_class = activation.avm2().classes().shaderevent;
        let event = EventObject::from_class_and_args(
            activation,
            shader_event_class,
            &[
                AvmString::new_utf8(activation.gc(), "complete").into(),
                false.into(),
                false.into(),
                bitmap,
                bytes,
                vector,
            ],
        );
        Avm2::dispatch_event(activation.context, event, this);
    }

    Ok(())
}
