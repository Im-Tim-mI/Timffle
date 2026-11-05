//! Support for decoding AMF0 data
use crate::amf0::type_marker::TypeMarker;
use nom::Parser;

use crate::PADDING;
#[cfg(feature = "amf3")]
use crate::amf3;
use crate::nom_utils::{AMFResult, take_str};
use crate::types::{ClassDefinition, Element, ObjectId, Reference, Value};
use nom::Err;
use nom::bytes::complete::{tag, take};
use nom::combinator::{map, map_res};
use nom::error::{ErrorKind, make_error};
use nom::multi::{many_m_n, many0};
use nom::number::complete::{be_f64, be_u8, be_u16, be_u32};
use std::convert::{TryFrom, TryInto};
use std::rc::Rc;

pub(crate) fn parse_string(i: &[u8]) -> AMFResult<'_, &str> {
    let (i, length) = be_u16(i)?;
    take_str(i, length)
}

fn parse_element_number(i: &[u8]) -> AMFResult<'_, Rc<Value>> {
    let (i, v) = be_f64(i)?;
    Ok((i, Rc::new(Value::Number(v))))
}

fn parse_element_bool(i: &[u8]) -> AMFResult<'_, Rc<Value>> {
    let (i, v) = be_u8(i)?;
    Ok((i, Rc::new(Value::Bool(v > 0))))
}

fn parse_element_string(i: &[u8]) -> AMFResult<'_, Rc<Value>> {
    let (i, v) = parse_string(i)?;
    Ok((i, Rc::new(Value::String(v.to_string()))))
}

fn parse_element_date(i: &[u8]) -> AMFResult<'_, Rc<Value>> {
    let (i, millis) = be_f64(i)?;
    let (i, time_zone) = be_u16(i)?;

    Ok((i, Rc::new(Value::Date(millis, Some(time_zone)))))
}

fn parse_long_string_internal(i: &[u8]) -> AMFResult<'_, &str> {
    let (i, length) = be_u32(i)?;
    map_res(take(length), std::str::from_utf8).parse(i)
}

fn parse_element_long_string(i: &[u8]) -> AMFResult<'_, Rc<Value>> {
    let (i, str) = parse_long_string_internal(i)?;
    Ok((i, Rc::new(Value::String(str.to_string()))))
}

fn parse_element_xml(i: &[u8]) -> AMFResult<'_, Rc<Value>> {
    let (i, content) = parse_long_string_internal(i)?;
    Ok((i, Rc::new(Value::XML(content.to_string(), true))))
}

fn read_type_marker(i: &[u8]) -> AMFResult<'_, TypeMarker> {
    let (i, type_) = be_u8(i)?;
    Ok((
        i,
        TypeMarker::try_from(type_).unwrap_or(TypeMarker::Unsupported),
    ))
}

/// Timffle: AMF0 complex objects (anonymous/typed objects, ECMA and strict arrays) read by
/// [`AMF0Decoder`] carry `ObjectId(AMF0_REFERENCE_ID_BASE + index)`, where `index` is their
/// position in the AMF0 reference table (complex objects only, in order of occurrence, as
/// the AMF0 specification 2.9 defines it), so that a later `Value::Reference(index)` can be
/// resolved by the consumer; the offset keeps them apart from AMF3 ids (which count from 0)
/// when AMF3 values are embedded in AMF0.
pub const AMF0_REFERENCE_ID_BASE: i64 = 1 << 32;

/// Handles decoding AMF0
#[derive(Default)]
pub struct AMF0Decoder {
    /// Cache of previously read values, that can be referenced later
    ///
    /// Every value read enters this cache (primitives too): Flash Player's AVM1 shared
    /// object writer numbers references that way (see `shared_object_self_ref`), and
    /// [`AMF0Decoder::as_reference`] serves the AVM1 reader with the same numbering.
    cache: Vec<Rc<Value>>,

