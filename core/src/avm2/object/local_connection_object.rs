use crate::avm2::activation::Activation;
use crate::avm2::amf::deserialize_value_impl;
use crate::avm2::function::FunctionArgs;
use crate::avm2::object::script_object::ScriptObjectData;
use crate::avm2::object::{ClassObject, EventObject, Object, TObject};
use crate::avm2::value::Value;
use crate::avm2::{Avm2, Domain, Error};
use crate::context::UpdateContext;
use crate::local_connection::{LocalConnectionHandle, LocalConnections};
use crate::string::AvmString;
use core::fmt;
use flash_lso::types::Value as AmfValue;
use gc_arena::barrier::unlock;
use gc_arena::{Collect, Gc, GcWeak, Mutation, lock::Lock};
use ruffle_common::sandbox::{AllowedDomains, FlashOrigin};
use ruffle_common::utils::HasPrefixField;
use ruffle_macros::istr;
use std::cell::RefCell;

/// A class instance allocator that allocates LocalConnection objects.
pub fn local_connection_allocator<'gc>(
    class: ClassObject<'gc>,
    activation: &mut Activation<'_, 'gc>,
) -> Result<Object<'gc>, Error<'gc>> {
    let base = ScriptObjectData::new(class);

    let object = LocalConnectionObject(Gc::new(
        activation.gc(),
        LocalConnectionObjectData {
            base,
            connection_handle: RefCell::new(None),
            client: Lock::new(None),
            movie_url: activation.caller_movie_or_root().url().to_string(),
            allowed_domains: RefCell::new(AllowedDomains::default()),
        },
    ));

    object.set_client(activation.gc(), object.into());

    Ok(object.into())
}

#[derive(Clone, Collect, Copy)]
#[collect(no_drop)]
pub struct LocalConnectionObject<'gc>(pub Gc<'gc, LocalConnectionObjectData<'gc>>);

#[derive(Clone, Collect, Copy, Debug)]
#[collect(no_drop)]
pub struct LocalConnectionObjectWeak<'gc>(pub GcWeak<'gc, LocalConnectionObjectData<'gc>>);

impl fmt::Debug for LocalConnectionObject<'_> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("LocalConnectionObject")
            .field("ptr", &Gc::as_ptr(self.0))
            .finish()
    }
}

#[derive(Collect, HasPrefixField)]
#[collect(no_drop)]
#[repr(C, align(8))]
pub struct LocalConnectionObjectData<'gc> {
    /// Base script object
    base: ScriptObjectData<'gc>,

    connection_handle: RefCell<Option<LocalConnectionHandle>>,

    client: Lock<Option<Object<'gc>>>,

    /// Timffle: the URL of the SWF that created this object. Flash ties a
    /// LocalConnection to the sandbox of the file that created it: this is
    /// the domain `connect()` and `send()` qualify names with, and the
    /// domain other senders are checked against.
    movie_url: String,

    /// Timffle: the senders admitted by `allowDomain()` / `allowInsecureDomain()`.
    allowed_domains: RefCell<AllowedDomains>,
}

impl<'gc> LocalConnectionObject<'gc> {
    pub fn is_connected(self) -> bool {
        self.0.connection_handle.borrow().is_some()
    }

