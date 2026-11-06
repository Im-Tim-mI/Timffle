use crate::avm2::Error;
use crate::avm2::activation::Activation;
use crate::avm2::error::make_agal_upload_error;
use crate::avm2::function::FunctionArgs;
use crate::avm2::parameters::ParametersExt;
use crate::avm2::value::Value;

pub fn upload<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(this) = this.as_program_3d() {
        this.check_disposed(activation)?; // Timffle
        this.context3d().check_disposed(activation)?;
        let vertex_agal = args.get_object(activation, 0, "source_vertex")?;
        let vertex_agal = vertex_agal
            .as_bytearray()
            .expect("Parameter must be a ByteArray");
        let vertex_agal = vertex_agal.bytes().to_vec();
        let vertex_len = vertex_agal.len();

        let fragment_agal = args.get_object(activation, 1, "source_fragment")?;
        let fragment_agal = fragment_agal
            .as_bytearray()
            .expect("Parameter must be a ByteArray");
        let fragment_agal = fragment_agal.bytes().to_vec();
        let fragment_len = fragment_agal.len();

        this.context3d()
            .upload_shaders(this, vertex_agal, fragment_agal)
            .map_err(|e| make_agal_upload_error(activation, e))?;
        // Timffle: the uploaded program counts towards Context3D.totalGPUMemory.
        this.set_gpu_size((vertex_len + fragment_len) as u64);
    }
    Ok(Value::Undefined)
}

// Timffle: dispose() releases the GPU resource; using the object afterwards
// throws Error #3694 ("The object was disposed by an earlier call of dispose() on it").
pub fn dispose<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    if let Some(obj) = this.as_program_3d() {
        obj.dispose();
    }
    Ok(Value::Undefined)
}