    /// Timffle: the number of complex objects read so far, the AMF0 specification's
    /// reference-table index of the next one (see [`AMF0_REFERENCE_ID_BASE`]).
    complex_count: i64,

    #[cfg(feature = "amf3")]
    amf3_decoder: amf3::read::AMF3Decoder,
}

impl AMF0Decoder {
    fn parse_element_reference<'a>(&self, i: &'a [u8]) -> AMFResult<'a, Rc<Value>> {
        let (i, reference_index) = be_u16(i)?;

        Ok((i, Rc::new(Value::Reference(Reference(reference_index)))))
    }

    fn parse_element_ecma_array<'a>(&mut self, i: &'a [u8]) -> AMFResult<'a, Rc<Value>> {
        let (i, array_length) = be_u32(i)?;
        let id = self.claim_reference_id(); // Timffle
        map(
            |i| self.parse_array_element(i),
            move |elms: Vec<Element>| Rc::new(Value::ECMAArray(id, Vec::new(), elms, array_length)),
        )
        .parse(i)
    }

    fn parse_element_typed_object<'a>(&mut self, i: &'a [u8]) -> AMFResult<'a, Rc<Value>> {
        let (i, name) = parse_string(i)?;
        let id = self.claim_reference_id(); // Timffle

        map(
            |i| self.parse_array_element(i),
            move |elms: Vec<Element>| {
                Rc::new(Value::Object(
                    id,
                    elms,
                    Some(ClassDefinition::default_with_name(name.to_string())),
                ))
            },
        )
        .parse(i)
    }

    fn parse_element_object<'a>(&mut self, i: &'a [u8]) -> AMFResult<'a, Rc<Value>> {
        let id = self.claim_reference_id(); // Timffle
        let (i, v) = self.parse_array_element(i)?;
        Ok((i, Rc::new(Value::Object(id, v, None))))
    }

    /// Timffle: takes the next AMF0 reference-table index for a complex object that is
    /// about to be read (the table is indexed by order of occurrence, parents before their
    /// children, so a self-reference inside the object resolves) and returns the
    /// `ObjectId` that marks it.
    fn claim_reference_id(&mut self) -> ObjectId {
        let id = ObjectId(AMF0_REFERENCE_ID_BASE + self.complex_count);
        self.complex_count += 1;
        id
    }

    #[cfg(fuzzing)]
    /// For fuzzing
    pub fn fuzz_parse_element_array<'a>(&mut self, i: &'a [u8]) -> AMFResult<'a, Rc<Value>> {
        self.parse_element_strict_array(i)
    }

    /// Parse an array of elements
    fn parse_element_strict_array<'a>(&mut self, i: &'a [u8]) -> AMFResult<'a, Rc<Value>> {
        let (i, length) = be_u32(i)?;

        let length_usize = length
            .try_into()
            .map_err(|_| Err::Error(make_error(i, ErrorKind::Digit)))?;

        // There must be at least `length_usize` bytes (u8) to read this, this prevents OOM errors with v.large arrays
        if i.len() < length_usize {
            return Err(Err::Error(make_error(i, ErrorKind::TooLarge)));
        }

        let id = self.claim_reference_id(); // Timffle
        // This must parse length elements
        let (i, elements) =
            many_m_n(length_usize, length_usize, |i| self.parse_single_element(i)).parse(i)?;

        Ok((i, Rc::new(Value::StrictArray(id, elements))))
    }

    fn parse_array_element<'a>(&mut self, i: &'a [u8]) -> AMFResult<'a, Vec<Element>> {
        let mut out = Vec::new();

        let mut i = i;
        loop {
            let (k, _) = parse_string(i)?;
            let (k, next_type) = read_type_marker(k)?;
            if next_type == TypeMarker::ObjectEnd {
                i = k;
                break;
            }

            let (j, e) = self.parse_element(i)?;
            i = j;

            out.push(e.clone());
        }

        Ok((i, out))
    }

    fn parse_element_amf3<'a>(&mut self, i: &'a [u8]) -> AMFResult<'a, Rc<Value>> {
        #[cfg(feature = "amf3")]
        {
            let (i, x) = self.amf3_decoder.parse_single_element(i)?;
            Ok((i, Rc::new(Value::AMF3(x))))
        }
        #[cfg(not(feature = "amf3"))]
        {
            Ok((i, Rc::new(Value::Unsupported)))
        }
    }

    /// Parse a single AMF0 element
    pub fn parse_single_element<'a>(&mut self, i: &'a [u8]) -> AMFResult<'a, Rc<Value>> {
        // Get the type of the next element
        let (i, type_) = read_type_marker(i)?;

        let cache_idx = self.cache.len();
        self.cache.push(Rc::new(Value::Undefined));

        let (i, v) = match type_ {
            TypeMarker::Number => parse_element_number(i),
            TypeMarker::Boolean => parse_element_bool(i),
            TypeMarker::String => parse_element_string(i),
            TypeMarker::Object => {
                let (i, v) = self.parse_element_object(i)?;
                self.cache[cache_idx] = Rc::clone(&v);
                Ok((i, v))
            }
            TypeMarker::Null => Ok((i, Rc::new(Value::Null))),
            TypeMarker::Undefined => Ok((i, Rc::new(Value::Undefined))),
            TypeMarker::Reference => {
                let (i, v) = self.parse_element_reference(i)?;
                Ok((i, v))
            }
            TypeMarker::ECMAArray => {
                let (i, v) = self.parse_element_ecma_array(i)?;
                self.cache[cache_idx] = Rc::clone(&v);
                Ok((i, v))
            }
            TypeMarker::StrictArray => {
                let (i, v) = self.parse_element_strict_array(i)?;
                self.cache[cache_idx] = Rc::clone(&v);
                Ok((i, v))
            }
            TypeMarker::Date => parse_element_date(i),
            TypeMarker::LongString => parse_element_long_string(i),
            TypeMarker::Unsupported => Ok((i, Rc::new(Value::Unsupported))),
            TypeMarker::Xml => parse_element_xml(i),
            TypeMarker::TypedObject => {
                let (i, v) = self.parse_element_typed_object(i)?;
                self.cache[cache_idx] = Rc::clone(&v);
                Ok((i, v))
            }
            TypeMarker::AMF3 => self.parse_element_amf3(i),
            TypeMarker::MovieClip | TypeMarker::RecordSet | TypeMarker::ObjectEnd => Err(
                Err::Error(crate::errors::Error::UnsupportedType(type_ as u8)),
            ),
        }?;

        Ok((i, v))
    }

    fn parse_element<'a>(&mut self, i: &'a [u8]) -> AMFResult<'a, Element> {
        let (i, name) = parse_string(i)?;

        map(
            |i| self.parse_single_element(i),
            move |v| Element {
                name: name.to_string(),
                value: v,
            },
        )
        .parse(i)
    }

    fn parse_element_and_padding<'a>(&mut self, i: &'a [u8]) -> AMFResult<'a, Element> {
        let (i, e) = self.parse_element(i)?;
        let (i, _) = tag(PADDING.as_slice())(i)?;

        Ok((i, e))
    }

    /// Parse a sequence of `PADDING` delimited `Values`
    pub fn parse_body<'a>(&mut self, i: &'a [u8]) -> AMFResult<'a, Vec<Element>> {
        many0(|i| self.parse_element_and_padding(i)).parse(i)
    }

    /// Convert the given value into a reference, if possible
    /// This reference is only valid for values sourced from this decoder and will only reference values decoded by it
    pub fn as_reference(&self, v: &Value) -> Option<Reference> {
        self.cache
            .iter()
            .position(|cv| *cv == Rc::new(v.clone()))
            .map(|r| Reference(r as _))
    }
}
