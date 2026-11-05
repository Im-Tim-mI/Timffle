//! `flash.sampler` package functions
//!
//! Timffle: the reflective functions of the sampler package. Flash Player's AVM implements
//! these without the profiler (see `flash/sampler.as` for the ones that need it).

use crate::avm2::activation::Activation;
use crate::avm2::array::ArrayStorage;
use crate::avm2::function::FunctionArgs;
use crate::avm2::multiname::Multiname;
use crate::avm2::object::{ArrayObject, QNameObject, TObject};
use crate::avm2::parameters::ParametersExt;
use crate::avm2::property::Property;
use crate::avm2::value::Value;
use crate::avm2::{Error, Object};

/// Implements `flash.sampler.getMemberNames`: the QNames of every trait of the object (every
/// namespace, including private ones) followed by its dynamic properties. With
/// `instanceNames` true and a Class, the instance traits of that class are listed instead
/// of the class object's own. Non-objects answer `undefined`, like the AVM.
pub fn get_member_names<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let Some(obj) = args.try_get_object(0) else {
        return Ok(Value::Undefined);
    };
    let instance_names = args.get_bool(1);

    let vtable = match obj.as_class_object() {
        Some(class) if instance_names => class.instance_vtable(),
        _ => obj.vtable(),
    };

    let mut names: Vec<Option<Value<'gc>>> = Vec::new();
    for (name, ns, _) in vtable.resolved_traits().iter() {
        let qname = QNameObject::from_name(activation, Multiname::new(ns, name));
        names.push(Some(Value::Object(Object::from(qname))));
    }

    if !instance_names || obj.as_class_object().is_none() {
        let public_ns = activation.avm2().namespaces.public_all();
        let mut last_index = obj.get_next_enumerant(0, activation)?;
        while last_index != 0 {
            let name = obj.get_enumerant_name(last_index, activation)?;
            if !matches!(name, Value::Undefined | Value::Null) {
                let name = name.coerce_to_string(activation)?;
                let qname = QNameObject::from_name(activation, Multiname::new(public_ns, name));
                names.push(Some(Value::Object(Object::from(qname))));
            }
            last_index = obj.get_next_enumerant(last_index, activation)?;
        }
    }

    let array = ArrayObject::from_storage(activation.context, ArrayStorage::from_storage(names));
    Ok(Value::Object(Object::from(array)))
}

/// Implements `flash.sampler.isGetterSetter`: whether the named trait of the object is an
/// accessor (getter and/or setter) rather than a method or a slot.
pub fn is_getter_setter<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let Some(obj) = args.try_get_object(0) else {
        return Ok(false.into());
    };
    let Some(qname) = args.try_get_object(1).and_then(|q| q.as_qname_object()) else {
        return Ok(false.into());
    };

    let property = obj.vtable().get_trait(qname.name());
    Ok(matches!(property, Some(Property::Virtual { .. })).into())
}

/// Implements `flash.sampler.getSavedThis`: the receiver a bound method closure (`obj.method`
/// read as a value) always runs with; `undefined` for an unbound function or a non-function.
pub fn get_saved_this<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let Some(function) = args.try_get_function(0) else {
        return Ok(Value::Undefined);
    };
    Ok(function
        .executable()
        .bound_receiver()
        .unwrap_or(Value::Undefined))
}

/// Implements `flash.sampler.getLexicalScopes`: the objects on the closure's scope chain,
/// outermost first; `null` for a non-function (the AVM answers null when there is no
/// method closure to inspect).
pub fn get_lexical_scopes<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let Some(function) = args.try_get_function(0) else {
        return Ok(Value::Null);
    };

    let scope = function.executable().scope();
    let mut scopes = Vec::new();
    let mut index = 0;
    while let Some(entry) = scope.get(index) {
        scopes.push(Some(entry.values()));
        index += 1;
    }

    let array = ArrayObject::from_storage(activation.context, ArrayStorage::from_storage(scopes));
    Ok(Value::Object(Object::from(array)))
}
