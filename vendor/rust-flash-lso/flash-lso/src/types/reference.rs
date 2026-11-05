/// A reference to an existing value
#[cfg_attr(feature = "serde", derive(Serialize, Deserialize))]
#[derive(Copy, Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
// Timffle: public so that the AVM2 serializer can emit AMF0 references itself.
pub struct Reference(pub u16);
