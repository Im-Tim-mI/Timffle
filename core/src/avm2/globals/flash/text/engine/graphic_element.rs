use crate::avm2::activation::Activation;
use crate::avm2::error::Error;
use crate::avm2::function::FunctionArgs;
use crate::avm2::object::ElementData;
use crate::avm2::parameters::ParametersExt;
use crate::avm2::value::Value;

pub fn init<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this
        .as_object()
        .unwrap()
        .as_content_element_object()
        .unwrap();

    let mut data = this.element_data_mut(activation.gc());
    // Timffle: real storage for `graphic` / `elementWidth` / `elementHeight`;
    // the constructor fills them in through the setters.
    *data = ElementData::Graphic {
        graphic: None,
        element_width: 15.0,
        element_height: 15.0,
    };

    Ok(Value::Undefined)
}

// Timffle: GraphicElement.graphic / elementWidth / elementHeight getters and
// setters over the stored data.
pub fn get_graphic<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this
        .as_object()
        .unwrap()
        .as_content_element_object()
        .unwrap();
    let data = this.element_data();
    let ElementData::Graphic { graphic, .. } = &*data else {
        unreachable!("Data can only have been set to Graphic");
    };
    Ok(graphic.map(Value::from).unwrap_or(Value::Null))
}

pub fn set_graphic<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this
        .as_object()
        .unwrap()
        .as_content_element_object()
        .unwrap();
    let value = args.try_get_object(0);
    let mut data = this.element_data_mut(activation.gc());
    if let ElementData::Graphic { graphic, .. } = &mut *data {
        *graphic = value;
    }
    Ok(Value::Undefined)
}

pub fn get_element_width<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this
        .as_object()
        .unwrap()
        .as_content_element_object()
        .unwrap();
    let data = this.element_data();
    let ElementData::Graphic { element_width, .. } = &*data else {
        unreachable!("Data can only have been set to Graphic");
    };
    Ok((*element_width).into())
}

pub fn set_element_width<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this
        .as_object()
        .unwrap()
        .as_content_element_object()
        .unwrap();
    let value = args.get_f64(0);
    let mut data = this.element_data_mut(activation.gc());
    if let ElementData::Graphic { element_width, .. } = &mut *data {
        *element_width = value;
    }
    Ok(Value::Undefined)
}

pub fn get_element_height<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this
        .as_object()
        .unwrap()
        .as_content_element_object()
        .unwrap();
    let data = this.element_data();
    let ElementData::Graphic { element_height, .. } = &*data else {
        unreachable!("Data can only have been set to Graphic");
    };
    Ok((*element_height).into())
}

pub fn set_element_height<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this
        .as_object()
        .unwrap()
        .as_content_element_object()
        .unwrap();
    let value = args.get_f64(0);
    let mut data = this.element_data_mut(activation.gc());
    if let ElementData::Graphic { element_height, .. } = &mut *data {
        *element_height = value;
    }
    Ok(Value::Undefined)
}
