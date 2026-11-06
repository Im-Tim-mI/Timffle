//! Timffle: `flash.printing.PrintJob` natives -- the player-wide job slot.
//!
//! Flash Player allows one PrintJob in use at a time: constructing another while a job
//! that was neither sent nor failed to start is alive throws IllegalOperationError
//! #2141 (measured on Flash Player 32). The slot holds the job weakly, so a job that
//! is collected frees it.

use crate::avm2::Error;
use crate::avm2::Object;
use crate::avm2::activation::Activation;
use crate::avm2::function::FunctionArgs;
use crate::avm2::object::TObject;
use crate::avm2::parameters::ParametersExt;
use crate::avm2::value::Value;

/// `PrintJob.claimSlot(job)`: takes the slot for `job` unless another live job holds it.
pub fn claim_slot<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let job = args.get_object(activation, 0, "job")?;
    let mc = activation.gc();
    if let Some(holder) = activation.avm2().print_job_slot.and_then(|w| w.upgrade(mc))
        && !Object::ptr_eq(holder, job)
    {
        return Ok(false.into());
    }
    activation.avm2().print_job_slot = Some(job.downgrade());
    Ok(true.into())
}

/// `PrintJob.releaseSlot(job)`: frees the slot if `job` holds it.
pub fn release_slot<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let job = args.get_object(activation, 0, "job")?;
    if let Some(holder) = activation.avm2().print_job_slot
        && std::ptr::eq(holder.as_ptr(), job.as_ptr())
    {
        activation.avm2().print_job_slot = None;
    }
    Ok(Value::Undefined)
}
