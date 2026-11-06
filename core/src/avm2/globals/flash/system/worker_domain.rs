//! `flash.system.WorkerDomain` native methods

use crate::avm2::Error;
use crate::avm2::activation::Activation;
use crate::avm2::function::FunctionArgs;
use crate::avm2::object::WorkerDomainObject;
use crate::avm2::value::Value;

// Timffle: `WorkerDomain.createWorker` moved to WorkerDomain.as (it answers
// null, as Flash does without concurrency).

pub fn instantiate_internal<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let worker_domain = WorkerDomainObject::new(activation);

    Ok(worker_domain.into())
}