    pub fn client(self) -> Object<'gc> {
        self.0.client.get().expect("Client must be initialized")
    }

    pub fn set_client(&self, mc: &Mutation<'gc>, client: Object<'gc>) {
        unlock!(Gc::write(mc, self.0), LocalConnectionObjectData, client).set(Some(client));
    }

    /// Timffle: the URL of the SWF that created this object.
    pub fn movie_url(&self) -> &str {
        &self.0.movie_url
    }

    /// Timffle: `allowDomain()` (`insecure == false`) or
    /// `allowInsecureDomain()` (`insecure == true`).
    pub fn allow_domains<'a>(self, domains: impl IntoIterator<Item = &'a str>, insecure: bool) {
        let mut allowed = self.0.allowed_domains.borrow_mut();
        for domain in domains {
            allowed.allow(domain, insecure);
        }
    }

    /// Timffle: whether a `send()` from the SWF at `sender_url` may reach
    /// this (receiving) connection, as in Flash Player:
    ///
    /// - a non-HTTPS sender never reaches an HTTPS receiver unless the
    ///   receiver called `allowInsecureDomain()` for it (even in one domain);
    /// - senders in the receiver's superdomain are accepted by default (their
    ///   connection names resolve to the same `superdomain:name`);
    /// - every other sender needs `allowDomain()` / `allowInsecureDomain()`
    ///   with its domain, `*` (remote senders) or `localhost` (local files).
    pub fn accepts_sender(self, sender_url: &str) -> bool {
        let receiver = FlashOrigin::of(&self.0.movie_url);
        let sender = FlashOrigin::of(sender_url);
        let allowed = self.0.allowed_domains.borrow();
        if receiver.is_https() && !sender.is_https() {
            return allowed.allows_origin(&receiver, &sender);
        }
        if receiver.local == sender.local
            && LocalConnections::get_superdomain(&receiver.host)
                == LocalConnections::get_superdomain(&sender.host)
        {
            return true;
        }
        allowed.allows_origin(&receiver, &sender)
    }

    pub fn connect(self, activation: &mut Activation<'_, 'gc>, name: AvmString<'gc>) -> bool {
        if self.is_connected() {
            return false;
        }

        // Timffle: the connection belongs to the domain of the SWF that
        // created it, not necessarily the root SWF.
        let connection_handle = activation.context.local_connections.connect(
            &LocalConnections::get_domain(&self.0.movie_url),
            (activation.domain(), self),
            &name,
        );
        let result = connection_handle.is_some();

        *self.0.connection_handle.borrow_mut() = connection_handle;

        result
    }

    pub fn disconnect(self, activation: &mut Activation<'_, 'gc>) {
        if let Some(conn_handle) = self.0.connection_handle.borrow_mut().take() {
            activation.context.local_connections.close(conn_handle);
        }
    }

    pub fn send_status(self, context: &mut UpdateContext<'gc>, status: AvmString<'gc>) {
        let mut activation = Activation::from_nothing(context);

        let status_event_cls = activation.avm2().classes().statusevent;
        let event_name = istr!("status");
        let event = EventObject::from_class_and_args(
            &mut activation,
            status_event_cls,
            &[
                event_name.into(),
                false.into(),
                false.into(),
                Value::Null,
                status.into(),
            ],
        );

        Avm2::dispatch_event(activation.context, event, self.into());
    }

    pub fn run_method(
        self,
        context: &mut UpdateContext<'gc>,
        domain: Domain<'gc>,
        method_name: AvmString<'gc>,
        amf_arguments: Vec<AmfValue>,
    ) {
        let mut activation = Activation::from_domain(context, domain);
        let mut arguments = Vec::with_capacity(amf_arguments.len());

        // One object map for all arguments: an object passed twice (or referenced
        // from two arguments) arrives as the same object, as in Flash.
        let mut object_map = Default::default();
        for argument in amf_arguments {
            arguments.push(
                deserialize_value_impl(&mut activation, &argument, &mut object_map)
                    .unwrap_or(Value::Undefined),
            );
        }
        let arguments = FunctionArgs::from_slice(&arguments);

        let client = Value::from(self.client());
        if !self.client().instance_class().is_sealed()
            && !client.has_public_property(method_name, &mut activation)
        {
            return;
        }
        if let Err(e) = client.call_public_property(method_name, arguments, &mut activation) {
            match e.as_avm_error() {
                Some(error) => {
                    let event_name = istr!("asyncError");
                    let async_error_event_cls = activation.avm2().classes().asyncerrorevent;

                    let text = AvmString::new_utf8(
                        activation.gc(),
                        format!(
                            "Error #2095: flash.net.LocalConnection was unable to invoke callback {method_name}."
                        ),
                    );

                    let event = EventObject::from_class_and_args(
                        &mut activation,
                        async_error_event_cls,
                        &[
                            event_name.into(),
                            false.into(),
                            false.into(),
                            text.into(),
                            error,
                        ],
                    );

                    Avm2::dispatch_event(activation.context, event, self.into());
                }
                _ => {
                    tracing::error!(
                        "Unhandled error dispatching AVM2 LocalConnection method call to '{method_name}': {e}"
                    );
                }
            }
        }
    }
}

impl<'gc> TObject<'gc> for LocalConnectionObject<'gc> {
    fn gc_base(&self) -> Gc<'gc, ScriptObjectData<'gc>> {
        HasPrefixField::as_prefix_gc(self.0)
    }
}
