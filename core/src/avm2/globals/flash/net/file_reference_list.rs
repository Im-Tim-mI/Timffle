//! Timffle: `flash.net.FileReferenceList` natives.

use crate::avm2::error::make_error_2041;
use crate::avm2::function::FunctionArgs;
use crate::avm2::globals::flash::net::file_reference::parse_file_filters;
use crate::avm2::parameters::ParametersExt;
use crate::avm2::{Activation, Error, Value};

/// `FileReferenceList.browse()`: opens the multi-file dialog. The filters are validated like
/// `FileReference.browse()` (#2097); a dialog that is already open is #2041 like Flash Player.
pub fn browse<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let filters = parse_file_filters(activation, args.try_get_object(0))?;

    let dialog = activation
        .context
        .ui
        .display_file_open_dialog_multiple(filters);
    let Some(dialog) = dialog else {
        return Err(make_error_2041(activation));
    };

    let process = crate::loader::select_multi_file_dialog_avm2(activation.context, this, dialog);
    activation.context.navigator.spawn_future(process);

    Ok(true.into())
}
